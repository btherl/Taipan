#!/usr/bin/perl -w

# LORCHA.LST is a LISTed BASIC program that draws a lorcha
# and spits out the screen data to H:LORCHA.DAT (for which
# you will need atari800's H: device pointed at the current
# directory).

# Usage:
# atari800 -basic LORCHA.LST
# perl lorcha.pl LORCHA.DAT > lorcha_data.inc

use bytes;
undef $/;
$data = <>;
print "lorcha_data:\n";
for(0..6) {
	print " .byte ";
	print join ", ", map { sprintf '$%02x', ord $_ } split "", substr($data, $_ * 6, 7);
	print "\n";
}
