#!/usr/bin/perl -w

# draws an ASCII art representation of the lorcha.

use bytes;

if(!@ARGV) {
	push @ARGV, "LORCHA.DAT";
}

undef $/;
$_ = <>;
@shape = unpack "C*", $_;

open $in, "<taifont" or die $!;
$f = <$in>;
close $in;

@out = ();

for($row = 0; $row < 7; $row++) {
	for($col = 0; $col < 7; $col++) {
		draw_tile($row, $col);
	}
}

for($row = 0; $row < @out; $row++) {
	for($col = 0; $col < 7; $col++) {
		print $out[$row][$col];
	}
	print "\n";
}


sub draw_tile {
	my $row = shift;
	my $col = shift;
	my $tile = $shape[$row * 7 + $col];
	my $reverse = 0;
	my $i;
	my $j;
	my $y = $row * 8;
	#$out[$row][$col] = sprintf(" %03x", $tile);

	if($tile > 127) {
		$tile -= 128;
		$reverse = 1;
	}
	for($i = 0; $i < 8; $i++) {
		my $data = sprintf "%08b", ord substr($f, $tile * 8 + $i, 1);
		if($reverse) {
			$data =~ s/0/X/g;
			$data =~ s/1/ /g;
		} else {
			$data =~ s/1/X/g;
			$data =~ s/0/ /g;
		}

		$out[$y + $i][$col] = $data;
	}
}
