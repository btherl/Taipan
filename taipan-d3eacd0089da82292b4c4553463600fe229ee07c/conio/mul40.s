; Compatibility wrapper for cc65's mul40 or _mul40 library routine.
; Necessary because cc65 <= 2.17 has "mul40" as part of its atari
; library, but 2.18 and up made it a C-callable routine on all
; platforms, meaning its name grew a _ in front, "_mul40".

; The .VERSION pseudo-variable is documented as "major version
; times $100, plus minor version times $10". Whoever came up with
; this design must have thought the minor version would never exceed
; 15... starting with 2.16, the minor nybble overflows into the major
; one, meaning cc65-2.17's .VERSION is actually $0310. Which is fine,
; so long as there's never a cc65 major version 3.x (if this happens,
; versions 3.0 and 3.1 will fail to build this correctly, then 3.2
; will work again).

.if .VERSION <= $0310 ; $0310 == 2.17
  .import mul40
.else
  .import _mul40
mul40 = _mul40
.endif
