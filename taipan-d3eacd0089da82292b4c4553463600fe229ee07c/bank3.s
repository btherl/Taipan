
; bank 3 of the cartridge image, to be built with -t none.
; this bank is the fixed bank, always mapped at $a000-$bfff, in
; the "left cartridge" area.

 .macpack atari ; for scrcode (screen code) macro

 .include "atari.inc"

; zero page temporaries
destptr = FR0
srcptr = FR1

; where the romable_taimain code was org'ed.
codedest = $0400

; address of the font, which lives in bank 3 of the cart.
font = $9c00

; cc65's atari.inc fails to define this standard Atari label.
CCNTL = $d500

; cart_trailer is my name for what the OS calls CARTLOC.
; cc65's atari.inc doesn't define it either.
cart_trailer = $bffa

 .org $a000 ; left cartridge

screendata:
 ; uncompressed title screen bitmap, $1700 bytes
 .incbin "titledata.dat"

 ;.out .sprintf("next byte after titledata is %x", *)

; message to print when someone tries to boot the cart
; in a 16K Atari.
mem_msg:
 scrcode "Need at least 32K"
mem_msg_len = * - mem_msg - 1

; copy_32_pages:
; copy 8192 bytes from $8000-$9fff to (destptr).
; on exit, destptr points to the next 8192 byte chunk.

; copy_x_pages:
; as above, but accepts number of pages to copy in X register.

; copy_pages:
; as copy_x_pages, but the caller must set up srcptr as well
; as the X reg.

copy_32_pages:
 ldx #$20
copy_x_pages:
 lda #$0
 sta srcptr
 lda #$80
 sta srcptr+1
copy_pages:
 ldy #0
@copypage:
 lda (srcptr),y
 sta (destptr),y
 dey
 bne @copypage
 inc srcptr+1
 inc destptr+1
 dex
 bne @copypage
init:
 rts

memory_error:
 lda #$20 ; red BG
 sta COLOR2
 ldy #mem_msg_len
@mloop:
 lda mem_msg,y
 sta (SAVMSC),y
 dey
 bpl @mloop
@hang:
 bmi @hang

 .out .sprintf("fudge factor: %d bytes", $b744-*)
 .res $b744-*, $ff ; fudge factor, keep the DL from crossing a 1K boundary

 ; newtitle.s is the display list and menu code. CART_TARGET is used
 ; for conditional assembly (to make it work from ROM).
CART_TARGET = 1
 .include "newtitle.s"

cartstart:
 lda RAMTOP
 cmp #$80
 beq mem_ok
 jmp memory_error

mem_ok:
; turn off ANTIC DMA to speed up copying to RAM
 lda #0
 sta SDMCTL
 sta DMACTL

; copy code to RAM
 lda #<codedest
 sta destptr
 lda #>codedest
 sta destptr+1

 ; banks 0 and 1 are full of code (minus the top page), bank 2
 ; is partially full. At some point, bank 2 might disappear, if
 ; I can shrink the code down to fit in 0 and 1 only.
 lda #0    ; bank 0...
 sta CCNTL ; ...select it
 jsr copy_32_pages

 lda #1    ; bank 1...
 sta CCNTL ; ...select it
 jsr copy_32_pages

 ; tail end of the code is stored in this bank.
 lda #<code_tail
 sta srcptr
 lda #>code_tail
 sta srcptr+1
 ldx #(>code_tail_size)+1
 jsr copy_pages

 ; bank 2 contains our font, RODATA, and some code (HIGHCODE seg) that
 ; runs from ROM rather than being copied to RAM. It stays enabled the
 ; entire time the game is running.
 lda #2    ; bank 2...
 sta CCNTL ; ...select it

 lda #1
 sta COLDST    ; System Reset = reboot
 jsr start     ; 'start' is from newtitle.s
 jsr codedest  ; run the game (romable_taimain)
 jmp cartstart ; redisplay title screen if "play again? N"

code_tail:
 .incbin "splitrom.raw.2"
 code_tail_size = * - code_tail + 1
 .out .sprintf("code_tail_size $%x (%d pages)", code_tail_size, (>code_tail_size)+1)

 .if * > cart_trailer
  .fatal "bank 3 code too large"
 .else
  .out .sprintf("=> %d bytes free in bank 3, at %x", cart_trailer - *, *)
 .endif

 ; fill with 1 bits until the cart trailer
 .res cart_trailer - *, $ff

 ; trailer (some docs called it a 'header' but, eh, it doesn't come at
 ; the head of the cart...)
 ; see Mapping the Atari's entry for 'Cartridge B' or the Tech Ref Manual
 ; for a description of this.
 .word cartstart ; entry point
 .byte 0         ; 0 = cartridge present
 .byte 4         ; init and run the cart, don't boot the disk, non-diagnostic
 .word init      ; init address (just an RTS)
