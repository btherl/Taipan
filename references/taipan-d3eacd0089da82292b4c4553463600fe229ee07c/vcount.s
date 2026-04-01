 .export _waitvcount

 .include "atari.inc"

; wait for VCOUNT to reach a particular value. Use this
; to avoid updating parts of the screen while ANTIC is
; reading from it.

; c should be ((4 + Yposition) * 4), where Yposition is
; the text line below the bottom one you're about to modify.

; void __fastcall__ waitvcount(unsigned char *c)
_waitvcount:
 sta FR1

w:
 lda VCOUNT
 cmp FR1
 bne w

 STA WSYNC ; finish current scanline
 rts
