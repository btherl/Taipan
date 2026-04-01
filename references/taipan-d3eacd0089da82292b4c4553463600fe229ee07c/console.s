

 .include "atari.inc"
 .include "conio/mul40.s"

 .export _clrtobot, _clrtoeol, _clr_screen, _clrtoline
 .export _cblank, _cblankto, _backspace, _cprint_pipe
 .export _cprint_bang, _cspace, _cputc_s, _comma_space
 .export _cprint_colon_space, _cprint_question_space
 .export _cprint_period, _cprint_taipan_prompt, _plus_or_space
 .export _gotox0y22, _gotox0y3, _gotox0y, _gotox0y3_clrtoeol
 .export _cputc0, _set_orders, _pluralize, _print_combat_msg
 .export _rvs_on, _rvs_off
 .export _prepare_report, _clear_msg_window
 .export _print_status_desc, _print_month
 .export _revflag

 .importzp tmp3
 .import bump_destptr ; these two are
 .importzp destptr    ; from draw_lorcha.s
 .importzp sreg
 .import _cprintulong, _cputc, _cprint_taipan, _timed_getch, _orders
 .import _turbo
 .import _print_msg, _cspaces
 .import _st, _month, _cputs
 .import _cprintuint

 .ifdef CART_TARGET
  .segment "HIGHCODE"
 .else
  .code
 .endif


; void clr_screen(void);
; void clrtobot(void);
; void clrtoeol(void);
; void clrtoline(unsigned char line);

