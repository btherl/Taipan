
; Text decompressor for Taipan.

; extern void __fastcall__ print_msg(const char *msg);

; Text is packed into one snac per character.

; A snac is 6 bits, somewhere between a nybble and a byte. It could
; also stand for "Six Numeral ASCII-like Code" :)

; See textcomp.c for details of encoded format.

 .include "atari.inc"

 .export _print_msg
 .export _print_item, _print_location

 .import _item, _location
 .import _cputc

 srcptr = FR1
 outsnac = FR0 ; decoded snac (6-bit byte)
 bitcount = FR0+1 ; counts 8..1, current bit in inbyte
 inbyte = FR0+2 ; current input byte
 ysave = FR0+3
 dict_escape = FR0+4 ; true if last character was a Z

 .rodata

; The dictionary itself. Each entry is a snac-encoded string. One or two
; letter words are not worth listing here: they encode to 2 bytes each,
; plus the dictionary escape code is 2 bytes (snacs actually) per use. 3
; is only good if it's used pretty often.

; In messages.c, dict01 to dict26 will show up as Za thru Zz, and dict27
; and up are ZA, ZB, etc. A dict entry could reference another
; dict entry, the decoder can handle it, but it has to be done manually
; here. Examples are dict02, "Elder Brother", which is really "Elder BroZNr",
; and dict12, " the", which is really " ZN".

; Entry 0 is a dummy! The encoder gets confused by "Z\0". This may
; get fixed.

; There can be be up 63 entries in the dictionary (64, counting the
; dummy entry 0), since a 6-bit snac is used as the index.

; Dictionary size cannot exceed 255 bytes. Actually the last entry
; can extend past 255 bytes, so long as it *starts* within 255 bytes
; of dict00. Break this rule and you get a range error when you build.

; The quoted stuff in comments is read by messages.pl, it needs to be
; the exact un-encoded form of the snac string. Anything after the quotes
; (e.g. number of occuurences) is ignored. The order here isn't important,
; messages.pl will apply them in order by length (longest first).

; To get the bytes to use for a particular message:
; echo -n "message here" | ./textcomp 2>/dev/null|perl -ple 's/0x/\$/g; s/ /, /g'

; the "We made it!" dict08 saves 8 bytes vs. the commented-out one.

