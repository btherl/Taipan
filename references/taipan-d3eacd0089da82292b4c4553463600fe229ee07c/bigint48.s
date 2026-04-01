
; 48-bit integer bignum implementation for taipan.
; the Atari 800/XL/XE build doesn't use this, it's only for
; the 5200 (though the A8 build can be tested with it).

; .include "atari.inc" ; don't include atari.inc on the 5200,
                       ; I'll get confused even if ca65 doesn't.
 FR0 = $d4 ; this is the only label we need from atari.inc. on
           ; the 5200, $d4 and up are free zero page.

 .export _big_copy, _ulong_to_big, _big_cmp, _big_to_ulong, _big_add, _big_sub, _big_negate
 .export _big_div, _big_mul
 .import popax, pushax
 .importzp ptr1, ptr2, ptr3, tmp1

 ; used by _big_div
 numerator = FR0
 denominator = FR0+6
 result = FR0+12
 quotient = FR0+18
 halfnum = FR0+24
 newdenom = FR0+30
 ;sign = FR0+36

 ; used by _big_mul
 multiplicand = FR0
 multiplier = FR0+6
 ;result = FR0+12 ; same as above

 start = *

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; extern char __cdecl__ big_mul(bignump dest, bignump multiplicand, bignump multiplier);
; basically, init result to 0, shift the multiplicand right, add the multiplier
; to the result if a 1 shifted out. Then shift the multiplier left, repeat.
; 1010 x 0101 (10 times 5):
; result = 0;
; 0101 >> 1, shifted out a 1, so result += 1010, then shift the 1010 left to get 10100.
; 010 >> 1, shifted out a 0, so result stays same, then shift the 10100 left to get 101000
; 01 >> 1, shifted out a 1, so result += 101000, then shift the 101000 left to get 1010000
; 0 >> 1, shifted out a 0, result stays same.
; result ends up 1010 + 101000 or 50.
; the only PITA here is extending out to 48 bits. No overflow detection,
; hey, C doesn't detect int overflows either so why should I worry?
_big_mul:
 jsr popax
 sta ptr1
 stx ptr1+1
 jsr popax
 sta ptr2
 stx ptr2+1

 ldy #5
@p1lp:
 lda (ptr1),y
 sta multiplier,y
 lda (ptr2),y
 sta multiplicand,y
 lda #0
 sta result,y
 dey
 bpl @p1lp

 ldy #48 ; bit count
@shiftlp:
 ; for each bit, shift the multiplicand right...
 lsr multiplicand+5
 ror multiplicand+4
 ror multiplicand+3
 ror multiplicand+2
 ror multiplicand+1
 ror multiplicand
 bcc @dont_add ; if we shifted out a 0, don't add multiplier

 ; if we shifted out a 1, add the multiplier.
 clc
 lda multiplier
 adc result
 sta result
 lda multiplier+1
 adc result+1
 sta result+1
 lda multiplier+2
 adc result+2
 sta result+2
 lda multiplier+3
 adc result+3
 sta result+3
 lda multiplier+4
 adc result+4
 sta result+4
 lda multiplier+5
 adc result+5
 sta result+5

 ; unconditionally shift the multiplier left
@dont_add:
 asl multiplier
 rol multiplier+1
 rol multiplier+2
 rol multiplier+3
 rol multiplier+4
 rol multiplier+5

 ; are we done?
 dey
 bne @shiftlp ; no, do next bit

 jmp mul_div_done ; yes, store result.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; extern char __cdecl__ big_div(bignump dest, bignump dividend, bignump divisor);
; dividend and divisor AKA numerator and denominator.
; this eats a ton of zero page, but we can afford it.

; wrote this in C and translated to asm by hand. The C is very asm-like,
; and would make your professor cry (or curse). The resulting asm is
; a bloated mess, but still smaller than if I'd compiled the C code
; with cc65. There's lots of room for improvement.

