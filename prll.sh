#  Copyright 2009-2010 Jure Varlec
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#  
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#  
#  A copy of the GNU General Public License is provided in COPYING.
#  If not, see <http://www.gnu.org/licenses/>.

test -z "$BASH" -a -z "$ZSH_VERSION" && return
prll() {
    if [ -z "$1" -o "$1" = "-h" -o "$1" = "--help" ] ; then
	cat <<-EOF
	prll version 0.5.9999
	Copyright 2009-2010 Jure Varlec

	USAGE: prll [-b] fun_name fun_arg1 fun_arg2 fun_arg3 ...
	       prll [-b] -s 'fun_string' fun_arg1 fun_arg2 ...

	Order of options is important.

	Shell function 'fun_name' will be run for each 'fun_arg'.
	Alternatively, using -s, shell code 'fun_string' will be executed.

	Instead of 'fun_args', option -p may be given, which will cause
	prll to read lines from its standard input.
	Alternatively, option -0 will make it read null-delimited input.

	Option -b disables output buffering.

	The number of processes to be run in parallel can be set with
	the PRLL_NR_CPUS environment variable. If it is unset, prll will
	attempt to read the number of CPUs from /proc/cpuinfo.

	See the README for more information.
	EOF
	[ -z "$1" ] && return 1 || return 0
    fi
    /usr/bin/which prll_qer > /dev/null
    if [ "$?" -ne 0 ] ; then
	echo "PRLL: Missing prll_qer." 1>&2
	return 1
    fi

(
    # Do we do buffering?
    if [ "$1" = "-b" -o "$PRLL_BUFFER" = "no" -o "$PRLL_BUFFER" = "0" ] ; then
	prll_unbuffer=yes
	shift
    else
	/usr/bin/which prll_bfr > /dev/null
	if [ "$?" -ne 0 ] ; then
	    echo "PRLL: Missing prll_bfr." 1>&2
	    return 1
	fi
    fi
    if [ -z "$PRLL_NR_CPUS" ] ; then
	/usr/bin/which grep > /dev/null
	if [ "$?" -ne 0 -o ! -e /proc/cpuinfo ] ; then
	    echo "PRLL: Environment variable PRLL_NR_CPUS is not set" 1>&2
	    echo "PRLL: and either the grep utility is missing or" 1>&2
	    echo "PRLL: there is no /proc/cpuinfo file." 1>&2
	    echo "PRLL: Please set the PRLL_NR_CPUS variable." 1>&2
	    return 1
	fi
	PRLL_NR_CPUS=$(grep "processor	:" < /proc/cpuinfo | wc -l)
    fi
    
    prll_funname=$1
    shift
    # Do we have a function handle or a string?
    if [ "$prll_funname" = "-s" ] ; then
	prll_fun_str="$1"
	shift
	prll_str2func() {
	    eval "$prll_fun_str"
	}
	prll_funname=prll_str2func
    fi

    # Do we read parameters or stdin?
    if [ "$1" = "-p" ] ; then
	prll_read=stdin
	shift
    elif [ "$1" = "-0" -o "$1" = "-p0" ] ; then
	prll_read=null
	shift
    else
    # Put all arguments into an array
	prll_read=no
	local -a prll_params
	prll_params=("$@")
	prll_nr_args=${#prll_params[@]}
	if [ "$prll_nr_args" -lt "$PRLL_NR_CPUS" ] ; then
	    PRLL_NR_CPUS=$prll_nr_args
	fi
    fi

    echo "PRLL: Using $PRLL_NR_CPUS CPUs" 1>&2
    prll_Qkey="$(prll_qer n)"
    if [ "$?" -ne 0 ] ; then
	echo "PRLL: Failed to create message queue." 1>&2
	return 1
    else
	echo "PRLL: Created message queue with key $prll_Qkey" 1>&2
    fi

    if [ "$prll_unbuffer" != "yes" ] ; then
	prll_Skey="$(prll_bfr n)"
	if [ "$?" -ne 0 ] ; then
	    echo "PRLL: Failed to create semaphore." 1>&2
	    return 1
	else
	    echo "PRLL: Created semaphore with key $prll_Skey" 1>&2
	fi
    fi

    echo "PRLL: Starting work." 1>&2
    # Get the first jobs started
    for i in $(eval echo {1..$PRLL_NR_CPUS}) ; do
	prll_qer c $prll_Qkey 0;
    done
    ( # Run in a subshell so this code can be suspended as a unit
	if [ -n "$ZSH_VERSION" ] ; then
	    setopt ksharrays
	fi

	prll_cleanup() {
	    trap - SIGINT
	    prll_qer t $prll_Qkey || return 130
	    if [ "$1" != "nosig" ] ; then
		echo "PRLL: Interrupted, waiting for unfinished jobs." 1>&2
	    fi
	    while [ "$prll_progress" -ge "$prll_jbfinish" ] ; do
		prll_qer o $prll_Qkey || break
		let prll_jbfinish+=1
	    done
	    echo "PRLL: Cleaning up." 1>&2
	    prll_qer r $prll_Qkey
	    if [ "$prll_unbuffer" != "yes" ] ; then
		prll_bfr t $prll_Skey && prll_bfr r $prll_Skey
	    fi
	}
	trap prll_cleanup SIGINT

	prll_finish_code='
                          prll_finishing=yes
	                  let prll_jbfinish+=1
		          if [ "$prll_jbfinish" -gt "$prll_progress" ] ; then
		              prll_qer c $prll_Qkey 1
                              continue
                          fi
	                  if [ "$prll_progress" -lt "$PRLL_NR_CPUS" ] ; then
			      let prll_progress=$((PRLL_NR_CPUS-1))
		          fi
		          continue'

	prll_interrupt() {
	    echo "PRLL: Job $prll_progress interrupting execution." 1>&2
	    echo "PRLL: Waiting for unfinished jobs." 1>&2
	    prll_qer c $prll_Qkey 1
	    return 130
	}	

	prll_progress=0
	prll_jbfinish=0
	prll_finishing=no
	while prll_qer o $prll_Qkey ; do
	    if [ "$prll_finishing" = "yes" ] ; then
		let prll_jbfinish+=1
		if [ "$prll_jbfinish" -gt "$prll_progress" ] ; then
		    prll_qer c $prll_Qkey 1
		else
		    continue
		fi
	    fi
	    prll_jarg=''
	    if [ "$prll_read" = "no" ] ; then
		if [ "$prll_progress" -ge "$prll_nr_args" ] ; then
		    eval "$prll_finish_code"
		else
		    prll_jarg="${prll_params[$prll_progress]}"
		fi
	    elif [ "$prll_read" = "stdin" ] ; then
		IFS='' read -r -d $'\n' prll_jarg
		if [ "$?" -ne 0 ] ; then
		    eval "$prll_finish_code"
		fi
	    elif [ "$prll_read" = "null" ] ; then
		IFS='' read -r -d $'\0' prll_jarg
		if [ "$?" -ne 0 ] ; then
		    eval "$prll_finish_code"
		fi
	    else
		echo "Something's wrong..." 1>&2
		return 1
	    fi

	    (
		$prll_funname "$prll_jarg"
		echo "PRLL: Job number $prll_progress finished. " \
		    "Exit code: $?" 1>&2
	    ) | \
		(
		if [ "$prll_unbuffer" = "yes" ] ; then
		    cat
		else
		    prll_bfr b $prll_Skey
		fi
		prll_qer c $prll_Qkey 0
	    ) &

	    echo -n "PRLL: Starting job ${prll_progress}, PID $! " 1>&2
	    if [ "$prll_read" = "no" ] ; then
		echo -n \
		    "Progress: $((prll_progress*100/prll_nr_args))% " 1>&2
		echo -n "Arg: $prll_jarg " 1>&2
	    fi
	    echo 1>&2
	    let prll_progress+=1
	    [ "$prll_progress" -ge "$PRLL_NR_CPUS" ] && let prll_jbfinish+=1
	done
	declare -f prll_cleanup > /dev/null && prll_cleanup nosig
    )
)
return $?
}