dict00:
dict01: .byte $98, $9d, $73, $54, $53, $80 ; "Li Yuen", 4 occurrences
dict02: .byte $7c, $c1, $05, $4b, $57, $12, $3f, $4a, $12, $00 ; "Elder Brother"
dict03: .byte $64, $f5, $40 ; "you", 30
dict04: .byte $d7, $c1, $4d, $00 ; " 'em", 8
dict05: .byte $cc, $f5, $40 ; "You", 16
dict06: .byte $d4, $80, $56, $14, $00 ; " have", 11
dict07: .byte $d5, $32, $01, $30, $c0, $00 ; " shall", 6
;dict08: .byte $fb, $5c, $49, $50, $8d, $40 ; ") With ", 2
dict08: .byte $c4, $5d, $4d, $04, $41, $75, $25, $4d, $80 ; "We made it!"
dict09: .byte $05, $21, $cf, $00 ; "argo", 6
dict10: .byte $4c, $82, $50, $00 ; "ship", 10
dict11: .byte $d5, $70, $52, $14, $83, $d5, $4c, $50, $00 ; " warehouse", 4
;dict12: .byte $d5, $42, $05, $00 ; " the" 17
dict12: .byte $d7, $4a, $00 ; " the"
dict13: .byte $d4, $f1, $80 ; " of", 14
dict14: .byte $5c, $93, $0c, $00 ; "will", 8
dict15: .byte $d4, $21, $45, $3b, $50, $00 ; " been ", 6
dict16: .byte $d5, $43, $f5, $00 ; " to ", 12
dict17: .byte $20, $14, $f5, $00 ; "has ", 7
dict18: .byte $18, $f4, $b5, $00 ; "for ", 7
dict19: .byte $25, $3d, $40 ; "is ", 9
dict20: .byte $04, $e1, $00 ; "and", 10
dict21: .byte $d4, $30, $53, $20, $00 ; " cash", 8
dict22: .byte $04, $41, $09, $50, $93, $ce, $04, $cd, $40 ; "additional ", 3
dict23: .byte $b8, $12, $50, $04, $e0, $00 ; "Taipan", 47
dict24: .byte $d4, $f3, $8c, $67, $50, $00 ; " only ", 3
dict25: .byte $d4, $25, $47, $1c, $54, $93, $00 ; " buggers", 3
dict26: .byte $5c, $95, $08, $d4, $00 ; "with ", 4
dict27: .byte $d4, $64, $8f, $37, $50, $00 ; " from ", 3
dict28: .byte $d5, $70, $4e, $50, $00 ; " want"
dict29: .byte $5c, $f4, $94, $20, $93, $85, $4d, $30, $00 ; "worthiness"
dict30: .byte $d4, $d5, $43, $20, $00 ; " much"
dict31: .byte $10, $91, $86, $15, $21, $4e, $0c, $50, $00 ; "difference"
dict32: .byte $74, $f3, $50, $48, $11, $0f, $48, $00 ; "Comprador"
dict33: .byte $f1, $3d, $6c, $15, $03, $d2, $50, $00 ; "'s Report"
dict34: .byte $6d, $91, $78, $d5, $71, $7c, $30, $cd, $40 ; "Aye, we'll "
dict35: .byte $08, $f0, $52, $10, $00 ; "board"
dict36: .byte $40, $94, $81, $50, $50, $00 ; "pirate"
dict37: .byte $d4, $e3, $c0 ; " no"
dict38: .byte $d5, $72, $53, $20, $00 ; " wish"
dict39: .byte $10, $50, $94, $00 ; "debt"
dict40: .byte $50, $81, $40 ; "the"
dict41: .byte $78, $fd, $74, $0c, $00 ; "Do you"
dict42: .byte $84, $53, $85, $48, $13, $00 ; "General"
dict43: .byte $d0, $34, $b5, $00 ; "your "
dict44: .byte $c0, $54, $99, $d5, $71, $4c, $30, $00 ; "Very well"
dict45: .byte $84, $f3, $c4, $d4, $a3, $d3, $4f, $6d, $80 ; "Good joss!!"
dict46: .byte $d1, $7d, $80 ; "Taipan!"
;dict47: .byte $d2, $ed, $80 ; "Taipan!!"
dict47: .byte $17, $c4, $85, $d4, $73, $c9, $38, $7d, $44, $3d, $73, $80 ; "e're going down"

; Table has to be <= 1 page, so this won't fit:
;dict47: .byte $c4, $5d, $4d, $04, $41, $75, $25, $4d, $80 ; "We made it!"

 .out .sprintf("dictionary is %d bytes", * - dict00)

dict_offsets:
 .byte dict00 - dict00
 .byte dict01 - dict00
 .byte dict02 - dict00
 .byte dict03 - dict00
 .byte dict04 - dict00
 .byte dict05 - dict00
 .byte dict06 - dict00
 .byte dict07 - dict00
 .byte dict08 - dict00
 .byte dict09 - dict00
 .byte dict10 - dict00
 .byte dict11 - dict00
 .byte dict12 - dict00
 .byte dict13 - dict00
 .byte dict14 - dict00
 .byte dict15 - dict00
 .byte dict16 - dict00
 .byte dict17 - dict00
 .byte dict18 - dict00
 .byte dict19 - dict00
 .byte dict20 - dict00
 .byte dict21 - dict00
 .byte dict22 - dict00
 .byte dict23 - dict00
 .byte dict24 - dict00
 .byte dict25 - dict00
 .byte dict26 - dict00
 .byte dict27 - dict00
 .byte dict28 - dict00
 .byte dict29 - dict00
 .byte dict30 - dict00
 .byte dict31 - dict00
 .byte dict32 - dict00
 .byte dict33 - dict00
 .byte dict34 - dict00
 .byte dict35 - dict00
 .byte dict36 - dict00
 .byte dict37 - dict00
 .byte dict38 - dict00
 .byte dict39 - dict00
 .byte dict40 - dict00
 .byte dict41 - dict00
 .byte dict42 - dict00
 .byte dict43 - dict00
 .byte dict44 - dict00
 .byte dict45 - dict00
 .byte dict46 - dict00
 .byte dict47 - dict00
 ;.byte dict48 - dict00

