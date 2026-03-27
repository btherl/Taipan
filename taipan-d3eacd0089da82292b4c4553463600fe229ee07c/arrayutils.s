; extern void clear_ships_on_screen(void);

; optimized bzero() replacement.
; the real bzero() in cc65-2.19 is 129 bytes long.
; it's optimized for speed (has an unrolled loop) and shares
; code with memset(). we can do it in a lot less code here,
; especially since we only need to clear exactly 20 bytes
; located at a known absolute address.

; in C, we could write: for(i=0; i<len; i++) { arr[i] = 0; }
; ...which takes up around 64 bytes of code.
; instead, this: clear_ships_on_screen();
; ...takes 3 bytes for the function call, plus ~20 bytes for
; the function, or around 1/3 the size of the for loop, or under 1/4
; the size of bzero() plus its function call.

; we also have clear_hkw() and clear_hold().

 .import _ships_on_screen, _hkw_, _hold_
 .export _no_ships_on_screen
 .export _hold_is_empty, _hkw_is_empty, _have_no_cargo
 .export _clear_hkw, _clear_hold, _clear_ships_on_screen

 .include "atari.inc"

 .code
_clear_ships_on_screen:
 lda #<(_ships_on_screen-1)
 ldx #>(_ships_on_screen-1)
 ldy #$14
 ; fall thru

clr_array:
 ; AX is array address minus one!
 ; Y is sizeof(array)
 sta FR0
 stx FR0+1
 lda #0
@l:
 sta (FR0),y
 dey
 bne @l
 rts

_clear_hkw:
 lda #<(_hkw_-1)
 ldx #>(_hkw_-1)
 ldy #$08
 bne clr_array

_clear_hold:
 lda #<(_hold_-1)
 ldx #>(_hold_-1)
 ldy #$10
 bne clr_array

;;;;;

; Several places in the Taipan C code we have to check whether an
; array is all zero. A for loop in C takes up quite a bit of space,
; so write an array-checker in asm.

; Wrappers for array_is_empty():
; no_ships_on_screen()
; hold_is_empty()
; hkw_is_empty()
; have_no_cargo();

_no_ships_on_screen:
 lda #<(_ships_on_screen-1)
 ldx #>(_ships_on_screen-1)
 ldy #$14
 ; fall thru

array_is_empty:
 ; AX is array address minus one!
 ; Y is sizeof(array)
 sta FR0
 stx FR0+1
@l:
 lda (FR0),y
 bne ret0
 dey
 bne @l
@ret1:
 lda #1
 rts
ret0:
 lda #0
 tax ; need this or not?
 rts

_hkw_is_empty:
 lda #<(_hkw_-1)
 ldx #>(_hkw_-1)
 ldy #$08
 bne array_is_empty

_hold_is_empty:
 lda #<(_hold_-1)
 ldx #>(_hold_-1)
 ldy #$10
 bne array_is_empty

_have_no_cargo:
 jsr _hkw_is_empty
 beq ret0
 bne _hold_is_empty