;;int divide(int num, int denom) {
;;   int result, quotient, newdenom, halfnum;

_big_div:
 jsr popax ; get dividend (denominator)
 sta ptr1
 stx ptr1+1
 jsr popax ; get divisor (numerator)
 sta ptr2
 stx ptr2+1
 ; leave dest argument on the stack.

;;   result = 0;
 ldy #5 ; copy values to ZP
@bdcp:
 lda (ptr1),y
 sta denominator,y
 lda (ptr2),y
 sta numerator,y
 lda #0
 sta result,y
 dey
 bpl @bdcp
 ; at this point we are done with ptr1 and ptr2, so we don't
 ; have to save them before calling our other functions.

 ; don't need this.
;;  ; deal with signs.
;;  ;lda #0 ; A already 0 from loop above
;;  sta sign
;;  ldx #denominator
;;  jsr fixsign
;;  ldx #numerator
;;  jsr fixsign

;;outerloop:
;;   newdenom = denom;
@outerloop:
 ldx #5
@copy_and_zero:
 lda denominator,x
 sta newdenom,x
 lda #0
 sta quotient,x
 dex
 bpl @copy_and_zero

;;   quotient = 1;
 inc quotient ; other bytes were zeroed in loop above.

;;   if(newdenom < num)
;;      goto checkequal;
 lda #newdenom
 ldx #0
 jsr pushax
 lda #numerator
 ldx #0
 jsr _big_cmp ; Z flag for equal, N=1 less, N=0 greater
;;   if(newdenom < num)
;;      goto innerprep;
 bmi @innerprep
;;   if(newdenom == num)
;;      goto innerprep;
 beq @innerprep

;;   quotient = 0;
;;   num = 0;
;;   goto addquot;
 lda #0
 sta quotient
 sta numerator
 sta numerator+1
 sta numerator+2
 sta numerator+3
 sta numerator+4
 sta numerator+5
 beq @addquot

;;innerprep:
;;   halfnum = num >> 1;
@innerprep:
 lda numerator+5
 lsr
 sta halfnum+5
 lda numerator+4
 ror
 sta halfnum+4
 lda numerator+3
 ror
 sta halfnum+3
 lda numerator+2
 ror
 sta halfnum+2
 lda numerator+1
 ror
 sta halfnum+1
 lda numerator
 ror
 sta halfnum

;;innerloop:
;;   if(newdenom > halfnum)
;;      goto innerdone;
@innerloop:
 lda #newdenom
 ldx #0
 jsr pushax
 lda #halfnum
 ldx #0
 jsr _big_cmp
 beq @notgt
 bmi @notgt
 bpl @innerdone
@notgt:

;;   newdenom <<= 1;
 asl newdenom
 rol newdenom+1
 rol newdenom+2
 rol newdenom+3
 rol newdenom+4
 rol newdenom+5

;;   quotient <<= 1;
 asl quotient
 rol quotient+1
 rol quotient+2
 rol quotient+3
 rol quotient+4
 rol quotient+5

;;   goto innerloop;
 jmp @innerloop

;;innerdone:
;;   num -= newdenom;
@innerdone:
 lda #numerator
 ldx #0
 jsr pushax
 lda #numerator
 ldx #0
 jsr pushax
 lda #newdenom
 ldx #0
 jsr pushax
 jsr _big_sub

;;addquot:
;;   result += quotient;
@addquot:
 lda #result
 ldx #0
 jsr pushax
 lda #result
 ldx #0
 jsr pushax
 lda #quotient
 ldx #0
 jsr pushax
 jsr _big_add

;;   if(num) goto outerloop;
 lda numerator
 ora numerator+1
 ora numerator+2
 ora numerator+3
 ora numerator+4
 ora numerator+5
 beq mul_div_done
 jmp @outerloop ; too far for relative branch

;;   return result;
mul_div_done:
; destination is still on the stack.
 jsr popax
 sta ptr1
 stx ptr1+1
 ldy #5
@doneloop:
 lda result,y
 sta (ptr1),y
 dey
 bpl @doneloop

 rts

;;}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; extern void __fastcall__ big_copy(bignump dest, bignump src);
_big_copy:
 sta ptr1
 stx ptr1+1
 jsr popax
 sta ptr2
 stx ptr2+1
 ldy #5
@bclp:
 lda (ptr1),y
 sta (ptr2),y
 dey
 bpl @bclp
 rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; extern void __fastcall__ ulong_to_big(const unsigned long l, bignump b);
_ulong_to_big:
 ; ptr1 = b
 sta ptr1
 stx ptr1+1

 ; zero out top 16 bits of b
 ldy #4
 lda #0
 sta (ptr1),y 
 iny
 sta (ptr1),y

 ; copy bottom 16 bits of l to bottom 16 bits of b
 jsr popax
 ldy #0    ; popax eats the Y reg
 sta (ptr1),y
 iny
 txa       ; sadly there's no stx (zp),y on the 6502
 sta (ptr1),y

 ; copy top 16 bits of l to middle 16 bits of b
 jsr popax
 ldy #2
 sta (ptr1),y
 iny
 txa
 sta (ptr1),y
 rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; TODO: consolidate with big_copy(), they're almost identical.
