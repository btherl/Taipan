# Makefile for Atari 800 Taipan, by B. Watson
# Written for GNU make, but seems to work with BSD make (though
# I don't test BSD make every time I change anything).

# 'make help' will show the list of targets.

# cl65 binary:
CC=cl65

# System cl65 will compile for. Don't expect this to work if you change it
# (though possibly atarixl might work someday, with newer cc65s)
SYS=atari

# Optimization flags for cc65.
#COPT=-Oirs
COPT=-O

# This is used for embedding the date and git info in the game binary.
# It'll appear on the title screen.
VER=0.99alpha
TODAY=`date +%Y%m%d`
#BRANCH=`( git branch 2> /dev/null || echo ' NOGIT' )| cut -d' ' -f2`
REV=`git rev-parse --short HEAD 2>/dev/null || echo UNKNOWN`
#VERSION="v$(VER)-$(TODAY)-$(BRANCH)-$(REV)"
VERSION="v$(VER)-$(TODAY)-$(REV)"

# Memory layout. Controlled by the Makefile from now on, no longer
# hardcoded addresses in various scripts. These are in hex. If any
# of them are changed, you *must* run 'make clean'.

# Font. Default is for the xex build. Cartridge build changes this.
FONT_ADDR=0x2000

# Title screen data will be decompressed to this address. XEX only,
# cartridge doesn't use compressed title.
TITLE_DATA_ADDR=0x2400

# Title display list, decompression code, and menu code. Should be
# TITLE_DATA_ADDR plus 0x1744. XEX only.
TITLE_CODE_ADDR=0x3b44

# Main game start address. All the code in TAIMAIN_C_SRC and
# TAIMAIN_ASM_SRC loads here. We get this address by looking for
# 'C code can load at' message when making newtitle.xex. It's the
# next byte after the end of the display list. Default is for the
# XEX, the cart changes it.
#TAIMAIN_ADDR=0x3d00
TAIMAIN_ADDR=0x3cc7

# Size of cc65 parameter stack in bytes. Default is 0x200, which is
# much bigger than actually necessary.
STACK_SIZE=0x200

# for older cc65, we needed a custom linker file.
#CFLAGS=-t $(SYS) -C custom.cfg -I. -L. $(COPT)

# for recent git cc65, we can reserve memory on the command line.
# -D__RESERVED_MEMORY__=1056 because cc65's default end of memory
# is $BC20, and we want it to end just below our font, which starts
# at $B800. cc65's runtime stack starts just below this, and is
# 2K in size (bottom is at 0xb000).
# -D__SYSTEM_CHECK__=1 stops cl65 from prepending a bit of code that
# checks to make sure there's enough memory. Older cc65 didn't do this,
# and I never missed it.
# The meaning of the -l flag is different between cc65-2.13.3
# and the later github cc65, so it's been removed here.
#CFLAGS=-t $(SYS) -T -I. -L. -Wl -D__SYSTEM_CHECK__=1 -Wl -D__RESERVED_MEMORY__=1056 $(COPT)

CFLAGS=-t $(SYS) -T -I. -L. -Wl -D__SYSTEM_CHECK__=1 -DFONT_ADDR=$(FONT_ADDR) --start-addr $(TAIMAIN_ADDR) -Wl -D__STACKSIZE__=$(STACK_SIZE) $(COPT) $(EXTRACFLAGS)

# These aren't really used:
AS=ca65
ASFLAGS=
AR=ar65

# C compiler for host system. Currently only used for building convfont
# and mkcart.
HOSTCC=gcc
HOSTCFLAGS=-Wall

# Perl binary. This Makefile relies heavily on perl.
PERL=perl

# Flags to pass to perl. We're dealing with raw binary data, not
# utf-8 encoded unicode text. The -C0 tells perl to ignore any
# PERL_UNICODE setting in the environment (see "perldoc perlrun").
PERLFLAGS=-C0

PERLF=$(PERL) $(PERLFLAGS)

# romfont is the 1K font extracted from the Atari 800 OS, with a
# command like:
# dd if=atariosb.rom of=1 bs=256 skip=8 count=4
# ...where atariosb.rom comes from e.g. the PC-Xformer 2.5 zip file.

# The game binary:
XEX=taipan.xex