; rough estimate of how many bytes are saved by the dictionary
; stuff: the dictionary + extra decoder stuff costs 221 bytes (vs.
; the original textdecode.s without dictionary).
; each dictionary entry saves (length - 2) * (occurrences - 1) bytes.
; with only dict00 - dict23, we'll save around 173 bytes.
; actually it works out to 179 bytes, but the estimate was close.
; we've reached the point of diminishing returns: dict00 - dict31 only
; saves 199 bytes.

 dictsize = * - dict00
 .out .sprintf("dictionary plus dict_offsets is %d bytes", dictsize)

 .include "msg.inc"

 .rodata
table: ; outsnac values 53..63
 .byte ' ', '!', '%', ',', '.', '?', ':', 39, 40, 41, $9b
 tablesize = * - table

 .ifdef CART_TARGET
  .segment "HIGHCODE"
 .else
  .code
 .endif

; extern void __fastcall__ print_location(char loc)
_print_location:
 asl
 tay
 lda _location,y
 ldx _location+1,y
 bne _print_msg ; branch always (location is never $00xx)

; extern void __fastcall__ print_item(char item)
_print_item:
 asl
 tay
 lda _item,y
 ldx _item+1,y ; fall thru

_print_msg:
 sta srcptr
 stx srcptr+1
 lda #0
 sta dict_escape
 sta outsnac
 ldy #$ff ; since we increment it first thing...

 ldx #6 ; counts 6..1, current bit in outsnac
@nextbyte:
 iny
 lda #8
 sta bitcount  ; counts 8..1, current bit in inbyte
 lda (srcptr),y
 sta inbyte
@bitloop:
 asl inbyte    ; get next bit from inbyte...
 rol outsnac   ; ...into outsnac
 dex
 beq @decode   ; got 6 bits, decode into ascii
 dec bitcount  ; more bits in this byte?
 bne @bitloop  ; get rest of bits in this byte...
 beq @nextbyte ; ...else next byte

@decode:
 lda outsnac
 bne @notend   ; are we done?
 rts           ; 0 = end of message

@notend:
 ldx dict_escape ; was previous character a Z?
 beq @normalchar

 jsr dict_lookup ; if so, do a dictionary lookup...
 jmp @noprint    ; ...and pick back up at next byte

@normalchar:     ; else it's a normal character
 cmp #27
 bcs @notlower
 adc #'a'-1      ; 1-26 are a-z
 bne @printit

@notlower:
 cmp #52
 bne @notdict
 inc dict_escape ; Z means next 6 bits are dictionary ID
 bne @noprint    ; don't actually print the Z

@notdict:
 bcs @notupper
 adc #38         ; 27-51 are A-Y
 bne @printit

@notupper:
 sbc #53 ; 53-63 are table lookups
 tax
 lda table,x

@printit:
 sty ysave ; _cputc trashes Y
 jsr _cputc
 ldy ysave
@noprint:
 lda #0
 sta outsnac
 ldx #6
 dec bitcount
 beq @nextbyte
 bne @bitloop

dict_lookup:
 ; dictionary lookup time. save our state on the stack. note that
 ; using the stack means dict entries could potentially contain
 ; dictionary escapes. each level would eat 7 bytes of stack, so be
 ; careful (the current dictionary doesn't do this at all)
 tya
 pha
 lda inbyte
 pha
 lda srcptr
 pha
 lda srcptr+1
 pha
 lda bitcount
 pha

 ldx outsnac ; get the start address of the dictionary entry into AX
 lda dict_offsets,x ; this is why the dictionary can't be <255 bytes total
 clc
 adc #<dict00    ; calculate low byte from base + offset
 sta dict_escape ; temp usage, will be overwritten after _print_msg
 lda #>dict00
 adc #0          ; calculate hi byte
 tax             ; hi byte in X
 lda dict_escape ; lo byte in A
 jsr _print_msg  ; recursive call, print the dictionary entry

 ; restore old state
 lda #0
 sta dict_escape
 pla
 sta bitcount
 pla
 sta srcptr+1
 pla
 sta srcptr
 pla
 sta inbyte
 pla
 tay

 rts ; print rest of original message

 ; this size doesn't include _print_location and _print_item, they really
 ; aren't part of the decompressor, they're only in this file so they
 ; can fall through to _print_msg instead of jmp there (saves a few bytes).
 decodersize = * - _print_msg

 .out .sprintf("print_msg() is %d bytes", decodersize + tablesize)
 .out .sprintf("total textdecomp is %d bytes", decodersize + tablesize + dictsize)
