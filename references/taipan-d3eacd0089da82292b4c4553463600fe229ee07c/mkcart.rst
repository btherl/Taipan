======
mkcart
======

-------------------------------------------------------
Convert between raw ROM images and atari800 CART format
-------------------------------------------------------

.. |date| date::

:Manual section: 1
:Manual group: DASM-Dillon
:Authors: `B. Watson <yalhcru@gmail.com>`
:Date: |date|
:Version: 2.10.12
:Copyright: This document is licensed under the same terms as DASM
            itself, see the file COPYING for details.

SYNOPSIS
========

mkcart -oCARTFILE -tTYPE RAWFILE [RAWFILE ...]

mkcart -cCARTFILE

mkcart -xRAWFILE CARTFILE

mkcart -l

DESCRIPTION
===========

A companion tool to `dasm(1)`, mkcart can:

- convert one or more `dasm(1)` raw (-f3) object files to a CART image
  format for use with emulators such as `atari800(1)`.

- convert a CART image back to a raw image.

- check the integrity and report information about a CART image.

OPTIONS
=======

-tTYPE       Cartridge type (1-67, see `-l` for list), default = guess (poorly!).
             Only used in -o mode.

-oCARTFILE   Create CARTFILE from RAWFILE(s). `-t` optional but highly
             recommended.

-cCARTFILE   Check integrity of file (header, checksum, and size).

-xRAWFILE    Create raw binary from CARTFILE (remove header).

-l           List all supported -t types with their sizes in
             bytes and their human-readable names, and exit.

-?, -h       Show built-in help message.

EXAMPLES
========

| # a standard 8KB cartridge:
| dasm example.asm -f3 -oexample.bin
| mkcart -oexample.cart -t1 example.bin

| # a bankswitched OSS 16KB cartridge:
| dasm bank1.asm -f3 -obank1.bin
| dasm bank2.asm -f3 -obank2.bin
| mkcart -oexample.cart -t15 bank1.bin bank2.bin

EXIT CODES
==========

With -o and -x, mkcart will exit with status `0` if it was able
to complete the conversion, or `1` if something went wrong.

With -c, mkcart will exit with status `0` if the image is OK (has a
valid header, known type, good checksum, etc), or `1` if not.

BUGS
====

With -o and -x, the input files are opened, read, and closed twice:
once to calculate the checksum and verify that there's enough data, then
the header is written and the input files are re-opened and reread. Bad
Things will probably happen if any of the input files change in between
the two passes.

The -x option should split bankswitched cartridges into multiple raw
images instead of one combined image. Workaround: use `split(1)`
or `dd(1)` to split the raw image into bank-sized chunks:

| mkcart -xmac65.bin mac65.cart

| # split into mac65.bank00 and mac65.bank01
| split -b8192 mac65.bin mac65.bank

| # same thing, with dd
| dd if=mac65.bin of=mac65.bank00 bs=1024 count=8
| dd if=mac65.bin of=mac65.bank01 bs=1024 count=8 skip=8

Either way, you have to know the bank size (usually 8 or 16 KB), which
is less than ideal.

SEE ALSO
========

* `dasm(1)`
* `atari800(1)`
* `cart.txt`
