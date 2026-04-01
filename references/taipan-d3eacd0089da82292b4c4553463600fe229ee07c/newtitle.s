; this file needs to be assembled with:
; cl65 -o newtitle.xex -t none newtitle.s
; It contains only an init routine, no run address.

 .ifdef CART_TARGET
origin = *
 .else
 .include "atari.inc"

 ; where our screen was loaded (see newtitle.pl)
;screendata = $2400

 ; homebrew atari xex header
 .word $ffff
 .word origin
 .word end-1

; .org $a800
 .org origin
 .endif

 ; location sound code will look at to see whether sound
 ; is disabled (0 = enabled, !0 = disabled). If you
 ; change this here, change it in sounds.h also!
 ; $cb is free zero page, not used by the OS or DOS. These
 ; don't have to be zero page, but it saves a few bytes if
 ; they are.
sound_disabled = $cb

 .ifndef CART_TARGET
 ; since we're changing the font and colors, we'll save the old
 ; ones here. If you change these, change them in taipan.c and soundasm.s
 ; also.
fontsave = $cc
color1save = $cd
color2save = $ce
 .endif

version:
 .incbin "ver.dat"

 .ifdef CART_TARGET
dl_ram = $7000
help_lms = dl_ram + 1
help = $7010
help_rom:
 .else
help:
 .endif
 .incbin "help.dat"

helphitbl:
 .byte >version
 .byte >help
 .byte >(help+32)
 .byte >(help+64)
 .byte >(help+96)
 .byte 0

helplotbl:
 .byte <version
 .byte <help
 .byte <(help+32)
 .byte <(help+64)
 .byte <(help+96)
 .byte 0

 .ifdef CART_TARGET
help_size = * - help_rom
 .out .sprintf("help_size == %x", help_size)
 .endif

; background colors now cycles thru all 16 hues
;colorchoices:
 ;.byte $c0,$10,$00
;colorcount = (*-colorchoices)-1
default_bg = $c0 ; green

textchoices:
 .byte $08,$0a,$0c,$0e
textcount = (*-textchoices)-1
default_text = textcount-1 ; 2nd brightest is default

wait1jiffy:
 lda RTCLOK+2
wait:
 cmp RTCLOK+2
 beq wait
 rts

; this is needed to prevent the DL from crossing a 1K boundary.
filler:
 .repeat 5
  .byte $aa
 .endrepeat

; since the screen data crosses a 4K boundary, we have to
; include a LMS. screendata needs to be on a 32-byte boundary for
; these calculations to work.
 .if(screendata .mod $20)
  .error "screendata must be on a 32-byte boundary!"
 .endif

totalscanlines = 184 ; aka image size / $20
topscanlines = (($1000 - (screendata .mod $1000)) / $20)
bottomscanlines = (totalscanlines - topscanlines)

 .out .sprintf("topscanlines = %d", topscanlines)
 .out .sprintf("bottomscanlines = %d", bottomscanlines)

; if the display list crosses a 1K boundary, it needs to contain a
; jmp instruction ($01).
 .macro dlbyte arg
  .if((* .mod $400) = $3fd)
   .out .sprintf("emitting DL jump to $%x at $%x", * + 3, *)
   .byte $01
   .word (* + 2)
  .endif
  .byte arg
 .endmacro

 .macro dl3byte ins, arg
  .local bytes
  bytes = $400 - (* .mod $400)
  .if(bytes < 3)
   .error .sprintf("$%x %d: display list dl3byte when <3 bytes left in 1K block, sorry", *, bytes)
  .endif
  .byte ins
  .word arg
 .endmacro

 ; display list here. slightly different display for the xex and
 ; cart versions: the cart has an extra blank scanline just before the
 ; menu GR.0 line, but one less blank at the top (so it comes out the same).
 ; this is really nitpicking, but why not?

dlist:
 dlbyte $70 ; 24 scanlines of blanks
 dlbyte $70
 .ifdef CART_TARGET
 dlbyte $60
 .else
 dlbyte $70
 .endif

 dl3byte $0f | $40, screendata ; LMS, BASIC mode 8
 .repeat topscanlines - 1
  dlbyte $0f ; 127 more scanlines of mode 8
 .endrepeat

 dl3byte $0f | $40, screendata+(topscanlines * $20) ; Hit 4K boundary, LMS again
 .repeat bottomscanlines - 1
  dlbyte $0f ; 55 more scanlines of mode 8
 .endrepeat
 .ifdef CART_TARGET
  dl3byte $01, dl_ram ; DL is mainly in ROM, jump to RAM (extra scanline)
 .else
 ;dlbyte $00 ; extra blank scanline, to match the cart version (removed by request)
 dl3byte $02 | $40, version ; LMS, 1 line of GR.0 for the version
help_lms = * - 2
 dl3byte $41, dlist ; JVB, jump & wait for vblank
 .endif

 .out .sprintf("dl start $%x, end $%x, size %d", dlist, *-1, (* - dlist) + 1)

 .out .sprintf("C code can load at $%x", *)

helpshowing = FR1

; here is where we store N<space> or FF (inverse)
sounddisp = help + 78

 ; executable code here
start:

 .ifdef CART_TARGET
  lda #$42         ; finish display list. this part has to be in RAM,
  sta dl_ram       ; so we can change the LMS target to show the different
  lda #<version    ; lines of help.
  sta help_lms
  lda #>version
  sta help_lms+1
  lda #$41
  sta help_lms+2
  lda #<dlist
  sta help_lms+3
  lda #>dlist
  sta help_lms+4

  ; copy the help text into RAM, where it can be modified.
  ldx #0
