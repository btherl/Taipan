#!/usr/bin/perl -w

# we're looking for this:

# 00111000
# 01000100
# 10101000
# 10100000
# 10100000
# 01000100
# 00111000

#@want = (
#0b10101000,
#0b10100000,
#);

@want = (
0b00000101,
0b00000101,
);

#@want = (
#0b00111000,
#0b01000100,
#0b10101000,
#0b10100000,
#0b10100000,
#0b01000100,
#0b00111000,
#);

# or possibly a version of it shifted 1 or 2 bits to the right

undef $/;
$img = <>;
@bytes = map { ord($_) } split //, $img;
for($i = 0; $i < @bytes - 7; $i++) {
	my $found = 1;
	for($j = 0; $j < @want; $j++) {
		if($bytes[$i+$j] != $want[$j]) {
			$found = 0;
		}
	}
	if($found) {
		printf "offset: %x\n",  $i;
	}
}