; this stuff doesn't disturb conio's (and the OS's) idea of the
; current cursor position. It's *way* faster than writing them in
; C in terms of cclear() (which uses one cputc() call per blank).

_clr_screen: ; same as gotoxy(0,0); clrtobot();
 lda #0
 sta ROWCRS
 sta COLCRS

_clrtobot: ; same as clrtoline(24);
 lda #24
 ;bne _clrtoline ; we'd have had to do this if ROWCRS weren't zero-page.
 .byte $2c ; see bit trick explanation below, if you don't recognize this.

_clrtoeol:
 lda ROWCRS
 ; fall through to _clrtoline

_clrtoline:
 sta tmp3 ; stash our arg

 ;lda #0
 ;sta OLDCHR ; stop conio from redrawing stuff after we clear it,
             ; no longer needed with our custom conio.

 ; setup destptr to start of current line, NOT
 ; current cursor position.
 lda ROWCRS
 jsr mul40  ; AX = A*40 (addr of start-of-row)
 clc
 adc SAVMSC ; add AX to screen pointer
 sta destptr
 txa
 adc SAVMSC+1
 sta destptr+1

 ; X = current row, Y = current column. Stop clearing a line when Y == 40,
 ; we're done when X == 24. Apologies, the names X and Y are backwards
 ; compared to proper Cartesian coordinates.
 ldx ROWCRS
 ldy COLCRS
 lda #0

clrloop:
 sta (destptr),y ; blank a character (A == 0, screen code for a space)
 iny
 cpy #40
 bne clrloop
 ldy #0
 inx
 cpx tmp3
 bcs done

 jsr bump_destptr
 lda #0
 tay
 beq clrloop

done:
 rts

_cblankto:
 sec
 sbc COLCRS
 beq done
 bcs _cblank
 rts

_backspace:
 dec COLCRS
 lda #1
 ; fall through to _cblank

_cblank:
 tax
 lda COLCRS
 pha
 lda ROWCRS
 pha
 txa
 jsr _cspaces
 pla
 sta ROWCRS
 pla
 sta COLCRS
 rts

_rvs_on:
 lda #$80
 .byte $2c ; BIT absolute opcode
_rvs_off:
 lda #0
 sta _revflag
 rts

 ; micro-optimizations here.
 ; the stuff below might be a bit hard to follow, but it saves code.
 ; calling this: cputs("? ");
 ; emits code like this:
 ;  lda #<Lxxx
 ;  ldx #>Lxxx
 ;  jsr _cputs
 ; ...which is 9 bytes per call (plus 3 bytes for the "? " string itself).
 ; replacing each cputs("? "); with cprint_question_space() means 3 bytes
 ; per call (a JSR). there are 3 'some char followed by a space' routines
 ; here, totalling 10 bytes. the actual space is printed by code shared
 ; with cspace().
 ; also, there are 5 'print a single character' routines. each one would
 ; normally be cputc('X'), which compiles to:
 ;  lda #'X'
 ;  jsr _cputc
 ; ...or 5 bytes each. we have 5 of them, so 25 bytes. using fall-thru
 ; and the BIT trick, they condense down to 17 bytes.
 ; if you're not familiar with the "BIT trick" to skip a 2-byte instruction,
 ; the stuff below looks like gibberish... here's a mini-tutorial:

 ;store1:
 ; lda #1
 ; .byte $2c ; this is the opcode for BIT absolute
 ;store2:
 ; lda #2
 ; sta $0600
 ; rts

 ; if entered via "jsr store1", the above code fragment executes these
 ; instructions:
 ; lda #1
 ; bit $02A9 ; $A9 is the LDA immediate opcode, 02 is the #2
 ; sta $0600
 ; rts

 ; if entered via "jsr store2", it's
 ; lda #2
 ; sta $0600
 ; rts

 ; the "bit $02a9' doesn't affect any registers other than the flags,
 ; and the "sta $0600 : rts" part doesn't depend on any of the flags,
 ; so the BIT is effectively a no-op that "masks" the 2-byte LDA #2
 ; instruction "hidden" as its operand.

 ; ", Taipan? "
 ; using fall-thru here saves 3 bytes (normally the last instruction
 ; would be "jmp _cprint_question_space")
_cprint_taipan_prompt:
 jsr _comma_space
 jsr _cprint_taipan
 ; fall thru

 ; each entry point here prints one character followed by a space
 ; "? "
_cprint_question_space:
 lda #'?'
 .byte $2c

 ; ": "
_cprint_colon_space:
 lda #':'
 .byte $2c

 ; ", "
_comma_space:
 lda #','
 jsr _cputc
 ; fall thru

 ; each entry point here prints one character
_cspace:
 lda #' '
 .byte $2c
_cputc0:
 lda #'0'
 .byte $2c
_cprint_pipe:
 lda #'|'
 .byte $2c
_cputc_s:
 lda #'s'
 .byte $2c
_cprint_period:
 lda #'.'
 .byte $2c
_cprint_bang:
 lda #'!'
 jmp _cputc

; extern void plus_or_space(unsigned char b);
_plus_or_space:
 tax
 beq @spc
 lda #'+' + 128 ; inverse plus
 .byte $2c
@spc:
 lda #' '
 ldx #39
 stx COLCRS
 ldx #15
 stx ROWCRS
 jmp _cputc

; extern void gotox0y22(void);
_gotox0y22:
 lda #22
 .byte $2c

; extern void gotox0y3(void);
_gotox0y3:
 lda #3

; extern void gotox0y(char y);
_gotox0y:
 sta ROWCRS
 lda #0
 sta COLCRS
 rts

; extern void gotox0y3_clrtoeol(void);
_gotox0y3_clrtoeol:
 jsr _gotox0y3
 jmp _clrtoeol

; extern void print_combat_msg(const char *);
_print_combat_msg:
 pha
 jsr _gotox0y3
 pla
 jsr _print_msg
 jmp _clrtoeol

; extern void clear_msg_window(void)
; extern void prepare_report(void)
_clear_msg_window:
 lda #$12
 .byte $2c
_prepare_report:
 lda #$10
 jsr _gotox0y
 jmp _clrtobot

; extern void __fastcall__ pluralize(int num);
_pluralize:
 cmp #1
 bne _cputc_s
 txa
 bne _cputc_s
 rts

; extern void __fastcall__ _print_status_desc(char status);
; replaces this C code:
; cputs(st[status / 20]);
; status ranges 0 to 100 (it's the seaworthiness percentage),
; the st[] array has elements 0 to 5. 5 is "Perfect" and only
; used when status == 100.
_print_status_desc:
 lsr ;        arg /= 2; // was 0..100, now 0..50
 ldy #$fe ;   y = -2;
 sec
@div10loop: ; do {
 iny
 iny ;              y += 2;
 sbc #$0a ;         arg -= 10;
 bcs @div10loop ; } while(arg >= 0);
 ; y is now (arg / 20) * 2, one of: 0 2 4 6 8 10
 ; which is exactly what we need to index an array of six
 ; 16-bit pointers.
 lda _st,y
 ldx _st+1,y
 jmp _cputs

; extern void __fastcall__ print_month(void);
; _month is a global, ranges 1 to 12.

_print_month:
 lda _month
 asl
 asl ; carry will be left clear
 adc #<(months-4)
 pha
 lda #>(months-4)
 adc #0
 tax
 pla
 jmp _cputs

; extern void set_orders(void);
_set_orders:
 lda _turbo   ; in turbo fight mode?
 beq @sowait  ; no, so wait like usual
 lda CH       ; turbo = yes, did user hit a key?
 cmp #$ff
 bne @sowait  ; yes, wait like usual
 rts
@sowait:
 lda #0
 sta _turbo
 jsr _timed_getch
 cmp #$60      ; capital letter?
 bcs @sonoturbo ; nope, disable turbo
@soturbo:
 ora #$20     ; convert to lowercase
 sta _turbo   ; enable turbo
 ;;; sta COLOR4 ; for debugging
@sonoturbo:
 ldx #3
@solp:
 cmp orders_tbl-1,x
 beq @returnx
 dex
 bne @solp
 stx _turbo ; invalid order, disable turbo
 rts
@returnx:
 stx _orders
done1:
 rts

; extern void __fastcall__ print_score_msg(long score)

; asm replacement for this C code:

;   /* score is a *signed* long. */
;   if(score < 0)
;      print_msg(M_stay_on_shore);
;   else if(score < 100)
;      print_msg(M_land_based_job);

 .import _M_stay_on_shore, _M_land_based_job
 .export _print_score_msg
_print_score_msg:
 sta FR0
 lda sreg+1              ; is MSB sign bit set?
 bpl @notneg
 lda #<_M_stay_on_shore  ; if so, print this message
 ldx #>_M_stay_on_shore
@pm:
 jmp _print_msg
@notneg:                 ; else MSB is positive. Is it non-zero?
 bne done1               ; if non-zero, score is at least 2^24+1, no message
 txa                     ; check bits 8-15...
 ora sreg                ; ...and 16-23
 bne done1               ; if either middle byte is non-zero, score>=256, no message
 lda FR0                 ; here, the top 3 bytes are zero, so check the LSB.
 cmp #99                 ; is it < 100?
 bcs done1               ; if not, no message. or,
 lda #<_M_land_based_job ; if so, print this message
 ldx #>_M_land_based_job
 bne @pm                 ; branch always (since message is not in zero page)

;; .import _guns
;; .export _gun_or_guns
;;_gun_or_guns:
;; lda _guns+1
;; bne @s
;; lda _guns
;; cmp #1
;; bne @s
;; lda #' '
;; .byte $2c
;;@s:
;; lda #'s'
;; jmp _cputc

 .rodata
orders_tbl: .byte "frt"

; inverse "Jan\0Feb\0Mar\0Apr\0May\0Jun\0Jul\0Aug\0Sep\0Oct\0Nov\0Dec\0"
months:
 .byte $ca, $e1, $ee, $00
 .byte $c6, $e5, $e2, $00
 .byte $cd, $e1, $f2, $00
 .byte $c1, $f0, $f2, $00
 .byte $cd, $e1, $f9, $00
 .byte $ca, $f5, $ee, $00
 .byte $ca, $f5, $ec, $00
 .byte $c1, $f5, $e7, $00
 .byte $d3, $e5, $f0, $00
 .byte $cf, $e3, $f4, $00
 .byte $ce, $ef, $f6, $00
 .byte $c4, $e5, $e3, $00

 .bss
_revflag: .res 1
