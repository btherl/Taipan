#!/usr/bin/perl -w

$_ = <>;
chomp;
for(split /, */, $_) {
	s/, *//;
	s/0x//;
	my $out = sprintf("%08b", hex($_));
	$out =~ s/1/X/g;
	$out =~ s/0/ /g;
	print "$out\n";
}
