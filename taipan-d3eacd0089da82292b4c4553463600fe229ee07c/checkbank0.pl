#!/usr/bin/perl -w

# Check a cart bank (normally bank0) and warn if there's a zero
# byte in the 'cart present' location. According to the atari800
# docs, sometimes bank 0 comes up mapped to the right cart area,
# which means the OS might try to initialize/run it (which wouldn't
# work).

die "usage: $0 <filename>\n" unless @ARGV == 1;

use bytes;

undef $/;
$_ = <>;
$byte = ord substr($_, 8188, 1);
if($byte == 0) {
	warn "$0: $ARGV[0] has zero byte (cart present) in trailer (\$9ffc)\n";
}
exit 0;
