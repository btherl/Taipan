#!/usr/bin/perl -w

# Turn each line of stdin into one 32-byte line of Atari screen codes,
# truncating or padding with nulls as needed.

# Input format is plain text, except any character can be preceded
# by a \ to inverse it. No way to get a non-inverse \ in there, sorry.

use bytes;

$linelen = $1 || 32; # 32 for narrow playfield, would be 40 for normal.

while(<>) {
	chomp;

	s/\\(.)/chr(ord($1)|0x80)/ge;

	if(length > $linelen) {
		warn "$0: line $. truncated to 32 characters!\n";
		substr($_, 32) = "";
	}

	my $blanks = $linelen;
	for(map { ord } split "", $_) {
		my $byte = $_ & 0x7f;
		my $inv =  $_ & 0x80;
#warn sprintf("\$_ %02x, \$byte %02x, \$inv %02x", $_, $byte, $inv);
		if($byte < 32) {
			$byte += 64;
		} elsif($byte >= 32 && $byte <= 96) {
			$byte -= 32;
		}
#warn sprintf("result: %02x", ($byte | $inv));
		print chr($byte | $inv);
		$blanks--;
	}
	print chr(0) x $blanks;
}
