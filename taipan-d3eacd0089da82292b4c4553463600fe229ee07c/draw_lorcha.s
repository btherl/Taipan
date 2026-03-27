; Atari Taipan routines for rendering enemy lorchas.

; Lorcha (boat), a type of sailing vessel having a Chinese
; junk rig on a Portuguese or European style hull.

 .include "atari.inc"

 .import _jsleep
 .export _draw_lorcha, _sink_lorcha, _damage_lorcha, _clear_lorcha, _flash_lorcha

; TODO: maybe replace position tables with mul40? see
; libsrc/atari/mul40.s, which is getting linked anyway
; because conio uses it.

 .rodata
; offset from start of screen for each ship position (0-9)
lorcha_pos_lo:
 .byte <320, <328, <336, <344, <352
 .byte <640, <648, <656, <664, <672
lorcha_pos_hi:
 .byte >320, >328, >336, >344, >352
 .byte >640, >648, >656, >664, >672

; ZP working variables start at $d4, aka FR0 (floating point reg 0).
 temp = $d4
 andmask = temp
 flashing = temp+1
 destptr = $d6
 lcount = $d8
 which = $d9
 sinkdelay = $da

; clrtobot.s needs these:
 .exportzp destptr
 .export bump_destptr

; Our lorcha is a 7x7 block of ATASCII characters. We're storing
; directly to screen RAM, so we use 'internal' codes.
; To edit the graphics, see shipshape[] in convfont.c.
lorcha_data:
 .incbin "LORCHA.DAT"

; fully-damaged version of the lorcha, damaged_shipshape[] in convfont.c
damaged_data:
 .incbin "DAMAGED.DAT"

; fully-damaged version of the lorcha, damaged_shipshape2[] in convfont.c
damaged_data2:
 .incbin "DAMAGED2.DAT"

 .ifdef CART_TARGET
  .segment "HIGHCODE"
 .else
  .code
 .endif

; void __fastcall__ flash_lorcha(int which);
_flash_lorcha:
 ldx #$80
 stx flashing
 bne drawit

; void __fastcall__ clear_lorcha(int which);
_clear_lorcha:
 ldx #0
 stx andmask
 stx flashing
 beq drawit

; void __fastcall__ draw_lorcha(int which);
_draw_lorcha:
 ldx #$ff
 stx andmask
 ldx #0
 stx flashing

; the above 3 entry points set up flashing and/or andmask,
; then branch to the common routine here.
; flashing = 1: invert all the character codes (ignore andmask). turns
;               ship inverse, or back to normal, using the data that's
;               already in screen RAM (meaning, damage is preserved).
; flashing = 0: copy lorcha_data to destptr, ANDing with andmask:
;               andmask = 0: clear lorcha
;               andmask = $ff: draw lorcha

drawit:
 tax
 jsr setup_destptr
 ldx #0
line:
 ldy #0
char:
 bit flashing
 bpl noflash
 lda (destptr),y
 eor #$80
 clc
 bcc storeit
noflash:
 lda lorcha_data,x
 and andmask
storeit:
 sta (destptr),y
 inx
 iny
 cpy #7
 bne char
 jsr bump_destptr
 cpx #49
 bne line
 rts

; sinking the lorcha means copying each line of screen RAM
; from the one above it. has to be done in reverse order.
_sink_lorcha:
 sta which
 lda #6
 sta lcount

 ; set sinkdelay to 3, 5, or 7 jiffies
@rnd:
 lda RANDOM
 eor RTCLOK+2
 and #$06
 beq @rnd
 ora #1
 sta sinkdelay

sinkloop:
 ldx which
 jsr setup_destptr
 clc
 lda destptr
 adc #200 ; 40 bytes/line * 5 lines
 sta destptr
 lda destptr+1
 adc #0
 sta destptr+1

 ; delay for sinkdelay jiffies
 ldx #0
 lda sinkdelay
 jsr _jsleep

 ldx #6 ; line loop counter

 ; at start of loop, destptr points to last line, and temp
 ; is unitialized.
slineloop:

 ; temp=destptr; destptr-=40;
 lda destptr
 sta temp
 sec
 sbc #40
 sta destptr
 lda destptr+1
 sta temp+1
 sbc #0
 sta destptr+1

 ; now loop over 7 bytes
 ldy #6
sbyteloop:
 lda (destptr),y
 sta (temp),y
 dey
 bpl sbyteloop
 dex
 bpl slineloop
 dec lcount
 bpl sinkloop

 rts ; end of _sink_lorcha
;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_damage_lorcha:
 tax
 jsr setup_destptr

xrand:
 ; get random number 0-48 in X:
 lda RANDOM
 lsr
 lsr
 cmp #49
 bcs xrand
 tax

getpiece:
 bit RANDOM
 bpl @used2
 lda damaged_data,x
 jmp @can_dmg

@used2:
 lda damaged_data2,x

@can_dmg:
 cmp lorcha_data,x
 beq xrand ; if it's a piece that can't show damage,
                    ; ditch it and start over
 sta temp ; stash the piece

 ; which row/col? call bump_destptr (x/7)-1 times.
 txa
calcrow:
 sec
 sta temp+1 ; this holds the modulus (x%7)
 sbc #7
 bcc rowdone
 pha
 jsr bump_destptr
 pla
 clc
 bcc calcrow

rowdone:
 ldy temp+1

 lda (destptr),y
 cmp lorcha_data,x    ; if it's already damaged,
 bne @ret             ; leave it alone.

 lda temp ; the piece
 sta (destptr),y

@ret:
 rts ; end of _damage_lorcha

; a couple of utility functions for dealing with destptr:

; add 40 to destptr. trashes A, preserves X/Y.
bump_destptr:
 lda destptr
 clc
 adc #40
 sta destptr
 lda destptr+1
 adc #0
 sta destptr+1
 rts

; sets up destptr to point to correct position for the given
; ship number (0-9) in X reg. trashes A, preserves X/Y.
setup_destptr:
 lda lorcha_pos_lo,x
 clc
 adc SAVMSC
 sta destptr
 lda lorcha_pos_hi,x
 clc
 adc SAVMSC+1
 sta destptr+1
 rts
