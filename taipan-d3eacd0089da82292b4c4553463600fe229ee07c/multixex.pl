#!/usr/bin/perl -w

# concatenate 2 or more atari binary load files, removing the $FFFF
# headers from the 2nd and further ones.

# this shouldn't be necessary: Atari DOS 2.0S can handle the extra
# $FFFF headers, and it sets the gold standard for Atari executables.
# any loader that can't handle them, is broken. however, people apparently
# use these broken loaders a lot these days, so we'll be nice and
# support them.

use bytes;

die "Usage: $0 <xex-file> [<xex-file>] ... > output.xex\n" unless @ARGV;

undef $/;
$header_emitted = 0;

for(@ARGV) {
	open my $fh, "<$_" or die "$0: $_: $!\n";
	my $data = <$fh>;
	substr($data, 0, 2) = "" if substr($data, 0, 2) eq "\xff\xff";
	$header_emitted++, print "\xff\xff" unless $header_emitted;
	print $data;
}
