; Random number generator and wrappers for Taipan.

; Originally I used POKEY's RANDOM register. It made for smaller code,
; and seemed OK...
; After some crude statistical analysis, I've decided to go with cc65's
; rand() implementation. It seems to return more evenly distributed
; results.

 .export _randl, _rand1to3
 .importzp sreg

 .include "atari.inc"

 .ifdef CART_TARGET
  .segment "HIGHCODE"
 .else
  .code
 .endif

;;; Wrappers for rand():

; unsigned long __fastcall__ randl(void);
; this returns the full range of an unsigned long, 0 to 2**32-1
_randl:
 jsr _rand
 sta sreg
 jsr _rand
 sta sreg+1
 jsr _rand
 pha
 jsr _rand
 tax
 pla
 rts

; return 1, 2, or 3. equivalent to: randi()%3+1
; replacing both occurences of the expression in taipan.c with a calls
; to this function saves 11 bytes.
_rand1to3:
	jsr _rand      ; returns 16 bits: X is MSB (which we ignore), A is LSB
	and #$03       ; A now 0..3
	beq _rand1to3  ; try again, if it's 0
	ldx #0         ; now A is 1..3, but we have to force X to 0...
	rts

;;; rand() itself.
;;; This rand() function copied from cc65-2.19's libsrc/common/rand.s
;;; and modified for my nefarious purposes.
;;; srand() is not present (we don't use it).
;
; Random number generator
;
; Written and donated by Sidney Cadot - sidney@ch.twi.tudelft.nl
; 2016-11-07, modified by Brad Smith
; 2019-10-07, modified by Lewis "LRFLEW" Fox
;
; May be distributed with the cc65 runtime using the same license.
;
;
; int rand (void);
; void srand (unsigned seed);
;
;  Uses 4-byte state.
;  Multiplier must be 1 (mod 4)
;  Added value must be 1 (mod 2)
;  This guarantees max. period (2**32)
;  The lowest bits have poor entropy and
;  exhibit easily detectable patterns, so
;  only the upper bits 16-22 and 24-31 of the
;  4-byte state are returned.
;
;  The best 8 bits, 24-31 are returned in the
;  low byte A to provide the best entropy in the
;  most commonly used part of the return value.
;
;  Uses the following LCG values for ax + c (mod m)
;  a = $01010101
;  c = $B3B3B3B3
;  m = $100000000 (32-bit truncation)
;
;  The multiplier was carefully chosen such that it can
;  be computed with 3 adc instructions, and the increment
;  was chosen to have the same value in each byte to allow
;  the addition to be performed in conjunction with the
;  multiplication, adding only 1 additional adc instruction.
;

 .export _rand, _randseed, _initrand, _addrandbits

.bss

; The seed. Not ANSI C compliant: we default to 0 rather than 1.
; Yes, this means we get a constant stream of 0 from rand()
; if we never seed it. No, we haven't forgot to seed it!
_randseed:   .res 4

.code

_rand:  clc
        lda     _randseed+0
        adc     #$B3
        sta     _randseed+0
        adc     _randseed+1
        sta     _randseed+1
        adc     _randseed+2
        sta     _randseed+2
        and     #$7f            ; Suppress sign bit (make it positive)
        tax
        lda     _randseed+2
        adc     _randseed+3
        sta     _randseed+3
        rts                     ; return bit (16-22,24-31) in (X,A)

;;; End of cc65 code.

; cc65's srand() is ANSI/ISO compliant... meaning it takes an int
; argument, which on 6502 means only 16 bits for the initial seed.
; So even though rand() generates a list of 4.3 billion nonrepeating
; results, there would only be 65535 starting points. To keep things
; less predictable, replace srand() with initrand() and addrandbits().
; initrand() sets the initial 32-bit random state from 4 successive
; reads of the Atari's POKEY pseudo-random register. The register
; keeps clocking all the time, so essentially its state is dependent
; on how long the Atari has been powered up. If we just used that for
; a random seed, the game might be too predictable (a given copy of
; the game will possibly take the same amount of time to load on the
; same drive, plus the cartridge doesn't load from disk so it's 100%
; deterministic). So addrandbits() adds entropy based on user actions:
; characters typed and the timing of the typing, to 1 jiffy precision.

; Initial plan was to generate a 32-bit seed value in the range 1 to
; 2**32-1. However I fudged it a little: none of the bytes will ever
; be initialized to 0, so it's really 1 to 255**4-1 (which is 98.5%
; of the full range: still over 4 billion possibilities).

;;; The next 2 paragraphs are speculative, don't relate to any actual code:

; Note: I came up with an elaborate scheme to sample the KBCODE
; register every scanline. Some users might actually be able to time
; their typing to 1/60 sec precision, but nobody could do that at
; scanline precision (a scanline is something like 64 microseconds).
; We could use the raw scanline number as the random value, or even
; do some calculations to get the color clock when the register
; changed (no idea whether that's useful, whether POKEY's keyboard
; hardware is that precise).
; Unfortunately it probably won't work in emulators because they
; generally process keyboard events once per frame. I didn't bother
; to code it & test it because it's overkill anyway.

