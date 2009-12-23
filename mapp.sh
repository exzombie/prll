# Copyright 2009 Jure Varlec
# This program is free software. It comes without any warranty, to
# the extent permitted by applicable law. You can redistribute it
# and/or modify it under the terms of the Do What The Fuck You Want
# To Public License, Version 2, as published by Sam Hocevar. See
# COPYING.WTFPL-2 or http://sam.zoy.org/wtfpl/COPYING for more details.

function mapp() {
    which awk sed egrep ipcs ipcrm ipcmk mapp_jobserver > /dev/null
    if [[ $? -ne 0 ]] ; then
	echo "MAPP: Missing some utilities. Search results:" 2>&1
	which awk sed egrep ipcs ipcrm ipcmk mapp_jobserver 2>&1
	return 1
    fi
    if [[ -n $ZSH_VERSION ]] ; then
	echo "MAPP: ZSH detected. Using KSH-style arrays" \
	    "and disabling job monitoring."
	setopt ksharrays
	setopt nomonitor
    fi
    if [[ -z $MAPP_NR_CPUS ]] ; then
	local MAPP_NR_CPUS=$(grep "processor	:" < /proc/cpuinfo | wc -l)
    fi

    local mapp_funname=$1
    shift
    local -a mapp_params
    mapp_params=("$@")
    local mapp_nr_args=${#mapp_params[@]}
    if [[ $mapp_nr_args -lt $MAPP_NR_CPUS ]] ; then
	MAPP_NR_CPUS=$mapp_nr_args
    fi
    local mapp_progress=0
    echo "MAPP: Using $MAPP_NR_CPUS CPUs" 2>&1
    local mapp_Qkey
    local mapp_Q="$(ipcmk -Q | sed -r 's/.+ ([0-9]+)$/\1/' | egrep -x '[0-9]+')"
    if [[ $? -ne 0 ]] ; then
	echo "MAPP: Failed to create message queue." 2>&1
	return 1
    else
	mapp_Qkey=$(ipcs -q | awk "\$2 == $mapp_Q { print \$1 }")
	echo "MAPP: created message queue with id $mapp_Q and key $mapp_Qkey" \
	    2>&1
    fi

    echo "MAPP: Starting jobserver." 2>&1
    local mapp_jarg
    mapp_jobserver s $mapp_Qkey $MAPP_NR_CPUS $mapp_nr_args | \
    while read mapp_jarg; do
	echo "MAPP: Starting job ${mapp_jarg}." \
	    "Progress: $((mapp_progress*100/mapp_nr_args))%" 2>&1
	(
	    $mapp_funname "${mapp_params[$mapp_jarg]}"
	    mapp_jobserver c $mapp_Qkey $mapp_jarg
	    echo "MAPP: Job number $mapp_jarg finished." 2>&1
	) &
	let mapp_progress+=1
    done
    echo "MAPP: Jobserver finished, cleaning up."
    wait
    ipcrm -q $mapp_Q
}
