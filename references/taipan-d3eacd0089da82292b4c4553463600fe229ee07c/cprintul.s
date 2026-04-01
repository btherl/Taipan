; cprintul.s - print an unsigned long, int, or char

; Modified from cc65's libsrc/common/ltoa.s
; Originally by Ullrich von Bassewitz, 11.06.1998

; modified version by B. Watson

; - print the characters with cputs instead of storing in a buffer
; - rename ultoa => cprintul, change its prototype
; - add cprintuchar and cprintuint wrappers
; - got rid of ltoa (don't need it)
; - hardcode radix to 10
; - don't need __hextab since we don't do hex (saves 16 bytes)
; - get rid of dopop subroutine, since the return type is now
;   void, and we don't take a buffer argument that needs returning.

; void __fastcall__ cprintul(unsigned long value);

        .export         _cprintulong, _cprintuchar, _cprintuint
        .import         popax, _cputc
        .importzp       sreg, ptr2

radix = 10

 .ifdef CART_TARGET
  .segment "HIGHCODE"
 .else
  .code
 .endif

 ; char and int wrappers for cprintulong(). basically these are
 ; the 'casting' code cc65 would emit any time cprintulong() is
 ; called with a char or int argument. it happens often enough in
 ; taipan.c that it's worth doing this way:

 ; cprintulong(1) compiles to 11 bytes:
 ;  ldx #$00
 ;  stx sreg
 ;  stx sreg+1
 ;  lda #$01
 ;  jsr _cprintulong

 ; whereas cprintuchar(1) is 5 bytes (saves 6):
 ;  lda #$01
 ;  jsr _cprintuchar

 ; cprintuint(1) is 7 bytes (saves 4, add 'ldx #$00' to the above).

 ; the wrappers are 10 bytes together. so long as we remember to *use*
 ; them, we only have to use cprintuchar() 2 times and/or cprintuint()
 ; 3 times to start saving bytes.

_cprintuchar:
 ldx #0
_cprintuint:
 pha
 lda #0
 sta sreg
 sta sreg+1
 pla

 ; main routine
_cprintulong:
        ; high word passed to us in sreg
        ; low word in ptr2
        sta     ptr2
        stx     ptr2+1

; Convert to string by dividing and push the result onto the stack

        lda     #$00
        pha                     ; sentinel

; Divide val/radix -> val, remainder in a

L5:     ldy     #32             ; 32 bit
        lda     #0              ; remainder
L6:     asl     ptr2
        rol     ptr2+1
        rol     sreg
        rol     sreg+1
        rol     a
        cmp     #radix
        bcc     L7
        sbc     #radix
        inc     ptr2
L7:     dey
        bne     L6

        ora     #'0'            ; get ascii character
        pha                     ; save char value on stack

        lda     ptr2
        ora     ptr2+1
        ora     sreg
        ora     sreg+1
        bne     L5

; Get the characters from the stack, print them.

@print: pla
        beq @done               ; exit if sentinel
        pha
		  jsr _cputc
		  pla
        bne     @print          ; branch always

@done:
        rts
