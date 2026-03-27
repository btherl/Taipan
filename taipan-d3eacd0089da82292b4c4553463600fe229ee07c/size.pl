#!/usr/bin/perl -w

my $code_start = oct(shift) || die "no code start addr";
my $stack_size = oct(shift) || die "no stack size";

open MAP, "<taipan.map" or die $!;
while(<MAP>) {
	next unless /^BSS/;
	(undef, $bss_start, $bss_end, undef) = split /\s+/;
	$bss_start = hex $bss_start;
	$bss_end = hex $bss_end;
}
close MAP;

$free = (0xbc20 - $stack_size) - $bss_end + 1;
$code_size = $bss_start - $code_start;
$bss_size = $bss_end - $bss_start + 1;

printf "===>  code ends   at \$%04x (%d, %.1fK)\n", ($bss_start - 1), $code_size, $code_size / 1024;
printf "===>   BSS ends   at \$%04x (%d, %.1fK)\n", $bss_end, $bss_size, $bss_size / 1024;
printf "===> stack starts at \$%04x\n", 0xbc20 - $stack_size;
printf "===> free code space \$%04x (%d, %.1fK)\n", $free, $free, $free / 1024;
