; Cartridge copyright year
;
; Christian Groessler, 01-Mar-2014

; modified for taipan

.export         __CART_YEAR__: absolute = 1

.segment        "CARTYEAR"

                .byte   $ff, $ff ; $ff in 2nd byte means diagnostic cart
