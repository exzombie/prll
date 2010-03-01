export LC_ALL=C
source ../prll.sh
PATH="../:$PATH"

echo
echo $TEST_DESCRIPTION
if [[ -n $ZSH_VERSION ]] ; then
   echo "Shell: zsh"
else
   echo "Shell: bash"
fi
echo
