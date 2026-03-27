#!/usr/bin/perl -w

open IN, "<taipan.lst" or die $!;

while(<IN>) {
	(/^([0-9A-F]{6})/) && (eval "\$addr = 0x$1");
	if(/\.proc\s+_(\w+)/) {
		$proc = $1;
		$start{$proc} = $addr;
	} elsif(/\.endproc/) {
		$end{$proc} = $addr - 1;
		$proc = "";
	}
}

for(sort keys %start) {
	$len{$_} = $end{$_} - $start{$_} + 1;
}

for(sort { $len{$a} <=> $len{$b} } keys %len) {
	printf "% 32s % d\n", $_, $len{$_};
	$total += $len{$_};
}
printf "% 32s % d\n", "Total:", $total;