; extern char __fastcall__ big_to_ulong(bignump b, unsigned long *l);
_big_to_ulong:
 sta ptr2
 stx ptr2+1
 jsr popax
 sta ptr1
 stx ptr1+1
 ldy #3
@bclp:
 lda (ptr1),y
 sta (ptr2),y
 dey
 bpl @bclp
 rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; extern signed char __fastcall__ big_cmp(bignump a, bignump b);
_big_cmp:
 sta ptr2     ; ptr2 = b;
 stx ptr2+1
 jsr popax
 sta ptr1     ; ptr1 = a;
 stx ptr1+1

 ; since this is a signed compare, we'll check the sign bits first.
 ; if a is negative and b isn't, or vice versa, we shortcut the rest
 ; of the compare.
 ldy #5       ; point at the MSB
 lda (ptr1),y ; get MSB of a
 bpl @a_pos
 lda (ptr2),y ; a is negative, is b?
 bmi @cmplp   ; yep, do a normal compare
 bpl @return_neg ; no, return negative result

@a_pos:
 lda (ptr2),y ; a is positive, is b?
 bmi @return_pos ; no, return positive result
              ; yes, fall thru and do a normal compare

 ; Y is still 5 no matter how we got here.
@cmplp:
 sec
 lda (ptr1),y
 sbc (ptr2),y ; A = a[Y] - b[Y];
 bne @unequal ; if non-zero subtraction result, go check carry
 dey          ; else got zero, keep comparing
 bpl @cmplp   ; more bytes to check?
 bmi @return_a ; no. note: A still zero here
@unequal:
 bcs @return_pos
@return_neg:
 lda #$ff     ; negative result, return -1
 .byte $2c    ; skip next 2 bytes
@return_pos:
 lda #$01     ; positive result, return 1 (actually $0101)
@return_a:
 tax ; sign-extend, the optimizer gets wonky about char vs int returns
 rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; extern void __fastcall__ big_negate(bignump b);
; 2's complement negation: invert all the bits, then add 1
; TODO: this should be smaller.
_big_negate:
 sta ptr1
 stx ptr1+1

 ldy #0
@invloop:
 lda (ptr1),y
 eor #$ff
 sta (ptr1),y
 iny
 cpy #6
 bne @invloop

 ldy #0
 sec
 php
@addloop:
 plp
 lda (ptr1),y 
 adc #0
 php
 sta (ptr1),y
 iny
 cpy #6
 bne @addloop

 plp
 rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; extern char __cdecl__ big_add(bignump dest, bignump addend1, bignump addend2);
; extern char __cdecl__ big_sub(bignump dest, bignump minuend, bignump subtrahend);
; addition and subtraction are almost identical, so the code here does both.
; TODO: this is not as compact as it could be.
_big_sub:
 lda #$80
 .byte $2c
_big_add:
 lda #0
 sta tmp1 ; tmp1 is negative if subtracting, positive if adding

 jsr popax ; addend2 or subtrahend
 sta ptr2
 stx ptr2+1
 jsr popax ; addend1 or minuend
 sta ptr1
 stx ptr1+1
 jsr popax ; dest
 sta ptr3
 stx ptr3+1

 ldy #0

 bit tmp1
 bmi @setc ; set carry if subtracting...
 clc       ; otherwise clear it
 .byte $24 ; bit ZP, skip only 1 byte
@setc:
 sec

 php ; we have to keep the C flag on the stack since the cpy below trashes it
@addlp:
 plp
 lda (ptr1),y
 bit tmp1
 bmi @sub
 adc (ptr2),y
 .byte $2c

@sub:
 sbc (ptr2),y

@store:
 sta (ptr3),y
 php
 iny
 cpy #6
 bne @addlp
 plp
 rts

 .out .sprintf("bigint48 code is %d bytes", *-start)

; was going to be a helper routine for big_mul and big_div, but
; taipan doesn't need signed multiply/divide.
;; fixsign:
;;  lda 0+5,x
;;  bpl @pos
;;  lda #$80
;;  eor sign
;;  sta sign
;;  txa
;;  ldx #0
;;  jsr _big_negate
;; @pos:
;;  rts

