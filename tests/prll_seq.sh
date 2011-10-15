prll_seq() {
    seq_i=1
    echo -n $seq_i
    while [ $seq_i -lt $1 ] ; do
	echo -n " "
	seq_i=$((seq_i + 1))
	echo -n $seq_i
    done
}