; Note: I came up with a weird idea that might be useful to someone.
; When you enable players and/or missiles, but don't enable their DMA,
; they display garbage, which as I understand it is the contents of
; the data bus being read by ANTIC while the 6502 is still running.
; You could position a player or missile so one bit of it (bit 0 or
; 7) overlaps the playfield, then loop every scanline and read the
; collision register, shifting the bits into a result register. This
; would get you a lot of potentially-random bits, but since the
; 6502 is executing real code, they might not really be all that
; random. I'd like to code it up and analyze the results someday, but
; that's *way* outside the scope of this game!

;;; End of speculations, back to code.

; If you're trying to debug initrand() and/or addrandbits(), uncomment
; the #define RANDSEED_TEST at the top of taipan.c

; extern void __fastcall__ initrand(void);
; Initially the seed comes from sequential reads of POKEY's random
; register. It never returns 0 so we're guaranteed to have a usable
; seed. However, the sequential reads and the fact that initrand()
; gets called a constant amount of time after startup, means the
; initial seed won't be very random by itself. It'll get mutated
; by agetc() and addrandbits() as the user types the firm name. Even
; if he only types a 1-character name followed by Return, that's still
; going to give us a decent random seed.

_initrand:
 ldx #3
@l:
 lda RANDOM
 sta _randseed,x
 dex
 bpl @l
 rts

; extern void __fastcall__ addrandbits(char);
; Called by init_game() after each character is typed.
; The point of this is to turn the little bit of entropy in the
; user's input and timing into more entropy from POKEY. The less
; frequently you read RANDOM, the less correlated (and more random)
; the results will be.
; Caller passes us a user keystroke as ATASCII, in A. We take bits 0
; to 2 [*], wait that many scanlines, get a random number from POKEY, and
; EOR it into the _randseed byte pointed to by the low 2 bits of the
; frame counter (RTCLOK+2).
; Doing it this way, it's guaranteed that at least one byte of
; _randseed will be modified by addrandbits(). It's likely that
; more than one will be, but not guaranteed.
; Note that agetc() is still calling rand() on odd frames while all
; this is going on, so the bytes in the seed might not be the ones
; initrand() or addrandbits() put there!

_addrandbits:
 and #$07
 tax
@scanloop:    ; wait X scanlines
 sta WSYNC
 dex
 bpl @scanloop
 lda RTCLOK+2 ; the jiffy timer
 and #$03     ; destination byte (offset 0-3 from _randseed)
 tax
 lda RANDOM
@e:
 eor _randseed,x ; combine with the existing bits
 beq @e          ; if the result is 0, undo the eor.
 sta _randseed,x
 rts

; [*] I did some analysis of English text (various novels in ASCII
; e-book form) and it appears that normally bits 0 and 2 are set on
; 50% of the bytes on average (and clear the other 50% of course). Bit
; 1 is only set 33% of the time on average. This is a result of the
; frequency-of-use of the characters. Remember ETAOIN SHRDLU? Look at
; bits 0-2 of each byte... Also spaces are very common, and bits 0-2
; are of course all 0 there. So using bits 0-2 of the user's typing
; is actually biased (we get 0 to 7, but the values 0, 1, 4, 5 occur
; twice as often as 2, 3, 6, 7). This doesn't matter much, as we're
; using the result as a scanline counter to delay a read from RANDOM:
; the original bits don't end up in the seed.

;;; rest of file is commented out, left for reference.

; RANDOM is the POKEY LFSR read address. According to the POKEY data
; sheet, this is the high 8 bits bits of a 17-bit LFSR (Atari calls it
; a poly counter). Unfortunately, a read from this address never seems
; to return 0, which confuses me: an LFSR can never return 0, but since
; we're only reading 8 bits of it, we should be able to get a 0 (some
; of the other 9 bits would still be 1).

; Might use this at some point:
;_randbit:
; lda RANDOM
; asl
; lda #0
; adc #0
; rts

; unsigned char __fastcall__ randbit(void);
;_randbit:
; ldx #0
;randbit:
; lda RANDOM
; lsr
; and #$01
; rts

; This doesn't give evenly distributed results, it's twice as
; likely to return 2 or 3 than 0, 1, or 4.
; unsigned char __fastcall__ rand1in5(void);
;_rand1in5:
; ldx #0
;rand1in5:
; lda RANDOM
; lsr
; lsr
; and #$03
; adc #0
; rts


; unsigned char __fastcall__ randb(void);
;;_randb: ; C-callable entry point
;; ldx #0
;;randb:  ; asm-callable (doesn't trash X reg)
;; lda RANDOM ; bit 7 of this read ends up as bit 0 of result
;; sta tmp3
;; nop        ; let the LFSR cook for a bit...
;; nop
;; lda RTCLOK+2 ; different amount of cooking depending on whether
;; and #$01     ; we're on an even or odd numbered TV frame
;; bne @1
;; nop
;; nop
;; nop
;;@1:
;; rol tmp3   ; tmp3 bit 7 now in carry
;; lda RANDOM
;; rol        ; carry now in bit 0 of A
;; nop
;; nop
;; rts

; unsigned int __fastcall__ randi(void);
; NB cc65's rand() returns a positive signed int, meaning
; 0 to 0x7fff.
;;_randi:
;; jsr randb
;; and #$7f
;; tax
;; jsr randb
;; rts

; unsigned long __fastcall__ randl(void);
; this returns the full range of an unsigned long, 0 to 2**32-1
;;_randl:
;; jsr randb
;; sta sreg
;; jsr randb
;; sta sreg+1
;; jsr randb
;; tax
;; jsr randb
;; rts

