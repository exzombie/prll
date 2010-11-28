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

    # Read parameters and environment variables
    prll_unbuffer=no
    [ "$PRLL_BUFFER" = "no" -o "$PRLL_BUFFER" = "0" ] && prll_unbuffer=yes

    OPTIND=1
    prll_funname=''
    prll_read=no
    while getopts "s:p0bBc:qhH?" prll_i
    do	case $prll_i in
	    s)	eval "prll_str2func() {	$OPTARG
}"
		prll_funname=prll_str2func ;;
	    p)	prll_read=stdin ;;
	    0)  prll_read=null ;;
	    b)  prll_unbuffer=yes ;;
	    B)  prll_unbuffer=no ;;
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
	if [ $? -ne 0 -o ! -e /proc/cpuinfo ] ; then
	    prll_die \
		"The number of CPUs is not set and either the grep" \
		"utility is missing or there is no /proc/cpuinfo file." \
		"Please set the number of CPUs."
	fi
	PRLL_NR_CPUS=$(grep "processor	:" < /proc/cpuinfo | wc -l)
    elif [ $PRLL_NR_CPUS -lt 1 ] ; then
	prll_die "The number of CPUs is zero."
    elif ! [ $PRLL_NR_CPUS -ge 1 ] ; then
	prll_die "Invalid number of CPUs."
    fi

    if [ $prll_unbuffer != yes -o $prll_read != no ] ; then
	command -v prll_bfr > /dev/null
	if [ $? -ne 0 ] ; then
	    prll_die "Missing prll_bfr."
	fi
    fi

    # If not reading from stdin, setup positional arguments
    if [ $prll_read = no ] ; then
	prll_nr_args=$#
	if [ $prll_nr_args -lt $PRLL_NR_CPUS ] ; then
	    PRLL_NR_CPUS=$prll_nr_args
	fi
    fi

    prll_msg "Using $PRLL_NR_CPUS CPUs"
    prll_Qkey="$(prll_qer n)"
    if [ $? -ne 0 ] ; then
	prll_die "Failed to create message queue."
    else
	prll_msg "Created message queue with key $prll_Qkey"
    fi

    if [ $prll_unbuffer != yes ] ; then
	prll_Skey="$(prll_bfr n)"
	if [ $? -ne 0 ] ; then
	    prll_die "Failed to create semaphore."
	else
	    prll_msg "Created semaphore with key $prll_Skey"
	fi
    fi

    if [ $prll_read != no ] ; then
	prll_Skey2="$(prll_bfr n)"
	if [ $? -ne 0 ] ; then
	    prll_die "Failed to create semaphore."
	else
	    prll_msg "Created semaphore with key $prll_Skey2"
	fi
    fi

    prll_msg "Starting work."
    # Start reading stdin
    (
	if [ $prll_read != no ] ; then
	    trap "prll_bfr r $prll_Skey2" INT
	    if [ $prll_read = stdin ] ; then
		prll_bfr w $prll_Skey2
	    elif [ $prll_read = null ] ; then
		prll_bfr W $prll_Skey2
	    fi
	    # Removal of the semafore signals completion
	    prll_bfr r $prll_Skey2
	else
	    exec 1>&-
	fi
    ) | (
    # Get the first jobs started
    prll_i=1
    while [ $prll_i -le $PRLL_NR_CPUS ] ; do
	prll_qer c $prll_Qkey 0;
	prll_i=$((prll_i + 1))
    done

    # A function for users. It gracefully aborts.
    prll_interrupt() {
	prll_msg \
	    "Job $prll_progress interrupting execution." \
	    "Waiting for unfinished jobs."
	prll_qer c $prll_Qkey 1
	return 130
    }	

    prll_progress=0
    prll_jbfinish=0
    # Main loop
    while prll_qer o $prll_Qkey ; do
	[ $prll_progress -ge $PRLL_NR_CPUS ] && \
	    prll_jbfinish=$((prll_jbfinish + 1))
	prll_jarg=''
	if [ $prll_read = no ] ; then
	    if [ $prll_progress -ge $prll_nr_args ] ; then
		break
	    else
		prll_jarg="$1"
		shift
	    fi
	else
	    prll_jarg="$(prll_bfr c $prll_Skey2)"
	    if [ $? -ne 0 ] ; then
		break
	    fi
	fi
	
	trap '' INT
	# Spawn subshells that start the job and buffer
	(
	    $prll_funname "$prll_jarg"
	    prll_msg "Job number $prll_progress finished. Exit code: $?"
	) | \
	(
	    if [ $prll_unbuffer = yes ] ; then
		cat
	    else
		prll_bfr b $prll_Skey
	    fi
	    prll_qer c $prll_Qkey 0
	) &

	# Print progress
	prll_status="Starting job ${prll_progress}, PID $!"
	if [ $prll_read = no ] ; then
	    prll_status="$prll_status Progress:"
	    prll_status="$prll_status $((prll_progress*100/prll_nr_args))%"
	    prll_status="$prll_status Arg: $prll_jarg"
	fi
	prll_msg "$prll_status"
	prll_progress=$((prll_progress + 1))

	trap 'prll_interrupted=1' INT
    done

    # Cleanup
    trap "prll_msg 'Waiting interrupted, jobs left running.'" INT
    if [ -n "$prll_interrupted" ] ; then
	prll_msg "INTERRUPTED!"
    fi
    prll_msg "Waiting for unfinished jobs."
    if [ $prll_progress -lt $PRLL_NR_CPUS ] ; then
	prll_progress=$((PRLL_NR_CPUS-1))
    fi
    while [ $prll_progress -gt $prll_jbfinish ] ; do
	prll_qer o $prll_Qkey || break
	prll_jbfinish=$((prll_jbfinish + 1))
    done
    prll_msg "Cleaning up."
    prll_qer r $prll_Qkey
    [ $prll_unbuffer != yes ] && prll_bfr r $prll_Skey
    [ $prll_read != no ] && prll_bfr r $prll_Skey2
    true # No use returning the status of IPC removal
    )
)
return $?
}
