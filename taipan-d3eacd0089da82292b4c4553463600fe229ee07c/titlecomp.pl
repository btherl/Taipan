#!/usr/bin/perl -w

### see titlecompression.txt to understand how this works!

$datasize = 0x1700;

use bytes;

# skip xex header
#read(STDIN, our $junk, 6); # no longer need

read(STDIN, $data, $datasize);

for(split //, $data) {
	$got{ord($_)}++;
}

$firstcode = shift || 128; # must be >=128
if($firstcode eq '-l') {
	$list_codes = 1;
	$firstcode = 128;
	$tabsize = shift || 25;
}

for($firstcode..255) {
	push @available_codes, $_ unless $got{$_};
}
print scalar keys %got, " unique byte values\n";
print scalar @available_codes . " available run codes >= $firstcode\n";
if($list_codes) {
	$lowest = 256;
	$best = 0;
#	print join("\t", @available_codes) . "\n";
	for($i = 0; $i < @available_codes - $tabsize - 1; $i++) {
		$used = $available_codes[$i + $tabsize - 1] - $available_codes[$i] + 1;
		if($used < $lowest) {
			$lowest = $used, $best = $available_codes[$i];
		}
		print $available_codes[$i] . " " . $used . "\n";
	}
	print "== optimum firstcode value is $best\n";
	exit(0);
}

sub allocate_code {
	if(!@available_codes) {
		die "out of run codes!\n";
	}

	return shift @available_codes;
}

# add a $ff to the end, to force the last run to be written
# if the file ends in a run. Remove it afterwards.
$run = 0;
$output = "";
for(split //, $data . chr(0xff)) {
	if($_ eq "\0") {
		if($run) {
			$run++;
			if($run == 256) {
				die "can't handle runs >= 256, sorry\n";
			}
		} else {
			$run = 1;
		}
	} else {
		if($run > 1) {
			if($runlengths{$run}) {
				$output .= chr($runlengths{$run});
			} else {
				my $code = allocate_code();
				$runlengths{$run} = $code;
				$used_codes{$code} = $run;
				$output .= chr($code);
				$lastcode = $code;
			}
		} elsif($run == 1) {
			$output .= "\0";
		}
		$run = 0;
		$output .= $_;
	}
}

# remove the $ff we added above.
substr($output, -1) = "";

open $out, ">comptitle.dat";
print $out $output;
close $out;

$pct = int(length($output) * 1000 / length($data))/ 10;
print "1st code $firstcode, last $lastcode, table size " . ($lastcode - $firstcode + 1) . "\n";
print length($output) . " bytes compressed data, $pct% ratio\n";
print "used " . keys(%runlengths) . " codes\n";


for($firstcode..$lastcode) {
	$table .= " .byte ";
	if(exists($used_codes{$_})) {
		$table .= '$' . sprintf("%02x", $used_codes{$_}) . " ; " . sprintf("%02x", $_);
	} else {
		$table .= "\$00 ; SELF";
	}
	$table .= "\n";
}

open $in, "<comptitle.s.in" or die $!;
open $out, ">comptitle.s" or die $!;

while(<$in>) {
	s/__TABLE__/$table/;
	s/__FIRSTCODE__/$firstcode/g;
	s/__LASTCODE__/$lastcode/g;
	print $out $_;
}

close $in;
close $out;