@hsloop:
  lda help_rom,x
  sta help,x
  inx
  cpx #help_size
  bne @hsloop
 .endif

 .ifndef CART_TARGET
 ; save old color registers and font addr.
 lda CHBAS
 sta fontsave
 lda COLOR1
 sta color1save
 lda COLOR2
 sta color2save
 .endif

 ; setup color registers
 ;lda colorchoices
 lda #default_bg
 sta COLOR2 ; text bg
 lda textchoices
 sta COLOR1 ; text fg

 ; turn off screen, in case vblank happens while we work
 lda #0
 ;sta FR0 ; why was I doing this?
 sta SDMCTL
 sta sound_disabled ; fix issue with sound not working with APE loader

 ; build our display list
 ; TODO, for now it's hardcoded (see 'dlist' below)

 ; wait for the next frame, to avoid graphics glitching
 jsr wait1jiffy

;; ; For use with explosion.s.pm:
;; ; set player/missiles. we don't use P/M here, it's for the explosion
;; ; sequence, but doing it here is "free" (it doesn't add to the size of
;; ; the main xex segment). also note that we don't enable ANTIC P/M DMA
;; ; (no SDMCTL or GRACTL bits set): the explosion routine writes directly
;; ; to the GRAFP/GRAFM registers.
;;
;; ; colors
;; lda #$0f ; bright white
;; sta PCOLR0
;; sta PCOLR1
;; sta PCOLR2
;; sta PCOLR3
;;
;; ; make sure they're not showing
;; lda #0
;; sta GRAFP0
;; sta GRAFP1
;; sta GRAFP2
;; sta GRAFP3
;; sta GRAFM
;;
;; ; positions
;; lda #$30 ; text columns 0-1
;; sta HPOSM3
;; lda #$38 ; text columns 2-3
;; sta HPOSM2
;; lda #$40 ; 4-5
;; sta HPOSM1
;; lda #$48 ; 6-7
;; sta HPOSM0
;; lda #$50 ; 8-15
;; sta HPOSP0
;; lda #$70 ; 16-23
;; sta HPOSP1
;; lda #$90 ; 24-31
;; sta HPOSP2
;; lda #$B0 ; 32-39
;; sta HPOSP3
;;
;; ; priority
;; lda #8 ; PF 0,1 on top of players (then PF 2,3 on bottom)
;; sta GPRIOR
;;
;; ; width
;; lda #3
;; sta SIZEP0 ; 3 = quad-width
;; sta SIZEP1
;; sta SIZEP2
;; sta SIZEP3
;; lda #$FF
;; sta SIZEM ; FF = quad width, all missiles

 ; save old display list
 ; this is now done in checkmem.s for the .xex build, to avoid
 ; bad interactions with SpartaDOS's TDLINE.
 ; still needs to be done here for the cart.
 .ifdef CART_TARGET
 lda SDLSTL
 sta FRE
 lda SDLSTH
 sta FRE+1
 .endif

 ; helpshowing is FR1, it's being messed with by the checkmem
 ; code so we need to initialize it.
 lda #0
 sta helpshowing

 ; setup our display list
 lda #<dlist
 sta SDLSTL
 lda #>dlist
 sta SDLSTH

 ; switch to narrow playfield, enable screen
 lda #$21
 sta SDMCTL

 ; clear any keypress that happened during loading
 lda #$ff
 sta CH

 ldx #0 ; X = index into bg color choices
 ldy #default_text ; Y = index into text color choices

 ; wait for user to press a key
wait4key:
 ;lda colorchoices,x
 ;sta COLOR2
 lda textchoices,y
 sta COLOR1
 lda CH
 cmp #$ff
 beq wait4key
 cmp #28 ; Escape key
 bne not_esc

 ; show next line of help
showhelp:
 stx FR1+1
 ldx helpshowing
 inx
loadhelp:
 lda helphitbl,x
 bne helpok
 ldx #0
 beq loadhelp
helpok:
 sta help_lms+1
 lda helplotbl,x
 sta help_lms
 stx helpshowing
 ldx FR1+1
 clc
 bcc x_ok

not_esc:
 cmp #62 ; S key
 bne not_s
 jsr enable_disable_sound
 clc
 bcc showhelp

not_s:
 cmp #21 ; B key
 bne not_b
 lda COLOR2
 clc
 adc #$10 ; next hue ($f0 wraps around to $00)
 sta COLOR2
 clc
 bcc x_ok
 ;dex
 ;bpl x_ok
 ;ldx #colorcount
 ;bne x_ok

not_b:
 cmp #45 ; T key
 bne keyok
 dey
 bpl x_ok
 ldy #textcount

x_ok:
 lda #$ff
 sta CH
 bne wait4key

keyok:
 lda CH
 cmp #33 ; space bar
 beq @done
 cmp #12 ; Enter
 bne x_ok

@done:
 ; eat the keypress
 lda #$ff
 sta CH
 rts ; return to DOS (which loads the rest of the game)

enable_disable_sound:
 lda #2
 sta helpshowing
 lda sound_disabled
 eor #$01
 sta sound_disabled
 beq now_on
 lda #166 ; inverse F screen code
 sta sounddisp
 sta sounddisp+1
 rts
now_on:
 lda #174 ; inverse N screen code
 sta sounddisp
 lda #0   ; space screen code
 sta sounddisp+1
 rts

 .out .sprintf("code ends at $%x", *)

end:
 .ifndef CART_TARGET
 .word INITAD
 .word INITAD+1
 .word start
 .endif
