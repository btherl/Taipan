
start = $8000
end = $9fff
 .org start
 .incbin "splitrom.raw.2"

 .if * > end
  .fatal "bank2 code too large"
 .else
  .out .sprintf("=> %d bytes free in bank 2", end - *)
 .endif

 .res end-*+1, $ff
