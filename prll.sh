#  Copyright 2009-2013 Jure Varlec
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

prll_real() {
    prll_usage() {
	cat <<-EOF
	prll version __PRLL_VERSION__
	Copyright 2009-2011 Jure Varlec

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
	 	-c num	Set number of parallel tasks to 'num'.
	 	-q	Disable progress messages.
	        -Q	Disable all messages except errors.

	The number of tasks to be run in parallel can be set with
	the PRLL_NRJOBS environment variable or the -c option. If
	it is not set, prll will attempt to read the number of CPUs
	from /proc/cpuinfo.

	Buffering can be disabled by setting PRLL_BUFFER environment
	variable to "no" or "0".

	See the prll manpage for more information.
	EOF
	exit ${1:-1}
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
	     # Suppress the newline
	    -n)	shift; printf 'PRLL: %s' "$*" 1>&2 ;;
	     # Interpret arguments as a printf string
	    -e)	shift; printf "$@" 1>&2 ;;
	    *)	printf 'PRLL: %s\n' "$*" 1>&2 ;;
	esac
    }

    # This executable is always needed.
    command -v prll_qer > /dev/null || prll_die "Missing prll_qer."
    command -v prll_bfr > /dev/null || prll_die "Missing prll_bfr."

    # Read parameters and environment variables.
    prll_unbuffer=no
    [ "$PRLL_BUFFER" = "no" -o "$PRLL_BUFFER" = "0" ] && prll_unbuffer=yes
    [ -n "$PRLL_NR_CPUS" ] && prll_nr_cpus=$PRLL_NR_CPUS # Backward compat.
    [ -n "$PRLL_NRJOBS" ] && prll_nr_cpus=$PRLL_NRJOBS

    OPTIND=1
    prll_funname='' # Function to execute
    prll_read=no # Whether to read standard input
    while getopts "s:p0bBc:qQhH?" prll_i
    do	case $prll_i in
	    s)	eval "prll_str2func() {	$OPTARG
}"
		prll_funname=prll_str2func ;;
	    p)	prll_read=stdin ;;
	    0)  prll_read=null ;;
	    b)  prll_unbuffer=yes ;;
	    B)  prll_unbuffer=no ;;
	    c)  prll_nr_cpus="$OPTARG" ;;
	    q)  prll_quiet=yes ;;
	    Q)	prll_msg() { : ; } ;;
	    h)	prll_usage 0 ;;
	    *)	prll_usage ;;
	esac
    done
    shift $((OPTIND - 1))

    # Setup cgroups if enabled.
    if [ -n "$PRLL_CGROUP_PATH" ] ; then
	prll_cgroup="$(mktemp -d $PRLL_CGROUP_PATH/prll_XXXXXX)"
	if [ -z "$prll_cgroup" ] ; then
	    prll_msg "Unable to create a directory in $PRLL_CGROUP_PATH"
	elif [ ! -f "$prll_cgroup/tasks" ] ; then
	    prll_msg "Directory $prll_cgroup is not a cgroup, removing it"
	    rmdir "$prll_cgroup"
	    prll_cgroup=
	else
	    prll_msg "cgroups enabled, using $prll_cgroup"
	fi
    fi

    # Function was not given as a string, so the next argument must be
    # the name of an external function.
    if [ -z "$prll_funname" ] ; then
	prll_funname="$1"
	shift
    fi

    # Add an exception for -p and -0 for backwards compatibility
    if [ "$1" = '-p' ] ; then
	prll_read=stdin
	shift
    elif [ "$1" = '-0' ] ; then
	prll_read=null
	shift
    fi

    # Check whether arguments were supplied
    if [ $prll_read = no -a -z "$1" ] ; then
	prll_msg -e "Nothing to do...\n\n"
	prll_usage
    fi

    # Number of CPUs was not given, so find it. Also, check for sanity.
    if [ -z "$prll_nr_cpus" ] ; then
	command -v grep > /dev/null
	if [ $? -ne 0 -o ! -e /proc/cpuinfo ] ; then
	    prll_die \
		"The number of CPUs is not set and either the grep" \
		"utility is missing or there is no /proc/cpuinfo file." \
		"Please set the number of CPUs."
	fi
	prll_nr_cpus=$(grep "processor	:" < /proc/cpuinfo | wc -l)
    elif [ $prll_nr_cpus -lt 1 ] ; then
	prll_die "The number of CPUs is zero."
    elif ! [ $prll_nr_cpus -ge 1 ] ; then
	prll_die "Invalid number of CPUs."
    fi

    # If not reading from stdin, setup positional arguments.
    if [ $prll_read = no ] ; then
	prll_nr_args=$#
	if [ $prll_nr_args -lt $prll_nr_cpus ] ; then
	    prll_nr_cpus=$prll_nr_args
	fi
    fi

    # Create IPCs.
    prll_msg "Using $prll_nr_cpus CPUs"
    prll_Qkey="$(prll_qer n)"
    if [ $? -ne 0 ] ; then
	prll_die "Failed to create message queue."
    else
	prll_msg "Created message queue with key $prll_Qkey"
    fi

    prll_Skey="$(prll_bfr n)"
    if [ $? -ne 0 ] ; then
	prll_die "Failed to create semaphore."
    else
	prll_msg "Created semaphore with key $prll_Skey"
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
    # Start reading stdin.
    (
	if [ $prll_read != no ] ; then
	    # This subshell has its own trap.
	    trap "prll_bfr r $prll_Skey2" INT
	    if [ $prll_read = stdin ] ; then
		prll_bfr w $prll_Skey2
	    elif [ $prll_read = null ] ; then
		prll_bfr W $prll_Skey2
	    fi
	    # Signal completion by removing the semaphore.
	    prll_bfr r $prll_Skey2
	else
	    # Nothing on stdin, so just close stdout and exit the
	    # subshell.
	    exec 1>&-
	fi
    ) | (
    # Load some tokens into the queue. This will make the main loop
    # start a few jobs to run in parallel.
    prll_i=1
    while [ $prll_i -le $prll_nr_cpus ] ; do
	prll_qer c $prll_Qkey 0;
	prll_i=$((prll_i + 1))
    done

    #####################
    # FUNCTIONS FOR USERS

    # Gracefully abort by inserting a 'quit' message into the queue.
    prll_interrupt() {
	prll_msg \
	    "Job $prll_progress interrupting execution." \
	    "Waiting for unfinished jobs."
	prll_qer c $prll_Qkey 1
	return 130
    }

    # A simple substitute for GNU seq.
    prll_seq() {
	prll_seq_i=1
	if [ -n "$2" ] ; then
	    prll_seq_i=$1
	    shift
	fi
	echo $prll_seq_i
	while [ $prll_seq_i -lt $1 ] ; do
	    prll_seq_i=$((prll_seq_i + 1))
	    echo $prll_seq_i
	done
    }

    # Locking. prll_lockery() shouldn't be called by users.
    prll_lockery() {
	prll_locknum="$1"
	[ -z "$prll_locknum" ] && prll_locknum=0
	[ "$prll_locknum" -ge 5 -o "$prll_locknum" -lt 0 ] && \
	    prll_die "Illegal lock number!"
	prll_bfr $2 $prll_Skey $prll_locknum
    }
    prll_lock() {
	prll_lockery "$1" u
    }
    prll_unlock() {
	prll_lockery "$1" U
    }

    # Argument splitting. Generates prll_arg_X variables, where X
    # numbers them from 1 upwards.
    prll_splitarg() {
	prll_spl_i=1
	prll_spl_rest="$prll_jarg"
	while [ -n "$prll_spl_rest" ] ; do
	    prll_spl_varname="prll_arg_$prll_spl_i"
	    eval "
read $prll_spl_varname prll_spl_rest <<EOF
$prll_spl_rest
EOF
"
	    prll_spl_i=$((prll_spl_i+1))
	done
	prll_arg_num=$((prll_spl_i-1))
    }

    #######################
    # END OF USER FUNCTIONS

    prll_progress=0 # Counts started jobs
    prll_jbfinish=0 # Counts finished jobs

    # The main loop. Its iterations are controlled by prll_qer, which
    # waits for a message to arrive before starting a new job, unless
    # the message tells it to quit.
    while prll_qer o $prll_Qkey ; do

	# Only start counting finished jobs after the initial batch of
	# tokens is exhausted.
	[ $prll_progress -ge $prll_nr_cpus ] && \
	    prll_jbfinish=$((prll_jbfinish + 1))

	# The function argument. It gets its value either from
	# positional arguments or stdin.
	prll_jarg=''
	if [ $prll_read = no ] ; then
	    # If there are no more arguments, break the main loop.
	    if [ $prll_progress -ge $prll_nr_args ] ; then
		break
	    else
		prll_jarg="$1"
		shift
	    fi
	else
	    prll_jarg="$(prll_bfr c $prll_Skey2)"
	    # If there is nothing more to read, break the main loop.
	    if [ $? -ne 0 ] ; then
		break
	    fi
	fi

	# Disable the interrupt trap for the rest of the loop iteration
	# to make sure jobs are counted correctly.
	trap '' INT
	# Spawn subshells that start the job and buffer.
	# It is done in a very roundabout way in order to workaround a race
	# condition with zsh.
	prll_launch_code='
	    (
		prll_jobnr=$prll_progress
		(
		  [ -n "$prll_cgroup" ] && prll_qer P "$prll_cgroup"/tasks
		  $prll_funname "$prll_jarg"
		)
		[ -z "$prll_quiet" ] &&
		prll_msg "Job number $prll_progress finished. Exit code: $?"
	    ) | \
		(
		if [ $prll_unbuffer = yes ] ; then
		    cat
		else
		    prll_bfr b $prll_Skey
		fi
		prll_qer c $prll_Qkey 0
	    ) &'
	[ -n "$ZSH_VERSION" ] && prll_launch_code="${prll_launch_code}!"
	eval "$prll_launch_code"

	# Print progress
	prll_status="Starting job ${prll_progress}, PID $!"
	if [ $prll_read = no ] ; then
	    prll_status="$prll_status Progress:"
	    prll_status="$prll_status $((prll_progress*100/prll_nr_args))%"
	    prll_status="$prll_status Arg: $prll_jarg"
	fi
	[ -z "$prll_quiet" ] && prll_msg "$prll_status"
	prll_progress=$((prll_progress + 1))

	# Setup the interrupt trap.
	trap 'prll_interrupted=1' INT
    done

    # Cleanup. It sets up its own interrupt trap to notify the user he
    # has to do his own cleanup.
    trap '' INT
    if [ -n "$prll_interrupted" ] ; then
	prll_msg "INTERRUPTED!"
    fi
    prll_msg "Waiting for unfinished jobs."
    if [ -n "$prll_cgroup" ] ; then
	prll_msg "You can kill them using prll_killcg on $(basename $prll_cgroup)"
    fi
    if [ $prll_progress -lt $prll_nr_cpus ] ; then
	prll_progress=$((prll_nr_cpus-1))
    fi
    while [ $prll_progress -gt $prll_jbfinish ] ; do
	prll_qer o $prll_Qkey || break
	prll_jbfinish=$((prll_jbfinish + 1))
    done
    prll_msg "Cleaning up."
    prll_qer r $prll_Qkey
    prll_bfr r $prll_Skey
    [ $prll_read != no ] && prll_bfr r $prll_Skey2
    [ -n "$prll_cgroup" ] && rmdir "$prll_cgroup"
    true # No use returning the status of IPC removal
    )
