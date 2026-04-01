#!/bin/sh

# push to git, create a new build from scratch, post it on webserver,
# and print the short git hash (for copy/pasting into irc).
# "sluk" is a shell script that you don't have :)

git push -4 && make distclean all || exit 1
URL="$( sluk taipan.xex )"
REV="$( git rev-parse --short HEAD )"

echo "build ID $REV at $URL"
