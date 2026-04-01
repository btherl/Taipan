; Sounds for Taipan! Atari 800 port.

; Made by capturing the Apple II audio and taking wild guesses,
; then refining them.

; I'm not shooting for Atari sounds that are identical to the
; Apple ones: (a) it's impossible anyway, and (b) the Apple
; sounds are a bit harsh to the ear. Hopefully these sound
; a little smoother while still being pretty close.

; This is an asm rewrite of sounds.c. Sounds the same, but weighs
; in at 186 bytes less code

; general form from sounds.c:
;   for(j=0; j<repeats; j++) {
;      for(i=0; i<Yreg; i++) {
;         POKEY_WRITE.audf1 = Areg-i*Xreg;
;         jsleep(delay);
;      }
;   }

 .include "atari.inc"

 .import _jsleep
 .export _bad_joss_sound, _good_joss_sound, _under_attack_sound
 .importzp tmp1, tmp2, tmp3, tmp4, sreg

 .ifdef CART_TARGET
  .segment "HIGHCODE"
 .else
  .code
 .endif

initialpitch = sreg
delay = sreg+1
pitch = tmp1
decrement = tmp2
counter = tmp3
repeats = tmp4

; this must agree with newtitle.s
; 0 = enabled, 1 = disabled
sound_disabled = $cb

_under_attack_sound:
; C version was:
;   for(j=0; j<3; j++) {
;      for(i=0; i<3; i++) {
;         POKEY_WRITE.audf1 = 20-i*3;
;         jsleep(3);
;      }
;   }
 lda #$03
 sta delay
 sta repeats
 tax
 tay
 lda #$14
; fall through to make_sound

; call make_sound with:
; A = initial pitch
; X = decrement amount per frame
; Y = inner loop count (i)
; repeats = outer loop count (j)
; delay = jiffies to delay per inner loop
make_sound:
 sta initialpitch
 stx decrement
 sty counter

 ; if sound is disabled, don't play it at all.
 lda sound_disabled
 bne stop_sound

 ; init sound
 lda #0
 sta AUDCTL
 lda #3
 sta SKCTL
 lda #$AA ; pure tone, volume 10
 sta AUDC1

@repeatloop:
 ldy counter
 lda initialpitch
 sta pitch
@noteloop:
 lda pitch
 sta AUDF1
 sec
 sbc decrement
 sta pitch
 ldx #0
 lda delay
 jsr _jsleep

 ; if user pressed a key, abort the sound entirely.
 ; disabled for now.
 ;lda CH
 ;cmp #$FF
 ;bne stop_sound

 dey
 bne @noteloop
 dec repeats
 bne @repeatloop

stop_sound:
 lda #0
 sta AUDC1
 rts

_bad_joss_sound:
; C version was:
;   for(i=0; i<10; i++) {
;      POKEY_WRITE.audf1 = 80-i*8;
;      jsleep(1);
;   }
; which writes 80 72 64 56 48 40 32 24 16 8 to AUDF1
 lda #$01
 sta repeats
 sta delay
 lda #$50
 ldx #$08
 ldy #$0a
 bne make_sound

_good_joss_sound:
; C version was:
;   for(j=0; j<3; j++) {
;      for(i=0; i<4; i++) {
;         POKEY_WRITE.audf1 = 20-i*5;
;         jsleep(2);
;      }
;   }
; which writes 20 15 10 5 to AUDF1, 3 times
 lda #$03
 sta repeats
 lda #$02
 sta delay
 lda #$14
 ldx #$05
 ldy #$04
 bne make_sound

