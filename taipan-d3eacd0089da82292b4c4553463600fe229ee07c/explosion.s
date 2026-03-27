; explosion seen when we're hit by enemy fire.

; flash the part of the screen where the lorchas are displayed.
; previously this flashed the whole screen, but it gave me a
; headache. plus, the apple version's "tv static" effect only appears
; on the lorcha area of the screen, so this is closer to the original
; than a fullscreen flash would be.

; we're not using a display list interrupt here. basically each flashed
; frame is:
; - sync CPU to ANTIC using VSYNC and WSYNC.
; - change HW color registers for text and background.
; - wait until enough scanlines have been drawn.
; - change the colors back to normal.

; pseudo-C for explosion():
; for(Yreg = flashes; Yreg > 0; --Yreg) {
;   for(framecounter = jiffies; framecounter > 0; --framecounter) {
;     // this loop body takes 1 jiffy to execute
;     while(VCOUNT < startvcount)
;       ;
;     set_flashed_colors();
;     while(VCOUNT < endvcount)
;       ;
;     set_normal_colors();
;   }
;   jsleep(jiffies); // unflashed display for equal amount of time
; }

 .export _explosion
 .include "atari.inc"
 .importzp tmp1, tmp2
 .import _jsleep

 .ifdef CART_TARGET
  .segment "HIGHCODE"
 .else
  .code
 .endif

; how many times the screen will appear to flash.
flashes = 3

; timing, in jiffies. each flash shows this many 'flashed' frames,
; followed by the same number of normal frames. the whole explosion takes
; ((jiffies * flashes * 2) / 60) seconds, or 1 second for jiffies = 10
; on NTSC (for PAL, it's 1.2 seconds).
jiffies = 10

; VCOUNT value where we will start the flash effect. Remember, VCOUNT is
; (scanlines / 2), and a GR.0 text line is 8 scanlines, or 4 VCOUNTs.
; There are 3 'blank for 8 lines' instructions at the top of the GR.0
; display list, so the first visible GR.0 line starts at (4+0)*4.
; The value below is the start of the GR.0 line before the top row
; of lorchas.
startvcount = (4+8)*4

; VCOUNT value where we will stop the flash effect and restore normal
; playfield colors. Value below is 2 GR0 lines after the bottom row
; of lorchas.
endvcount = (4+23)*4

; use zero page rather than X register for frame counter, since
; _jsleep will trash the X register.
framecounter = tmp1

; bottom 4 bits of COLOR1. Will be ORed with the top 4 bits (the hue)
; of COLOR2, to get the 'flashed' text background color. The flashed
; text color is always 0 (black, or actually darkest luma of whatever
; hue the text BG color is).
textluma = tmp2

; extern void explosion(void);
_explosion:
; {
 ldy #flashes ; outerloop counter

 lda COLOR1   ; can't hardcode this, since it can be changed
 and #$0f     ; at the title screen.
 sta textluma
;   {
; each time thru outerloop, show 'jiffies' frames of flash and another
; 'jiffies' frames of normal display (so the flashing toggles on and off
; 'flashes' times).
@outerloop:
 lda #jiffies
 sta framecounter ; inner loop, counts 10 to 1

@frameloop:
;     {
@wait4startscanline:
;       {
 lda VCOUNT ; delay until start of flashing area
 cmp #startvcount
 bne @wait4startscanline
;       }

 ; set_flashed_colors();
 sta WSYNC ; finish current scanline (avoid tearing)

 ; we're in the horizontal blank now. De Re Atari, Chapter 5, says we get
 ; "from 17 to 26 cycles". We're not using P/M and there's no LMS here,
 ; but 1 or 2 cycles may be stolen by memory refresh. The "sta COLPF1"
 ; only has to finish before any non-space characters are displayed on
 ; the scanline, which would give us a couple extra cycles if needed,
 ; since there's a border of spaces around the lorchas.

 lda COLOR2    ; +4 = 4
 and #$f0      ; +2 = 6
 ora textluma  ; +3 = 9
 sta COLPF2    ; +4 = 13
 lda #0        ; +2 = 15
 sta COLPF1    ; +4 = 18

;       {
@wait4endscanline: ; delay until end of flashing area
 lda VCOUNT
 cmp #endvcount
 bne @wait4endscanline
;       }

 ; set_normal_colors();
 sta WSYNC
 lda COLOR2 ; put colors back like they were for the rest of the frame.
 sta COLPF2
 lda COLOR1
 sta COLPF1

 dec framecounter
 bne @frameloop ; inner loop done when framecounter == 0
;     }

 ldx #0        ;\
 lda #jiffies  ; | jsleep(jiffies);
 jsr _jsleep   ;/

 dey
 bne @outerloop ; we're done if Y == 0
;   }

 rts
; }
