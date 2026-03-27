#!/usr/bin/perl -w

# turn version string into raw screen data, so we can easily display
# it on the title screen.

use bytes;
my $ver = shift;

if(length($ver) > 32) {
	warn "$0: version string > 32 chars, will be cut off!\n";
	substr($ver, 32) = "";
}

$blanks = 32;
for(map { ord } split "", $ver) {
	my $byte = $_;
	if($_ < 32) {
		$byte += 64;
	} elsif($_ >= 32 && $_ <= 96) {
		$byte -= 32;
	}
	print chr($byte);
	$blanks--;
}

print chr(0) x $blanks;
