#!/usr/bin/perl -w

# read a ctags file. for every tag found, create its
# corresponding tag with or without leading _.
# vim wants the tagfile sorted, so do that, too.

$file = $ARGV[0];
while(<>) {
	push @tags, $_;
	next if /^!/; # skip ctags magic tags

	# skip C #defines
	my @fields = split '\t';
	next if $fields[1] =~ /\.c$/ && $fields[3] =~ /^d$/;

	if(/^_/) {
		s/^_//;
	} else {
		s/^/_/;
	}
	push @tags, $_;
}

open OUT, ">$file" or die $!;
print OUT for sort @tags;
