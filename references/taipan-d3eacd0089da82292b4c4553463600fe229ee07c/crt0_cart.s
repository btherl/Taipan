;
; Startup code for cc65 (ATARI version)
;
; Contributing authors:
;       Mark Keates
;       Freddy Offenga
;       Christian Groessler
;       Stefan Haubenthal
;

; Modified for use with Taipan cartridge image:
; - Removed the RTS at the start of the code
; - Got rid of __ATARIXL__ conditionals
; - Don't save stuff like APPMHI and LMARGN, since the cart
;   never returns.

        .export         __STARTUP__ : absolute = 1      ; Mark as startup
        .export         _exit, start

        .import         initlib, donelib
        .import         callmain, zerobss
        .import         __RESERVED_MEMORY__
        .import         __RAM_START__, __RAM_SIZE__
        .include        "zeropage.inc"
        .include        "atari.inc"

; ------------------------------------------------------------------------

.segment        "STARTUP"

; Real entry point:

start:

; Clear the BSS data.

        jsr     zerobss

; Setup arg stack
        lda MEMTOP
        sta sp
        lda MEMTOP+1
        sta sp+1

; Call the module constructors.

        jsr     initlib

; Set the left margin to 0.

        ldy     #0
        sty     LMARGN

; Set the keyboard to upper-/lower-case mode.

        ldx     SHFLOK
        sty     SHFLOK

; Push the command-line arguments; and, call main().

        jsr     callmain

; Call the module destructors. This is also the exit() entry.

_exit:  jsr     donelib         ; Run module destructors

; Back to DOS.

        rts

; *** end of main startup code

; ------------------------------------------------------------------------
