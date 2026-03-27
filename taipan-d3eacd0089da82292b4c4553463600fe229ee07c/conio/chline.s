; modified for taipan:
; - removed _chlinexy as taipan never uses it.
; - get rid of the check for a 0 argument. taipan only calls chline()
;   with constant non-zero args.
;
; Ullrich von Bassewitz, 08.08.1998
;
; void chlinexy (unsigned char x, unsigned char y, unsigned char length);
; void chline (unsigned char length);
;

        .export         _chline, _cspaces
        .import         cputdirect
        .importzp       tmp1, tmp2

.ifdef __ATARI5200__
CHRCODE =       14
.else
CHRCODE =       $12+64
.endif

_cspaces:
 ldx #0
 .byte $2c
_chline:
 ldx #CHRCODE
 stx tmp2
        sta     tmp1
L1:     lda     tmp2
        jsr     cputdirect      ; Direct output
        dec     tmp1
        bne     L1
L9:     rts
