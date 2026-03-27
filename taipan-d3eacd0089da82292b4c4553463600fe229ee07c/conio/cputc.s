; this file modified for use with taipan:
; - \n treated like \r\n used to: moves cursor to
;   start of next line.
; - \r no longer special (prints a graphics character)
; - $0a no longer treated as as \n (prints graphics char)
; - _cputcxy removed as taipan never uses it

;
; Mark Keates, Christian Groessler
;
; void cputcxy (unsigned char x, unsigned char y, char c);
; void cputc (char c);
;

        ;.export         _cputcxy, _cputc
        .export         _cputc, _crlf
        .export         plot, cputdirect, putchar
        .import         popa, _gotoxy
        .importzp       tmp4,ptr4
        .import         _revflag

        .include        "atari.inc"
        .include        "mul40.s"


;_cputcxy:
        ;pha                     ; Save C
        ;jsr     popa            ; Get Y
        ;jsr     _gotoxy         ; Set cursor, drop x
        ;pla                     ; Restore C

_cputc:
;        cmp     #$0D            ; CR
;        bne     L4
;        lda     #0
;        sta     COLCRS
;        beq     plot            ; return

L4:     ;cmp     #$0A            ; LF
        ;beq     newline
        cmp     #ATEOL          ; Atari-EOL?
        beq     newline

        tay
        rol     a
        rol     a
        rol     a
        rol     a
        and     #3
        tax
        tya
        and     #$9f
        ora     ataint,x

cputdirect:                     ; accepts screen code
        jsr     putchar

; advance cursor
        inc     COLCRS
        lda     COLCRS
        cmp     #40
        bcc     plot
        ;lda     #0
        ;sta     COLCRS

        .export newline
_crlf:
newline:
        lda     #0
        sta     COLCRS
        inc     ROWCRS
        lda     ROWCRS
        cmp     #24
        bne     plot
        lda     #0
        sta     ROWCRS
plot:
        ldy     COLCRS
        ldx     ROWCRS
        rts

; update screen
; if called directly, putchar prints the screen code in A
; without updating the cursor position.
putchar:
        pha                     ; save char

        ldy     #0

        lda     ROWCRS
        jsr     mul40           ; destroys tmp4
        clc
        adc     SAVMSC          ; add start of screen memory
        sta     ptr4
        txa
        adc     SAVMSC+1
        sta     ptr4+1
        pla                     ; get char again

        ora     _revflag
        ;sta     OLDCHR

        ldy     COLCRS
        sta     (ptr4),y
        rts

        .rodata
ataint: .byte   64,0,32,96
