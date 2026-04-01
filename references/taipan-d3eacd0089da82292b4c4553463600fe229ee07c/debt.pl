#!/usr/bin/perl -w

my $debt = shift || 1000;
my $idebt = $debt;

my $months = shift || 100;
for(1..$months) {
	$debt += $debt * 0.1;
	if($idebt > 16) {
		$idebt += (($idebt >> 4) + ($idebt >> 5) + ($idebt >> 7) - ($idebt >> 9));
	} else {
		$idebt++;
	}
	# print "$debt\t$idebt\n";
	$pct = $idebt * 100 / $debt;
	printf("%.2d\t$idebt\t%.1d%%\n", $debt, $pct);
}
