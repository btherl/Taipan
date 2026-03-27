#!/usr/bin/perl -w

# browse through a binary file looking for bitmapped graphics,
# especially fonts

# user is expected to pipe through less

$height = 8; # how many rows to display per block
$width  = 8; # how many blocks to display per line

undef $/;
$data = <>;

for($offs=0; $offs<length($data); $offs += ($height * $width)) {
	for my $char (0..$width-1) {
		printf("%7x ", $offs + ($char * $height));
		printf("%2x", $offs / $height + $char);
	}

	print "\n";

	for my $line (0..$height-1) {
		for my $char (0..$width-1) {
			my $index = $offs + $line + ($char * $height);
			if($index < length($data)) {
				my $bitmap = sprintf("  %08b", ord(substr($data, $index, 1)));
				$bitmap =~ s/0/./g;
				$bitmap =~ s/1/X/g;
				print $bitmap;
			}
		}
		print "\n";
	}
}
