;
; Startup code for cc65 (Atari5200 version)
;
; Christian Groessler (chris@groessler.org), 2014

; modified for taipan, to work as a diagnostic cart.
; contains code adapted from the 5200 OS ROM.

        .export         _exit, start
        .export         __STARTUP__ : absolute = 1      ; Mark as startup
        .import         __RAM_START__, __RAM_SIZE__
        .import         __RESERVED_MEMORY__

        .import         initlib, donelib, callmain
        .import         zerobss, copydata

        .include        "zeropage.inc"
        .include        "atari5200.inc"

;;; start of (slightly modified) OS ROM code. the OS calls us with
;;; interrupts disabled, decimal mode cleared, with the stack pointer
;;; set to $FF. Since this is a diagnostic cart, we have to init the
;;; hardware and set up the interrupt vector table at $0200 (the OS
;;; doesn't do it for us, like it would for a non-diag cart).

;;; This code is based on Dan Boris's commented disassembly of the 4-port
;;; 5200 BIOS, retrieved from <http://atarihq.com/danb/files/5200BIOS.txt>.

;;; I've copied just the initialization code, minus the logo/copyright
;;; screen, and modified it to work with either OS revision.

;;; Everything I've read tells me that the 4-port OS will work on a 2-port
;;; machine (the hardware changes don't break compatibility), so the code
;;; here comes from the 4-port OS.

 tmpptr = $11 ; 2 bytes, aka PADDL0 and PADDL1

start:
 ldx #0
 txa
@clrloop:
 sta  POKEY,x   ;Clear POKEY registers
 sta  GTIA,x   ;Clear GTIA registers
 sta  ANTIC,x   ;Clear ANTIC registers
 sta  $00,x   ;Clear zero page
 inx
 bne  @clrloop
 lda  #$F8
 sta  CHBASE   ;Set Character base to $F800

; Determine which OS revision we're running under. This affects
; the locations of the vector table and display list in the ROM,
; and is probably the reason a few published 5200 games are
; incompatible with the Rev A ROM.
; Rev A has $07 at $fee5, original OS has $61. The vector table
; lives at $fe95 on the original OS and $feab on rev A.
; If there are other OS revisions out there in the wild, this
; code will likely fail on them.

 lda #$fe ; either way, the hi byte of the vector table is $fe
 sta tmpptr+1
 lda $fee5
 cmp #$07
 beq @rev_a

 ; set up pointer to vector table according to the OS revision we're on.
 lda #$95 ; the old gods...
 .byte $2c
@rev_a:
 lda #$ab ; ...and the new.
 sta tmpptr

@copy_vectors:
 ldy  #$0B ; 6 vectors, 2 bytes each.
@cploop:
 lda  (tmpptr),y
 sta  VIMIRQ,y   ;Copy vectors to vector table
 dey
 bpl  @cploop

 ; clear 3K of memory from $3000 to $3c00 (why only 3K?)
 ; if ROM space gets *really* tight, check & see whether we
 ; can live without this.
 lda  #$3C   ;Set pointer to $3C00
 sta  tmpptr+1
 lda  #$00
 sta  tmpptr

 ldx  #$0C
 tay  ; A still 0
@memclrloop:
 sta  (tmpptr),y
 dey
 bne  @memclrloop
 dec  tmpptr+1
 dex
 bpl  @memclrloop

 lda  #$22   ;Set DMACTL, dlist on/normal background
 sta  SDMCTL

 lda  #$C0
 sta  NMIEN  ;Enable DLI and VBI
 lda  #$02
 sta  SKCTL  ;Enable Keyboard scanning

 lda #$40
 sta IRQEN ; enable keyboard IRQ
 sta POKMSK
 cli       ; enable IRQ

 .out .sprintf("%d bytes", * - start)
;;; end of OS ROM code, rest of file is standard 5200 crt0.s.

; Clear the BSS data.

        jsr     zerobss

; Initialize the data.
        jsr     copydata

; Set up the stack.

        lda     #<(__RAM_START__ + __RAM_SIZE__ - __RESERVED_MEMORY__)
        sta     sp
        lda     #>(__RAM_START__ + __RAM_SIZE__ - __RESERVED_MEMORY__)
        sta     sp+1            ; Set argument stack ptr

; Call the module constructors.

        jsr     initlib

; Push the command-line arguments; and, call main().

        jsr     callmain

; Call the module destructors. This is also the exit() entry.

_exit:  jsr     donelib         ; Run module destructors

; A 5200 program isn't supposed to exit.

halt:   jmp halt
