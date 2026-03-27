
 .export _timed_getch, _set_jiffy_timer, _agetc, _numgetc
 .export  _yngetc, _lcgetc, _jsleep, _get_item_port, _get_item_battle, _tjsleep
 .import _cgetc, _cblank, putchar, _rand, _turbo

 .include "atari.inc"

 .ifdef CART_TARGET
  .segment "HIGHCODE"
 .else
  .code
 .endif

; keyboard and timer functions for taipan.

; sleep for j jiffies, unless _turbo is set.
; extern void __fastcall__ tjsleep(unsigned int j);
_tjsleep:
 sta FR0+4
 lda _turbo
 bne jret
 lda FR0+4

; sleep for j jiffies.
; extern void __fastcall__ jsleep(unsigned int j);
_jsleep:
 jsr _set_jiffy_timer
jiffy_wait:
 lda CDTMV3
 ora CDTMV3+1
 bne jiffy_wait
jret:
 rts

; extern void __fastcall__ set_jiffy_timer(unsigned int jiffies);
_set_jiffy_timer: ; called by jsleep() also.
 sei          ; disable IRQ while setting timer (probably overkill)
 sta CDTMV3
 stx CDTMV3+1
 cli
 rts

; like curses timeout(5000) followed by getch(): sleep until either
; a key is pressed or the timer expires. returns 0 if no key pressed.
; extern char __fastcall__ timed_getch(void);
_timed_getch:
 lda #$2c ; $012c jiffies = 5 sec (NTSC) or 6 sec (PAL)
 ldx #$01
 jsr _set_jiffy_timer

@wait4key:
 lda CDTMV3   ; has timer counted down to 0?
 ora CDTMV3+1
 bne @timer_running
 tax ; timer expired, return(0), A is already 0 here
 rts

@timer_running:
 lda CH   ; no, check for a keypress
          ; ...but don't let the capslock or inverse keys count
			 ; as a keypress, here.

 cmp #$ff ; no key pressed
 beq @wait4key
 and #$3f ; mask shift/control bits
 cmp #$3c ; caps-lock
 beq @wait4key
 cmp #$27 ; inverse (atari) key
 beq @wait4key

 ; user hit a key, handle it. but don't print a cursor.
 bne _agetc_no_cursor

; _agetc removes the inverse-video bit, and if
; a control key is pressed, it turns it into the non-control version
; (e.g. ^A = lowercase a). Keys that can't be mapped to regular ASCII
; (such as clear, delete, escape) are replaced with a space.
; extern unsigned char agetc(void);
_agetc:
 ; show the user a cursor
 lda #$80 ; inverse space (putchar uses screen codes)
 jsr putchar

_agetc_no_cursor:
 jsr _cgetc ; get ATASCII code of keypress
 pha

 ; get rid of the cursor
 lda #$00 ; space
 jsr putchar
 pla

finish_agetc:
 pha
 ; twitch the random bottle based on the low bit of
 ; the character entered.
 and #$01
 beq @nr
 jsr _rand
@nr:
 pla

 .ifdef GAME_HELP
   .import _print_game_help
 cmp #'?'
 bne notquestion
 jmp _print_game_help
notquestion:
 .endif

 ; special cases
 cmp #$9b   ; enter key, return as-is
 beq ok
 cmp #$9c   ; delete key, return as-is
 beq ok
 cmp #$7e   ; backspace
 beq ok

 ; everything else
 and #$7f   ; strip bit 7 (inverse)
 bne notnull
 lda #$20   ; map null (heart, ctrl-,) to space
notnull:
 cmp #$20
 bcs notcontrol
 ora #$60   ; 1 - 31 map to 96 - 127
notcontrol:
 cmp #$7c ; | (pipe, vertical bar) allowed as-is.
 beq ok
 cmp #$7b ; rest of range $7b - $7f is unmappable.
 bcc ok   ; (remember, $7e, backspace, was handled above)
 lda #$20
ok:
; pha
; ldx #0
; lda FR1+2
; jsr _cursor
; pla
 ldx #0
 rts

; extern unsigned char lcgetc(void);
_lcgetc:
 jsr _agetc
 cmp #'A'
 bcc ok
 cmp #'Z'+1
 bcs ok
 eor #$20   ; lowercase it
 bcc ok

; extern unsigned char numgetc(void);
_numgetc:
 jsr _agetc
 cmp #$9b
 beq ok
 cmp #$7e   ; backspace
 beq ok
 cmp #$61   ; allow 'a' for "all"
 beq ok
 cmp #$6b   ; allow 'k' for 1000
 beq ok
 cmp #$6d   ; allow 'm' for 1 million
 beq ok
 cmp #$9c   ; shift-del
 beq ok
 cmp #'0'
 bcc _numgetc
 cmp #'9'+1
 bcc ok
 bcs _numgetc

; extern unsigned char __fastcall__ yngetc(char dflt);
_yngetc:
 sta FR0 ; stash default arg
 ora #$80 ; show user the default (or a regular cursor if none)
 and #$bf ; (uppercase)
 jsr putchar
 jsr _agetc_no_cursor
 ora #$20 ; lowercase
 cmp #'y'  ; return y or n immediately
 beq ok
 cmp #'n'
 beq ok
 lda FR0     ; otherwise, check for default arg
 beq _yngetc ; no default, get another keypress
 rts         ; else return the default

; extern unsigned char get_item_port(void)
; return 0-3 for opium, silk, arms, general.
; return 5 for Enter key (nothing chosen)
_get_item_port:
 lda #4
 .byte $2c

; extern unsigned char get_item_battle(void)
; return 0-4 for opium, silk, arms, general, all.
_get_item_battle:
 lda #5
 sta FR0
@get_loop:
 jsr get_item
 cmp FR0
 beq @get_loop
 rts


get_item:
@getkey:
 jsr _lcgetc ; switch(lcgetc()) {
 sta FR0+1

;;; ldx #0
;;; cmp #'o'
;;; beq @gi_done ; case 'o': return 0;
;;; inx
;;; cmp #'s'
;;; beq @gi_done ; case 's': return 1;
;;; inx
;;; cmp #'a'
;;; beq @gi_done ; case 'a': return 2;
;;; inx
;;; cmp #'g'
;;; beq @gi_done ; case 'g': return 3;

 ldx #5
@giloop:
 lda items_tbl,x
 cmp FR0+1
 beq @gi_done
 dex
 bpl @giloop
 bmi @getkey
@gi_done:
 txa
 rts

.rodata
 items_tbl: .byte "osag*",$9b