# All the C and asm sources for taimain.xex:
TAIMAIN_HDRS=sounds.h
TAIMAIN_C_SRC=taipan.c strtonum.c
TAIMAIN_ASM_SRC=rand.s draw_lorcha.s timed_getch.s portstat.s console.s cprintul.s soundasm.s explosion.s textdecomp.s arrayutils.s
TAIMAIN_LIBS=conio/conio.lib

# Comment these lines out to build without big number support.
# This will stop being possible at some point.
BIGNUM_SRC=bigfloat.s
BIGNUM_HDRS=bignum.h bigfloat.h
BIGNUM_CFLAGS=-DBIGNUM=BIGFLOAT

# Uncomment these for experimental int48 big numbers. Support
# hasn't been added, so leave these commented for now.
#BIGNUM_SRC=bigint48.s
#BIGNUM_HDRS=bignum.h bigint48.h
#BIGNUM_CFLAGS=-DBIGNUM=BIGINT48

# Default rule for plain 'make' command is to build the binary.
all: checkenv $(XEX) tags

biginttest: clean
	$(MAKE) BIGNUM_SRC=bigint48.s BIGNUM_HDRS="bignum.h bigint48.h" BIGNUM_CFLAGS=-DBIGNUM=BIGINT48
	atari800 -nobasic $(XEX)

# I have F10 in my editor bound to 'make test', so:
test: clean all
	atari800 -nobasic $(XEX)

# Check the build environment.
checkenv:
	@$(PERL) -e1 && echo "perl found" && exit 0 || echo "perl missing" && exit 1
	@$(PERL) -MImage::Magick -e1 && echo "perl Image::Magick found" && exit 0 || echo "perl Image::Magick missing" && exit 1
	@$(CC) --help > /dev/null && echo "cl65 found" && exit 0 || echo "cl65 missing (install cc65)" && exit 1
	@echo "int main() { return 0; }" > 1.c && exit 0 || echo "can't create files in current directory" && exit 1
	@$(HOSTCC) -o 1 1.c && echo "host C compiler found" && exit 0 || echo "host C compiler missing or broken" && exit 1

# ctags. I forgot it can handle cc65 asm source. One wrinkle: C
# identifiers get prepended with an underscore from the POV of assembly
# code, and asm identifiers need a leading underscore to be used from
# C. There's probably a clever way to get ctags to handle this, but I
# don't know it, so I wrote a perl script to do the job.
tags:
	@ctags $(TAIMAIN_C_SRC) $(TAIMAIN_ASM_SRC) 2>/dev/null && $(PERLF) fixtags.pl tags || true

help:
	@echo "Top-level targets:"
	@echo "make          - builds taipan.xex (disk version)"
	@echo "make cart     - builds taipan.rom and taipan.cart (cartridge version)"
	@echo "make test     - builds & runs taipan.xex in atari800 emulator"
	@echo "make testcart - builds & runs taipan.cart in atari800 emulator"
	@echo "make dos2     - builds & runs taipan.xex in atari800 on a "; \
	 echo "                DOS 2.0S floppy image [*]"
	@echo "make mydos    - builds & runs taipan.xex in atari800 on a "; \
	 echo "                MyDOS 4.50 floppy image [*]"
	@echo "make fenders  - builds & runs taipan.xex in atari800 on a "; \
	 echo "                Fenders 3-sector Loader floppy image [*]"
	@echo
	@echo "[*] floppy image targets require 'axe' utility, from:"
	@echo "    https://slackware.uk/~urchlay/src/axe-0.2.0.tar.gz"
	@echo
	@echo "Useful variables to add to the make command:"
	@echo "  CC          - path to cl65 binary (default: cl65, searches PATH)"
	@echo "  EXTRACFLAGS - extra options to pass to cl65"
	@echo "  HOSTCC      - path to native C compiler (default: gcc, searches PATH)"
	@echo "  HOSTCFLAGS  - extra options to pass to HOSTCC (default: -Wall)"
	@echo "  PERL        - path to perl binary (default: perl, searches PATH)"

# The above is fast & easy, but from time to time it's necessary
# to test slow loading, make sure the title screen stuff works OK.
dos2: clean all
	cp dos2.atr.in dos2.atr
	cp taipan.xex TAIPAN
	axe -w TAIPAN dos2.atr
	rm -f TAIPAN
	atari800 -nobasic -nopatch dos2.atr

