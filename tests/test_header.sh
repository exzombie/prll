export LC_ALL=C
. ../prll.sh
PATH="../:$PATH"
test_shell="$(ps -p $$ -o comm=)"

echo
echo "$TEST_DESCRIPTION"
echo "Shell: $test_shell"
if [ -n "$SUPPORTED_SHELLS" ] ; then
    echo "$SUPPORTED_SHELLS" | grep "$test_shell" > /dev/null || \
    { echo "Shell not supported in this test."; exit 0; }
fi
echo
