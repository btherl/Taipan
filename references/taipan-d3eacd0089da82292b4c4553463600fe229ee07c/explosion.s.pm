; explosion seen when we're hit by enemy fire.
; this draws something that looks a bit like TV static, only
; it's a lot more regular and less random. it somewhat approximates
; the apple version's explosion, but not all that closely.

 .export _explosion
 .include "atari.inc"
 .importzp tmp1, tmp2
 .import _jsleep

static_loop_count = tmp1

; extern void explosion(void);
; {
_explosion:

 ldy #3 ; explosion_loop counter, counts 3 2 1

;   {
@explosion_loop:
 lda #$05 ; static_loop runs 3 times
 sta static_loop_count

;     {
@static_loop:
 ldx #0         ; jsleep(2)
 lda #$01
 jsr _jsleep

 ldx #2

;         {
;           {
; let the top part of the screen display normally.
; garbage begins to display on gr.0 line 8 (the one above the tops
; of the top row of lorchas).
@wait4scanline:
 lda VCOUNT
 cmp #(4+8)*4
 bne @wait4scanline
;           }

;           {
; store random stuff into the players/missiles
@randpm:
 sta WSYNC
 lda RANDOM
 sta GRAFP0
 lda RANDOM
 sta GRAFP1
 lda RANDOM
 sta GRAFP2
 lda RANDOM
 sta GRAFP3
 lda RANDOM
 sta GRAFM

 lda VCOUNT
 cmp #(4+23)*4
 bne @randpm ; stop garbage 2 lines after the bottom row of lorchas
;           }

 ; clear P/M for rest of frame
 lda #0
 sta GRAFP0
 sta GRAFP1
 sta GRAFP2
 sta GRAFP3
 sta GRAFM

 lda RTCLOK+2
;           {
; wait for start of next TV frame.
@wait4frame:
cmp RTCLOK+2
 beq @wait4frame
;           }

 dex
 bne @wait4scanline
;       }

 dec static_loop_count
 bne @static_loop
;     }

 ldx #0         ; jsleep(10)
 lda #$0a
 jsr _jsleep

 dey
 bne @explosion_loop ; we're done if Y==0
;   }

 rts
; }