fenders: clean all
	perl axecheck.pl taipan.xex
	cp taipan.xex TAIPAN
	cp fenders.atr.in fenders.atr
	axe -w TAIPAN fenders.atr
	rm -f TAIPAN
	atari800 -nopatch fenders.atr

mydos: clean all
	cp taipan.xex TAIPAN
	cp mydos.atr.in mydos.atr
	axe -w TAIPAN mydos.atr
	rm -f TAIPAN
	atari800 -nopatch mydos.atr

# We use our own custom conio instead of the one cc65 ships.
# see conion/README for details.
conio/conio.lib:
	cd conio && $(MAKE)

# The game binary is a multi-part binary load file. This rule
# depends on all the pieces, and just concatenates them. We used
# to just use cat, but reportedly some (dumb, broken) xex loaders
# have trouble with $FFFF markers at the start of the second and
# further segments, so multixex.pl skips them.
$(XEX): checkmem.xex taimain.xex taifont.xex newtitle.xex comptitle.xex
	$(PERLF) multixex.pl checkmem.xex comptitle.xex newtitle.xex taifont.xex taimain.xex > $(XEX)
	$(PERLF) size.pl $(TAIMAIN_ADDR) $(STACK_SIZE)

# Bitmap data for the title screen, 256x184 = 47104 pixels, 8 bits
# per pixel, or 5888 bytes. Displayed in ANTIC mode F (aka GR.8),
# using GTIA narrow playfield. The original title screen for the Apple
# is a 280x192 bitmap with a few blank lines at the top & bottom. I
# squished it horizontally to 256 pixels and got rid of the blank lines,
# to save load time. Note that titledata.dat is not built into
# the xex binary as-is: it's now used as input for creating
# comptitle.xex, the compressed title screen. For the cartridge,
# titledata.dat is included as-is.
titledata.dat: newtitle.pl newtitle.png
	$(PERLF) newtitle.pl > titledata.dat

# compressed title, for faster loading. see titlecompression.txt
# for gory details.
comptitle.xex: titledata.dat titlecomp.pl comptitle.s.in
	$(PERLF) titlecomp.pl 133 < titledata.dat
	$(CC) -l comptitle.lst -o comptitle.xex -t none --asm-define destination=$(TITLE_DATA_ADDR) comptitle.s

# tiny 1-sector memory checker, aborts the laod if a cart is present.
checkmem.xex: checkmem.s
	$(CC) -o checkmem.xex -t none checkmem.s

# Init segment that loads after the title screen data. It sets up
# a custom display list and sets the GTIA for narrow playfield,
# then waits for a keypress. Afterwards, it restores the OS's
# display list and sets the GTIA back to normal, then exits.
# Notice this is built with "-t none" instead of "-t atari",
# since it's a lot easier to homebrew an init segment than it is
# to get cc65 to build an init segment (would need a custom linker
# script at least).
newtitle.xex: newtitle.s ver.dat help.dat
	$(CC) -l newtitle.lst -m newtitle.map -o newtitle.xex -t none --asm-define screendata=$(TITLE_DATA_ADDR) --asm-define origin=$(TITLE_CODE_ADDR) newtitle.s

# Version number in Atari screen-data form
ver.dat: text2screen.pl
	echo "$(VERSION)" | $(PERLF) text2screen.pl > ver.dat

# Help text for the title screen
help.dat: help.txt text2screen.pl
	$(PERLF) text2screen.pl < help.txt > help.dat

#ver.dat: mkver.pl
#	$(PERL) mkver.pl $(VERSION) > ver.dat

# The main executable. All the C and asm code goes here, except the init
# segment in newtitle.s.
taimain.xex: $(TAIMAIN_C_SRC) $(TAIMAIN_ASM_SRC) $(TAIMAIN_HDRS) $(BIGNUM_SRC) $(BIGNUM_HDRS) $(TAIMAIN_LIBS) messages.c LORCHA.DAT
	$(CC) -m taipan.map $(CFLAGS) $(BIGNUM_CFLAGS) -o taimain.xex $(TAIMAIN_C_SRC) $(TAIMAIN_ASM_SRC) $(BIGNUM_SRC) $(TAIMAIN_LIBS)

