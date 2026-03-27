

 .importzp ptr3, sreg
 .import popeax, popax, pushax, _memcmp
 .export _ulong_to_big, _big_to_ulong, _big_add, _big_sub, _big_mul, _big_div
 .export _bank_maxed_out, _big_cmp, _big_copy  ;, _big_negate

 .include "atari.inc"

 fptemp = $a0 ; for now
 trampoline = $c0

 ; cc65's atari.inc is missing this FP entry point:
 NORMALIZE = $dc00

 ; atari.inc also has a typo, PLD1P for FLD1P
 FLD1P = PLD1P

 ;bfstart = *

 .rodata
BIG_64K: ; 65535 (2**16-1) in float format.
 .byte $42, $06, $55, $36, $00, $00

;BIG_ULONG_MAX:
 ;.byte $44, $42, $94, $96, $72, $95

 .ifdef CART_TARGET
  .segment "HIGHCODE"
 .else
  .code
 .endif

; It seems like fr0_to_fptemp and friends should be using the OS
; FLD* and FST* routines, doesn't it? But look:

;fr0_to_fptemp:
; lda #<fptemp
; sta FLPTR
; lda #>fptemp
; sta FLPTR+1
; jmp FST0P

; ...that's 11 bytes of code. The fr0_to_fptemp saves 1 byte of code,
; plus it runs faster (doesn't use FLPTR, no JMP).

fr0_to_fptemp:
 ldx #5
@l:
 lda FR0,x
 sta fptemp,x
 dex
 bpl @l
 rts

fptemp_to_fr0:
 ldx #5
@l:
 lda fptemp,x
 sta FR0,x
 dex
 bpl @l
 rts

fptemp_to_fr1:
 ldx #5
@l:
 lda fptemp,x
 sta FR1,x
 dex
 bpl @l
 rts

;fr0_to_ptr3:
; ldy #5
;@l:
; lda FR0,y
; sta (ptr3),y
; dey
; bpl @l
; rts

;ptr4_to_fr1:
; ldy #5
;@l:
; lda (ptr4),y
; sta FR1,y
; dey
; bpl @l
; rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; void __fastcall__ big_negate(bignump b);
; This doesn't call the ROM or use FR0/FR1, it just inverts the sign
; bit in-place.
;_big_negate:
; sta ptr3
; stx ptr3+1
; ldy #0
; lda (ptr3),y
; eor #$80
; sta (ptr3),y
; rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; truncate FR0 to integer (no rounding: 2.8 -> 2)
trunc_fr0:
 lda FR0
 and #$7f ; strip sign bit (we only care about exponent magnitude)
 sec
 sbc #$3f ; A now holds # of base-100 digits in integer part
 bcs @ok  ; # of int digits > 0?
 jmp ZFR0 ; no, zero out FR0 and exit

@ok:
 cmp #5     ; are there <= 5 int digits?
 bcs @done  ; no, the number's already an integer.

 tax        ; zero out digits: X is first one after decimal point
 lda #0
@zloop:
 sta FR0+1,x
 inx
 cpx #5
 bne @zloop

@done:
 rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; void __fastcall__ big_copy(bignump dest, bignump src)
_big_copy:
 sta FLPTR    ; src arg in FLPTR
 stx FLPTR+1
 jsr FLD0P    ; load src value into FR0
 jsr popax    ; get dest arg
 sta FLPTR    ; dest arg in FLPTR
 stx FLPTR+1
 jmp FST0P    ; store FR0 value into dest

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; void __cdecl__ big_add(bignump dest, bignump a, bignump b);
_big_add:
 lda #<FADD
 ldx #>FADD
 ; fall through to _big_binary_op

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; void __fastcall__ big_binary_op(bignump dest, bignump a, bignump b, unsigned int jsraddr);
_big_binary_op:

 ; JSR address in A/X pair, set up JMP instruction
 sta trampoline+1
 stx trampoline+2
 lda #$4c ; JMP opcode
 sta trampoline

 ; get 2nd operand (b), load into FR1
 jsr popax
 sta FLPTR
 stx FLPTR+1
 jsr FLD1P

 ; get 1st operand (a), load into FR0
 jsr popax
 sta FLPTR
 stx FLPTR+1
 jsr FLD0P

 ; call the FP routine
 jsr trampoline

; jsr NORMALIZE
; .byte $02

 ; result now in FR0, get destination & copy
 jsr popax
 sta FLPTR
 stx FLPTR+1
 jmp FST0P

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; void __cdecl__ big_sub(bignump dest, bignump a, bignump b);
_big_sub:
 lda #<FSUB
 ldx #>FSUB
 bne _big_binary_op ; branch always

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; void __cdecl__ big_mul(bignump dest, bignump a, bignump b);
_big_mul:
 lda #<FMUL
 ldx #>FMUL
 bne _big_binary_op ; branch always

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; void __cdecl__ big_div(bignump dest, bignump a, bignump b);
_big_div:
 lda #<FDIV
 ldx #>FDIV
 bne _big_binary_op ; branch always

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; void __fastcall__ big_trunc(bignump b);
; C-callable wrapper for trunc_fr0
 sta FLPTR
 stx FLPTR+1
 jsr FLD0P
 jsr trunc_fr0
 jsr FST0P
 rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; void __fastcall__ ulong_to_big(const unsigned long l, bignum *b);
; This works by splitting the 32-bit l into two 16-bit ints and
; converting them separately using the OS, then multiplying the high
; result by 2^16 and adding the low result.
_ulong_to_big:
 sta ptr3
 stx ptr3+1 ; save b (destination)

 jsr popeax ; get low 16 bits of l in A/X (hi 16 bits in sreg)
 sta FR0
 stx FR0+1
 jsr IFP    ; convert A/X to fp

 jsr fr0_to_fptemp ; stash it

 lda sreg   ; now get high 16 bits of l in A/X
 sta FR0
 ldx sreg+1
 stx FR0+1
 jsr IFP    ; convert to fp

 ; high value needs to be multiplied by 65536

 ldx #<BIG_64K ; FR1 = 65536
 ldy #>BIG_64K
 jsr FLD1R

 ;lda #<BIG_64K
 ;sta FLPTR
 ;lda #>BIG_64K
 ;sta FLPTR+1
 ;jsr FLD1P

 ; old version:
; lda #<BIG_64K
; sta ptr4
; lda #>BIG_64K
; sta ptr4+1
; jsr ptr4_to_fr1

 jsr FMUL          ; multiply...
 jsr fptemp_to_fr1 ; grab low value
 jsr FADD          ; add to total

 ; store it in b and we're done.
 ;jmp fr0_to_ptr3 ; used to do this, use OS instead:
 lda ptr3
 sta FLPTR
 lda ptr3+1
 sta FLPTR+1
 jmp FST0P

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; char __fastcall__ big_to_ulong(bignump b, unsigned long *l);
;
; This works, but it's not small, fast, or elegant...
_big_to_ulong:
 sta ptr3
 stx ptr3+1 ; save *l (dest)

 jsr popax ; get b
 sta FLPTR
 sta sreg
 stx FLPTR+1
 stx sreg+1
 jsr FLD0P

 ldx #<BIG_64K ; FR1 = 65536
 ldy #>BIG_64K
 jsr FLD1R

 jsr FDIV      ; FR0 = FR0 / FR1
 jsr trunc_fr0 ; FR0 = INT(FR0)
 jsr fr0_to_fptemp ; stash for later...
 jsr FPI       ; get integer form
 bcc @ok       ; OS supposed to return with C set if range error

 ; failed, return 0 to caller
 lda #0
 tax
 rts

@ok:
 ldy #2        ; save top 16 bits of result where they belong
 lda FR0
 sta (ptr3),y
 iny
 lda FR0+1
 sta (ptr3),y

 jsr fptemp_to_fr0 ; this is int((*b)/65536) in FR0 now

 ldx #<BIG_64K ; FR1 = 65536
 ldy #>BIG_64K
 jsr FLD1R

 jsr FMUL     ; FR0 now int((*b)/65536)*65536
 jsr FMOVE    ; FR1 = FR0

 ldx sreg     ; reload original *b in FR0
 ldy sreg+1
 jsr FLD0R
 jsr trunc_fr0 ; grrr. If we don't do this, we get rounding (not desired)

 jsr FSUB     ; FR0 = FR0 - FR1
 jsr FPI

 ldy #0       ; store low 16 bits where they belong
 lda FR0
 sta (ptr3),y
 iny
 lda FR0+1
 sta (ptr3),y

 ; success. return 1 to caller.
 tya
 ldx #0
 rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; char __fastcall__ bank_maxed_out(bignump b);
_bank_maxed_out:
 sta FLPTR
 stx FLPTR+1
 jsr FLD0P
 jsr NORMALIZE ; just in case
 lda FR0 ; get exponent
 ldx #0
 eor #$7f ; remove sign bit (should never be negative anyway!)
 cmp #$46
 bcc @false
 lda #1
 rts
@false:
 txa
 rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; signed char __fastcall__ big_cmp(bignump a, bignump b)
;
; this could be better: it could be a wrapper for _big_binary_op. But
; I'd have to move stuff all around on the stack.
_big_cmp:
 sta FLPTR
 stx FLPTR+1
 jsr FLD1P

 jsr popax     ; get a arg

 sta FLPTR
 stx FLPTR+1
 jsr FLD0P

 ; subtract (and throw away the result, only care about sign)
 jsr FSUB ; FR0 = FR0 - FR1

 lda FR0  ; exponent has sign bit, and happily is 0 if the result was 0!
 tax      ; sign extension, grr.
 rts

 ;.out .sprintf("bigfloat.s code is %d bytes", *-bfstart)
