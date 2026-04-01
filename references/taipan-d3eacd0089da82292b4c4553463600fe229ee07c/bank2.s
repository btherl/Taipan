
 .include "atari.inc"

 ; where the font lives. Must agree with bank3.s.
font = $9c00

 .org $8000
 .incbin "rodata.8000"

 .if * > font
  .fatal "bank2 code too large"
 .else
  .out .sprintf("=> %d bytes free in bank 2", font - *)
 .endif

 .res font - *, $ff
 .incbin "taifont"