return $?
}

prll() {
    ( prll_real "$@" )
    return $?
}

prll_killcg() {
    if [ -z "$PRLL_CGROUP_PATH" ] ; then
	echo "cgroups not enabled, see manual." 1>&2
	return 1
    fi
    prll_cgs=$(cd "$PRLL_CGROUP_PATH" && echo prll_*)
    if [ -z "$prll_cgs" ] ; then
	echo "No prll cgroups found." 1>&2
	return 0
    fi
    prll_cgcount=1
    echo "Found the following prll cgroups:" 1>&2
    for prll_cg in $prll_cgs ; do
	echo $prll_cgcount $prll_cg 1>&2
	prll_cgcount=$((prll_cgcount + 1))
    done
    echo -n "Enter the chosen cgroup's number: " 1>&2
    read
    prll_cgcount=1
    for prll_cg in $prll_cgs ; do
	if [ $prll_cgcount -eq $REPLY ] ; then
	    if [ -z "$1" ] ; then
		echo "Using INT signal." 1>&2
		prll_sig="-INT"
	    else
		echo "Using KILL signal." 1>&2
		prll_sig="-KILL"
	    fi
	    prll_tasks="$PRLL_CGROUP_PATH"/$prll_cg/tasks
	    while [ $(wc -l < "$prll_tasks") -gt 0 ] ; do
		cat "$prll_tasks" | (
		    while read ; do
			kill $prll_sig $REPLY
		    done
		)
	    done
	    echo "Tasks killed." 1>&2
	    rmdir "$PRLL_CGROUP_PATH"/$prll_cg 
	    return
	fi
	prll_cgcount=$((prll_cgcount + 1))
    done
    echo "Chosen cgroup does not exist!" 1>&2
    return 1
}
