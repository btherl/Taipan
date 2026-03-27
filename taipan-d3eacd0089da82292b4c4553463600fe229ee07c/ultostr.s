;
; Modified from cc65's libsrc/common/ltoa.s
; Originally by Ullrich von Bassewitz, 11.06.1998

; modified version by B. Watson

; - rename ultoa => ultostr
; - got rid of ltoa (don't need it)
; - hardcode radix to 10
; - don't need __hextab since we don't do hex (saves 16 bytes)
; - inline dopop subroutine

; char* ultostr (unsigned long value, char* s);

        .export         _ultostr
        .import         popax
        .importzp       sreg, ptr1, ptr2, ptr3

radix = 10

 .ifdef CART_TARGET
  .segment "HIGHCODE"
 .else
  .code
 .endif

_ultostr:
        ; pop the arguments
        sta     ptr1
        stx     ptr1+1
        sta     sreg            ; save for return
        stx     sreg+1
        jsr     popax           ; get low word of value
        sta     ptr2
        stx     ptr2+1
        jsr     popax           ; get high word of value
        sta     ptr3
        stx     ptr3+1

; Convert to string by dividing and push the result onto the stack

ultostr:  lda     #$00
        pha                     ; sentinel

; Divide val/radix -> val, remainder in a

L5:     ldy     #32             ; 32 bit
        lda     #0              ; remainder
L6:     asl     ptr2
        rol     ptr2+1
        rol     ptr3
        rol     ptr3+1
        rol     a
        cmp     #radix
        bcc     L7
        sbc     #radix
        inc     ptr2
L7:     dey
        bne     L6

        ora #'0'                ; get ascii character
        pha                     ; save char value on stack

        lda     ptr2
        ora     ptr2+1
        ora     ptr3
        ora     ptr3+1
        bne     L5

; Get the characters from the stack into the string

        ldy     #0
L9:     pla
        sta     (ptr1),y
        beq     L10             ; jump if sentinel
        iny
        bne     L9              ; jump always

; Done! Return the target string

L10:    lda     sreg
        ldx     sreg+1
        rts
