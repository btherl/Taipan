
 .export _port_stat_screen, _redraw_port_stat
 .import _port_stat_dirty
 .importzp ptr1, ptr2

 srcptr = ptr1
 dstptr = ptr2

 .include "atari.inc"

; PORTSTAT.DAT is created on the H: device by running mkportstats.xex
; in atari800. H: needs to be set writable and pointed to the current
; directory.

 .rodata
_port_stat_screen:
 .incbin "PORTSTAT.DAT"
screenlen = * - _port_stat_screen
screenpages = >screenlen
partial = <screenlen

 .ifdef CART_TARGET
  .segment "HIGHCODE"
 .else
  .code
 .endif

; only redraw the port status screen if needed. this saves 53 bytes
; compared to using memcpy().
; void redraw_port_stat(void);
_redraw_port_stat:
 ;lda _port_stat_dirty
 ;beq @done

 lda #<_port_stat_screen
 sta srcptr
 lda #>_port_stat_screen
 sta srcptr+1

 ; add 40 because PORTSTAT.DAT no longer contains the all-blank
 ; first line.
 lda SAVMSC
 clc
 adc #$28
 sta dstptr
 lda SAVMSC+1
 adc #$00
 sta dstptr+1

 ; copy screenpages pages
 ldx #screenpages
 ldy #0
@pageloop:
 lda (srcptr),y
 sta (dstptr),y
 dey
 bne @pageloop
 inc srcptr+1
 inc dstptr+1
 dex
 bne @pageloop

 ; copy last (partial) page. we know Y is 0 here.
 ;sty _port_stat_dirty ; do not clear the flag, the caller will
@partloop:
 lda (srcptr),y
 sta (dstptr),y
 iny
 cpy #partial
 bne @partloop

@done:
 rts
