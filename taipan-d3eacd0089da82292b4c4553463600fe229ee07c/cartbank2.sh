#!/bin/sh

# cc65 linker script stuff changed between 2.15 and 2.16. Pick the right
# .cfg for the version of cc65 we're using.

DEST="cartbank2.cfg"

VER="$( cc65 --version 2>&1 | sed 's,^.*V\([0-9.]*\) .*$,\1,' )"
MAJOR="$( echo "$VER" | cut -d. -f1 )"
MINOR="$( echo "$VER" | cut -d. -f2 )"
VERDEC="$( printf "%d%03d" "$MAJOR" "$MINOR" )"

if [ "$VERDEC" -lt "2015" ]; then
  echo "*** Warning: cc65 version $VER is too old, upgrade to at least 2.15"
  CFG=old
elif [ "$VERDEC" -eq "2015" ]; then
  CFG=old
else
  CFG=new
fi

CONFIG="$DEST.$CFG"
echo "=== Found cc65 version $VER, using $CONFIG"
rm -f "$DEST"
cp "$CONFIG" "$DEST"
