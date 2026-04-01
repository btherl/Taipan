#!/usr/bin/perl -w

if((-s $ARGV[0]) % 125 == 0) {
	die "$ARGV[0] is an even multiple of 125 bytes, it will NOT work with axe and fenders\n";
}
