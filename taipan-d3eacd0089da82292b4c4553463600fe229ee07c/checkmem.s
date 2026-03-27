; As of 3cbd137, the xex build will run in 40K. This stuff no longer
; checks for 48K or tries to disable the BASIC cart. With 40K free, we
; get 360 bytes for the stack, which is less than the linker config's
; 512 byte stack... but we never use anywhere near the full amount.

; We still do a GR.0 here, because the taipan.c code expects it to
; have been set up, and because some loaders (e.g. fenders) don't
; do it for us.

; Memcheck needs to do this:

;1. Do a GRAPHICS 0
;2. If RAMTOP >=$A0, go to step 6
;3. Print "need 40K" message
;4. Wait for a keypress
;5. Exit to DOS (without loading the rest of the file)
;6. Exit via RTS, so the rest of the game will load.

;At no point do we look at RAMSIZ, since it can't be trusted under SDX.

;Note that when we reach step 6, RAMTOP is always $C0 (either it was,
;or we set it to that).

; cl65 -o checkmem.xex -t none checkmem.s

 .include "atari.inc"
 .macpack atari

start = $0600 ; use page 6 for now

; homebrew XEX header
 .word $ffff
 .word start
 .word end-1

 .org start

msg:
 scrcode "Need at least 40K"
msglen = * - msg - 1

S: .byte "S:",0

init:
;1. Do a GRAPHICS 0
 jsr gr_0

;2. If RAMTOP is >=$A0, go to step 5.
 lda RAMTOP
 cmp #$a0
 bcc memerr

;5. Exit via RTS, so the rest of the game will load.
 rts

;3. Print a "need 40K" message
memerr:
 lda #<msg
 sta FR0
 lda #>msg
 sta FR0+1

 ldy #msglen
msgloop:
 lda (FR0),y
 sta (SAVMSC),y
 dey
 bpl msgloop

;4. Wait for a keypress
 sty CH ; y == $ff at this point, clear keyboard
 ; ...wait for a keystroke...
wait4key:
 cpy CH
 beq wait4key
 sty CH ; clear the key so DOS menu won't see it.

;5. Exit to DOS (without loading the rest of the file)
 jmp (DOSVEC)

gr_0:
 ldx #6*$10 ; CLOSE #6
 lda #CLOSE
 sta ICCOM,x
 jsr CIOV

 ; GRAPHICS 0
 ldx #6*$10 ; IOCB #6
 lda #OPEN
 sta ICCOM,x
 lda #$1c ; $c = read/write
 sta ICAX1,x
 lda #0   ; aux2 byte zero
 sta ICAX2,x
 lda #<S
 sta ICBAL,x
 lda #>S
 sta ICBAH,x
 jsr CIOV

 ; save display list pointer where taipan.c's main() can find it.
 ; this is done ASAP after the CIO call, to avoid saving the DL
 ; after SpartaDOS's TDLINE has had a chance to modify it.
 ; we use FRE because the menu code in newtitle.s trashes FR0 and FR1.
 lda SDLSTL
 sta FRE
 lda SDLSTH
 sta FRE+1

 rts

end:
 .word INITAD
 .word INITAD+1
 .word init
