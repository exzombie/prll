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
(
    prll_usage() {
	cat <<-EOF
	prll version 0.5.9999
	Copyright 2009-2010 Jure Varlec

	USAGE: prll [ options ] { fun_name | -s 'fun_string' } fun_args ...

	Shell function 'fun_name' will be run for each of 'fun_args'.
	Alternatively, using -s, shell code 'fun_string' will be executed
	as if it were the body of a function.

	Summary of options:
	 	-s str	Use string 'str' as shell code to run.
	 	-p	Read lines from standard input and use them
	 		instead of 'fun_args'.
	 	-0	Same as -p, but reads null-delimited input.
	 	-B	Enable output buffering, which is the default.
	 		Use to override the PRLL_BUFFER env. variable.
	 	-b	Disable output buffering.
	 	-c num	Set number of CPUs to 'num'.
	 	-q	Disable progress messages.

	The number of processes to be run in parallel can be set with
	the PRLL_NR_CPUS environment variable or the -c option. If
	it is not set, prll will attempt to read the number of CPUs
	from /proc/cpuinfo.

	See the README for more information.
	EOF
	exit 1
    }
    prll_die() {
	for prll_i ; do
	    printf "PRLL: %s\n" "$prll_i" 1>&2
	done
	exit 1
    }
    prll_msg() {
	case $1 in
	    '')	printf '\n' 1>&2 ;;
	    -n)	shift; printf 'PRLL: %s' "$*" 1>&2 ;;
	    -e)	shift; printf "$@" 1>&2 ;;
	    *)	printf 'PRLL: %s\n' "$*" 1>&2 ;;
	esac
    }

    command -v prll_qer > /dev/null || prll_die "Missing prll_qer."

    prll_unbuffer="no"
    [ "$PRLL_BUFFER" = "no" -o "$PRLL_BUFFER" = "0" ] && prll_unbuffer="yes"

    OPTIND=1
    prll_funname=''
    prll_read="no"
    while getopts "s:p0bBc:qhH?" prll_i
    do	case $prll_i in
	    s)	eval "prll_str2func() {	$OPTARG
}"
		prll_funname=prll_str2func ;;
	    p)	prll_read="stdin" ;;
	    0)  prll_read="null" ;;
	    b)  prll_unbuffer="yes" ;;
	    B)  prll_unbuffer="" ;;
	    c)  PRLL_NR_CPUS="$OPTARG" ;;
	    q)	prll_msg() { : ; } ;;
	    *)	prll_usage ;;
	esac
    done
    shift $((OPTIND - 1))
    if [ -z "$prll_funname" ] ; then
	[ -z "$1" ] && prll_die "Nothing to do..."
	prll_funname="$1"
	shift
    fi

    if [ -z "$PRLL_NR_CPUS" ] ; then
	command -v grep > /dev/null
	if [ "$?" -ne 0 -o ! -e /proc/cpuinfo ] ; then
	    prll_die \
		"The number of CPUs is not set and either the grep" \
		"utility is missing or there is no /proc/cpuinfo file." \
		"Please set the number of CPUs."
	fi
	PRLL_NR_CPUS=$(grep "processor	:" < /proc/cpuinfo | wc -l)
    elif [ "$PRLL_NR_CPUS" -lt 1 ] ; then
	prll_die "The number of CPUs is zero."
    fi

    if [ "$prll_unbuffer" != "yes" ] ; then
	command -v prll_bfr > /dev/null
	if [ "$?" -ne 0 ] ; then
	    prll_die "Missing prll_bfr."
	fi
    fi

    # Put all arguments into an array
    if [ "$prll_read" = "no" ] ; then
	local -a prll_params
	prll_params=("$@")
	prll_nr_args=${#prll_params[@]}
	if [ "$prll_nr_args" -lt "$PRLL_NR_CPUS" ] ; then
	    PRLL_NR_CPUS=$prll_nr_args
	fi
    fi

    prll_msg "Using $PRLL_NR_CPUS CPUs"
    prll_Qkey="$(prll_qer n)"
    if [ "$?" -ne 0 ] ; then
	prll_die "Failed to create message queue."
    else
	prll_msg "Created message queue with key $prll_Qkey"
    fi

    if [ "$prll_unbuffer" != "yes" ] ; then
	prll_Skey="$(prll_bfr n)"
	if [ "$?" -ne 0 ] ; then
	    prll_die "Failed to create semaphore."
	else
	    prll_msg "Created semaphore with key $prll_Skey"
	fi
    fi

    prll_msg "Starting work."
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
		prll_msg "Interrupted, waiting for unfinished jobs."
	    fi
	    while [ "$prll_progress" -ge "$prll_jbfinish" ] ; do
		prll_qer o $prll_Qkey || break
		let prll_jbfinish+=1
	    done
	    prll_msg "Cleaning up."
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
	    prll_msg \
		"Job $prll_progress interrupting execution." \
		"Waiting for unfinished jobs."
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
		prll_die "Something's wrong..."
	    fi

	    (
		$prll_funname "$prll_jarg"
		prll_msg "Job number $prll_progress finished. Exit code: $?"
	    ) | \
		(
		if [ "$prll_unbuffer" = "yes" ] ; then
		    cat
		else
		    prll_bfr b $prll_Skey
		fi
		prll_qer c $prll_Qkey 0
	    ) &

	    prll_msg -n "Starting job ${prll_progress}, PID $! "
	    if [ "$prll_read" = "no" ] ; then
		prll_msg -e "Progress: $((prll_progress*100/prll_nr_args))%% "
		prll_msg -e "Arg: $prll_jarg "
	    fi
	    prll_msg
	    let prll_progress+=1
	    [ "$prll_progress" -ge "$PRLL_NR_CPUS" ] && let prll_jbfinish+=1
	done
	declare -f prll_cleanup > /dev/null && prll_cleanup nosig
    )
)
return $?
}
