#!/usr/bin/perl -w

# replace this:

# timeout(5000);
# getch();
# timeout(-1);

# with this:

# timed_getch(83);

# the 83 comes from int(5000/1000*60)

# indentation levels must be preserved!

while(<>) {
	my $line = $_;
	if(/^(\s+)timeout\s*\((\d+)/) {
		#warn "found timeout($2) at $.\n";
		my $indent = $1;
		my $jiffies = int(($2 / 1000) * 60);

		if($jiffies == 60) {
			$jiffies = "TMOUT_1S";
		} elsif($jiffies == 180) {
			$jiffies = "TMOUT_3S";
		} elsif($jiffies == 300) {
			$jiffies = "TMOUT_5S";
		} else {
			warn "no TMOUT_* constant for $jiffies, line $.\n";
		}

		my $next = <>;
		if($next =~ /getch\(\)/) {
			print $indent . "timed_getch($jiffies);\n";
			my $last = <>;
			if($last !~ /timeout\(-1\)/) {
				print $last;
			}
		} else {
			print $line;
			print $next;
		}
	} else {
		print $line;
	}
}