#cl65 --mapfile taipan.map $(CFLAGS) -o taimain.xex taipan.c sounds.c rand.s draw_lorcha.s timed_getch.s jsleep.s portstat.s console.s

# With newer cc65s, I have to do this to get an assembly listing of just
# taipan.c. This rule not used as part of the main build, it's only for
# debugging.
taipan.lst: taipan.c
	$(CC) -m taipan.map $(CFLAGS) $(BIGNUM_CFLAGS) -c -o /dev/null -l taipan.lst -T taipan.c

# Another such rule for sounds.c:
sounds.lst: sounds.c sounds.h
	$(CC) -m sounds.map $(CFLAGS) -c -o /dev/null -l sounds.lst -T sounds.c

LORCHA.DAT: taifont.xex

# The font gets loaded into RAM, in the area reserved by the
# -D__RESERVED_MEMORY__ option to cl65. To actually use the font,
# taimain.xex contains code that sets CHBAS ($02f4).
taifont.xex: convfont romfont font
	cat romfont font | ./convfont -x > taifont.xex

# Used by the cartridge build, but not the disk (xex) binary. This just
# builds the font without the Atari 6-byte binary load header. It ends
# up at the top of one of the cartridge banks, and is also useful for
# eyeballing the font in bitmapdump.pl or converting to other formats.
taifont: convfont romfont font
	cat romfont font | ./convfont > taifont

# PORTSTAT.DAT gets incbin'ed directly in portstat.s. It's screen-code
# data for the static part of the port status screen, which ends up in
# an array that the C code can memcpy() into screen RAM as needed.
# This make rule actually runs atari800. For it to work, you'll need
# the H: device enabled, pointed at the current directory, and set
# to writable.
PORTSTAT.DAT: mkportstats.xex
	atari800 -H1 . -hreadwrite -nobasic mkportstats.xex
	touch portstat.s

# Host tool that builds our custom font from the data ripped out of
# the Apple version, plus the Atari OS ROM. Also, all the custom
# characters for the enemy ships are defined here (as hex data. Yes,
# I converted them manually from eyeballing a screenshot of the Apple
# combat screen).
convfont: convfont.c
	$(HOSTCC) $(HOSTCFLAGS) -DFONT_ADDR=$(FONT_ADDR) -o convfont convfont.c

# text compressor
textcomp: textcomp.c
	$(HOSTCC) $(HOSTCFLAGS) -o textcomp textcomp.c

# textdecomp.s includes msg.inc
textdecomp.s: msg.inc

msg.inc: messages.c

# messages.c is a generated file
messages.c: messages.pl messages.msg textcomp
	perl messages.pl < messages.msg > messages.c

helpmsgs.c: messages.pl helpmsgs.msg textcomp
	perl messages.pl -n < helpmsgs.msg > helpmsgs.c

### Cartridge-related targets. The way I'm doing this isn't 'proper': I should
#   be using cc65's linker with a fancy config script to do the bank layout
#   and such. But it's a lot easier for me to use the tools I know how to use,
#   so that's what I did.

# mkcart turns a raw binary into an atar800 .cart image with 16-byte header.
# originally I wrote this for use with the DASM assembler, but there's
# nothing DASM-specific about it.
mkcart: mkcart.c
	$(HOSTCC) $(HOSTCFLAGS) -o mkcart mkcart.c

cartbank2.cfg: cartbank2.cfg.old cartbank2.cfg.new cartbank2.sh
	sh cartbank2.sh

# cc65 doc atari.html explains how to produce a raw binary file.
# using a custom crt0 to get rid of the extra RTS cc65 puts there for
# SpartaDOS compatibility (which has no effect on a cartridge image,
# except to waste 1 byte).
romable_taimain.raw: cartbank2.cfg $(TAIMAIN_C_SRC) $(TAIMAIN_ASM_SRC) $(TAIMAIN_HDRS) $(BIGNUM_SRC) $(BIGNUM_HDRS) $(TAIMAIN_LIBS) crt0_cart.s messages.c helpmsgs.c LORCHA.DAT
	$(CC) --config cartbank2.cfg -m taipan.map -t atari -T -I. -L. -DFONT_ADDR=0x9c00 --start-addr 0x400 -Wl -D__STACKSIZE__=0x200 -O -Wl -D__SYSTEM_CHECK__=1 -Wl -D__AUTOSTART__=1 -Wl -D__EXEHDR__=1 --asm-define GAME_HELP=1 -DGAME_HELP -DCART_TARGET=1 --asm-define CART_TARGET=1 -DBIGNUM=BIGFLOAT -o romable_taimain.raw $(TAIMAIN_C_SRC) $(TAIMAIN_ASM_SRC) $(BIGNUM_SRC) $(TAIMAIN_LIBS) crt0_cart.s gamehelp.s

