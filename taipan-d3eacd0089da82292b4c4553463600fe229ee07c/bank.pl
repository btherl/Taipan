#!/usr/bin/perl -w

my $debt = shift || 1000;
my $idebt = $debt;

my $months = shift || 100;
for(1..$months) {
	$debt += $debt * 0.005;
	$idebt += ($idebt >> 8) + ($idebt >> 10);
	# print "$debt\t$idebt\n";
	$pct = $idebt * 100 / $debt;
	printf("%.2d\t$idebt\t%.1d%%\n", $debt, $pct);
}
