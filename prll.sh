# Copyright 2010 Jure Varlec
# This program is free software. It comes without any warranty, to
# the extent permitted by applicable law. You can redistribute it
# and/or modify it under the terms of the Do What The Fuck You Want
# To Public License, Version 2, as published by Sam Hocevar. See
# COPYING.WTFPL-2 or http://sam.zoy.org/wtfpl/COPYING for more details.

function prll() {
    if [[ -z $1 ]] ; then
	cat <<-EOF
	USAGE: prll fun_name fun_arg1 fun_arg2 fun_arg3 ...
	       prll -s 'fun_string' fun_arg1 fun_arg2 ...
	
	Shell function 'fun_name' will be run for each 'fun_arg'.
	Alternatively, using -s, shell code 'fun_string' will be executed.
	Instead of 'fun_args', option -p may be given, which will cause
	prll to read lines from its standard input.
	Alternatively, option -0 will make it read null-delimited input.
	The number of processes to be run in parallel can be set with
	the PRLL_NR_CPUS environment variable. If it is unset, prll will
	attempt to read the number of CPUs from /proc/cpuinfo.
	EOF
	return 1
    fi
    /usr/bin/which awk sed seq egrep ipcs ipcrm ipcmk prll_jobserver > /dev/null
    if [[ $? -ne 0 ]] ; then
	echo "PRLL: Missing some utilities." 1>&2
	return 1
    fi
    if [[ -z $PRLL_NR_CPUS ]] ; then
	local PRLL_NR_CPUS=$(grep "processor	:" < /proc/cpuinfo | wc -l)
    fi

    local prll_funname=$1
    shift
    # Do we have a function handle or a string?
    if [[ $prll_funname == "-s" ]] ; then
	local prll_fun_str="$1"
	shift
	function prll_str2func() {
	    eval "$prll_fun_str"
	}
	prll_funname=prll_str2func
    fi

    # Do we read parameters or stdin?
    local prll_read
    if [[ $1 == "-p" ]] ; then
	prll_read=stdin
	shift
    elif [[ $1 == "-0" || $1 == "-p0" ]] ; then
	prll_read=null
	shift
    else
    # Put all arguments into an array
	prll_read=no
	local -a prll_params
	prll_params=("$@")
	local prll_nr_args=${#prll_params[@]}
	if [[ $prll_nr_args -lt $PRLL_NR_CPUS ]] ; then
	    PRLL_NR_CPUS=$prll_nr_args
	fi
    fi

    echo "PRLL: Using $PRLL_NR_CPUS CPUs" 1>&2
    local prll_Qkey
    local prll_Q="$(ipcmk -Q | sed -r 's/.+ ([0-9]+)$/\1/' | egrep -x '[0-9]+')"
    if [[ $? -ne 0 ]] ; then
	echo "PRLL: Failed to create message queue." 1>&2
	return 1
    else
	prll_Qkey=$(ipcs -q | awk "\$2 == $prll_Q { print \$1 }")
	echo "PRLL: Created message queue with id $prll_Q and key $prll_Qkey" \
	    1>&2
    fi

    echo "PRLL: Starting jobserver." 1>&2
    # Get the first jobs started
    for i in $(seq 1 $PRLL_NR_CPUS) ; do prll_jobserver c $prll_Qkey 0; done
    ( # Run in a subshell so this code can be suspended as a unit
	if [[ -n $ZSH_VERSION ]] ; then
	    setopt ksharrays
	fi

	function prll_cleanup() {
	    trap - SIGINT
	    ipcs -q -i $prll_Q > /dev/null 2>&1
	    [[ $? -ne 0 ]] && return 130
	    if [[ $1 != "nosig" ]] ; then
		echo "PRLL: Interrupted, waiting for unfinished jobs." 1>&2
		while [[ $prll_progress -ge $prll_jbfinish ]] ; do
		    prll_jobserver o $prll_Qkey || break
		    let prll_jbfinish+=1
		done
	    fi
	    echo "PRLL: Cleaning up." 1>&2
	    ipcrm -q $prll_Q
	}
	trap prll_cleanup SIGINT

	local prll_finish_code='
                               local prll_finishing=yes
		               let prll_jbfinish+=1
		               if [[ $prll_jbfinish -gt $prll_progress ]] ; then
			         prll_jobserver c $prll_Qkey 1
                                 continue
                               fi
		               if [[ $prll_progress -lt $PRLL_NR_CPUS ]] ; then
			         let prll_progress=$((PRLL_NR_CPUS-1))
		               fi
		               continue'

	local prll_progress=0 prll_jbfinish=0 prll_finishing=no
	while prll_jobserver o $prll_Qkey ; do
	    if [[ $prll_finishing == "yes" ]] ; then
		let prll_jbfinish+=1
		if [[ $prll_jbfinish -gt $prll_progress ]] ; then
		    prll_jobserver c $prll_Qkey 1
		else
		    continue
		fi
	    fi
	    local prll_jarg=''
	    if [[ $prll_read == "no" ]] ; then
		if [[ $prll_progress -ge $prll_nr_args ]] ; then
		    eval "$prll_finish_code"
		else
		    prll_jarg="${prll_params[$prll_progress]}"
		fi
	    elif [[ $prll_read == "stdin" ]] ; then
		read prll_jarg
		if [[ $? -ne 0 ]] ; then
		    eval "$prll_finish_code"
		fi
	    elif [[ $prll_read == "null" ]] ; then
		read -r -d $'\0' prll_jarg
		if [[ $? -ne 0 ]] ; then
		    eval "$prll_finish_code"
		fi
	    else
		echo "Something's wrong..." 1>&2
		exit 1
	    fi
	    (
		$prll_funname "$prll_jarg"
		echo "PRLL: Job number $prll_progress finished." 1>&2
		prll_jobserver c $prll_Qkey 0
	    ) &
	    echo -n "PRLL: Starting job ${prll_progress}, PID $! " 1>&2
	    if [[ $prll_read == "no" ]] ; then
		echo -n "Progress: $((prll_progress*100/prll_nr_args))% " 1>&2
		echo -n "Arg: $prll_jarg " 1>&2
	    fi
	    echo 1>&2
	    let prll_progress+=1
	    [[ $prll_progress -ge $PRLL_NR_CPUS ]] && let prll_jbfinish+=1
	done
	declare -f prll_cleanup > /dev/null && prll_cleanup nosig
    )
    unset -f prll_str2func > /dev/null 2>&1
}
