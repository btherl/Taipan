#!/usr/bin/perl -w

use bytes;
use Image::Magick;
use Data::Dumper;
my $img = new Image::Magick;
$img->read("newtitle.png");
@pixels = $img->GetPixels(
		width     => 256,
		height    => 184,
		x         => 0,
		y         => 0,
		map       => 'G',
);
#print Dumper \@pixels;
#print "got " . @pixels . " pixels\n";

for $y (0..183) {
	for $b (0..31) {
		my $byte = 0;
		for($x = 0; $x < 8; $x++) {
			$byte <<= 1;
			$byte |= ($pixels[$y * 256 + $b * 8 + $x] > 0);
		}
		push @bytes, $byte;
	}
}

# turn off utf-8 encoding for stdout. without doing this, the build
# break if someone's set PERL_UNICODE in the environment. plus, I
# strongly suspect utf-8 will be enabled by default in perl 7.
binmode STDOUT, ':raw';

# just output the raw data, no xex header.
print chr($_) for @bytes;


#print scalar @bytes;

#for $y (0..183) {
#	for $b (0..31) {
#		my $data = sprintf "%08b", $bytes[$y * 32 + $b];
#		$data =~ s,0, ,g;
#		$data =~ s,1,X,g;
#		print $data;
#	}
#	print "\n";
#}

# we might try a crude form of RLE, but not right now
#$run = 0;
#for(@bytes) {
#	if($_ == 0) {
#		$run++;
#	} else {
#		if($run > 1) {
#			print "run of $run 0 bytes\n";
#			$total += $run;
#		}
#		$run = 0;
#	}
#}
#
#print "total $total\n";
