#!/usr/bin/perl -w

while(<>) {
	chomp;
	#$was = $_;
	s/$/ / while length($_) < 8;
	s/X/1/g;
	s/ /0/g;
	#warn "was '$was', now '$_'\n";
	push @out, sprintf("0x%02x", eval "0b$_");
}

print join(", ", @out) . "\n";
