; default cartridge name
;
; Christian Groessler, 01-Mar-2014
; modified for taipan

; anything in CAPS will rotate colors

.include        "atari.mac"

.export         __CART_NAME__: absolute = 1

.segment        "CARTNAME"

                scrcode "    taipan ALPHA    "