# 8192 bytes of $ff filler, for unused banks. Possibly these will be
# used for something like an interactive game manual/tutorial.
#blankbank:
#	$(PERLF) -Mbytes -e 'print chr(0xff) x 8192' > blankbank

splitrom.raw.0: splitrom.raw.2

splitrom.raw.1: splitrom.raw.2

# split romable_taimain.raw into bank-sized chunks. if we end up
# with 3 chunks, the cart won't work correctly, so stop the build here
# in that case.
splitrom.raw.2: romable_taimain.raw
	split -b 8192 -a 1 -d romable_taimain.raw splitrom.raw.
	[ -e splitrom.raw.3 ] && echo "*** romable_taimain.raw too big" && rm -f splitrom.raw.* && exit 1 || exit 0

bank0: splitrom.raw.0 checkbank0.pl
	cat splitrom.raw.0 > bank0
	$(PERLF) checkbank0.pl bank0

bank1: splitrom.raw.1
	cat splitrom.raw.1 > bank1

bank2: rodata.8000 bank2.s taifont romable_taimain.raw
	$(CC) -l bank2.lst -m bank2.map -t none -o bank2 bank2.s

bank3: bank3.s titledata.dat ver.dat help.dat newtitle.s splitrom.raw.2
	$(CC) -l bank3.lst -m bank3.map -t none -o bank3 bank3.s

# raw ROM, for burning to EPROM/flash.
taipan.rom: bank0 bank1 bank2 bank3
	cat bank0 bank1 bank2 bank3 > taipan.rom

# .cart version with atari800-compatible header.
taipan.cart: taipan.rom mkcart
	./mkcart -otaipan.cart -t12 taipan.rom
	./mkcart -ctaipan.cart

cart: checkenv taipan.cart

testcart: clean cart
	atari800 taipan.cart


### Rules for building various file types with the cc65 toolchain.
.s.o:
	$(AS) $(ASFLAGS) -o $@ $<

.c.o:
	$(CC) $(CFLAGS) -c -o $@ $<

%.xex: %.c
	$(CC) --mapfile map $(CFLAGS) -o $@ $<

# Obligatory clean and distclean rules.
clean:
	rm -f *.o *.lst convfont mkcart gzip2deflate *.xex AUTORUN.SYS taipan.atr dos2.atr mydos.atr fenders.atr ver.dat help.dat tags cartmsg.dat splitrom.raw.* taipan.rom taipan.cart bank[0-9] fill256 blankbank romable_taimain.raw splitrom.raw.* comptitle.s comptitle.dat conio/*.o conio/*.lib messages.c textcomp titledata.dat cartbank2.cfg LORCHA.DAT DAMAGED.DAT lorcha.txt damaged.txt

distclean: clean
	rm -f *~ core .*.swp 1.* 2.* 1 2 3 map map.* *.map a b c foo bar baz

push:
	sh push.sh

size: clean all
	$(PERLF) size.pl $(TAIMAIN_ADDR) $(STACK_SIZE)

procsizes: clean all taipan.lst
	$(PERLF) procsizes.pl > procsizes
	cat procsizes

# These 3 are informational only, for when you're editing the ship
# graphics in convfont.c.
lorcha.txt: shipshape.pl LORCHA.DAT
	$(PERLF) shipshape.pl LORCHA.DAT > lorcha.txt

damaged.txt: shipshape.pl LORCHA.DAT
	$(PERLF) shipshape.pl DAMAGED.DAT > damaged.txt

damaged2.txt: shipshape.pl LORCHA.DAT
	$(PERLF) shipshape.pl DAMAGED2.DAT > damaged2.txt

# This one build the sound code as a standalone xex.
soundtest: sounds.c
	$(CC) -DTESTXEX -t atari -o sounds.xex sounds.c
	atari800 -nobasic sounds.xex

