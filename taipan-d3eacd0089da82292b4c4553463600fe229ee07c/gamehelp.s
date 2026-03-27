 .include "atari.inc"

 .import _print_msg, _clrtoeol

 .import _M_help_avail_hk
 .import _M_help_avail_hk_retire
 .import _M_help_buy_sell
 .import _M_help_change_orders
 .import _M_help_doesnt_affect
 .import _M_help_each_gun
 .import _M_help_enter_firm
 .import _M_help_fight
 .import _M_help_for_fun
 .import _M_help_ftr_any
 .import _M_help_if_debt
 .import _M_help_loan_shark
 .import _M_help_may_loan
 .import _M_help_million
 .import _M_help_only_if_total
 .import _M_help_press_a
 .import _M_help_press_m
 .import _M_help_press_k
 .import _M_help_press_ret_done
 .import _M_help_quit_trading
 .import _M_help_press_ret_alone
 .import _M_help_run
 .import _M_help_throw
 .import _M_help_to_sail_to
 .import _M_help_transferred_to
 .import _M_help_turbo
 .import _M_help_type_amount
 .import _M_help_type_letter
 .import _M_help_type_number
 .import _M_help_under_attack
 .import _M_help_wh_bank_only
 .import _M_help_y_or_n

 .export _print_game_help, _game_help
 .export _get_amount_help, _port_choices_help, _port_stat_help_nonhk
 .export _port_stat_help_hk, _name_firm_help, _sea_battle_help
 .export _wu_help, _new_gun_help, _new_ship_help

 ;;; use temps that won't get stepped on by print_msg, cputs, cputc, etc.
 tblptr = FR1+2 ; and +3
 ystash = FR1+4

 .ifdef CART_TARGET
  .segment "HIGHCODE"
 .else
  .code
 .endif

;;; extern void __fastcall__ print_game_help(const char *entry);
;
; Print entire help screen. Caller must ensure the screen gets refreshed
; afterwards (e.g. by calling port_stats()).

 .import _cprintuint

_print_game_help:
 ldx _game_help+1
 beq @ldone
 lda _game_help
 sta tblptr
 stx tblptr+1
 lda #0
 sta ROWCRS
 sta COLCRS
 sta ystash
@loop:
 jsr _clrtoeol
 ldy ystash
 lda (tblptr),y ; high byte!
 beq @ldone
 tax
 iny
 lda (tblptr),y
 iny
 sty ystash
 jsr _print_msg
 jmp @loop
@ldone:
rts

; extern char *game_help;
; set to one of the _<whatever>_help addresses below, or NULL
; if there's no help for the current screen.
 .data
_game_help: .res 2

 .rodata

_get_amount_help:
 .dbyt _M_help_type_amount
 .dbyt _M_help_press_a
 .dbyt _M_help_press_k
 .dbyt _M_help_press_m
 .dbyt _M_help_press_ret_alone
 .byte $00

_port_choices_help:
 .dbyt _M_help_type_number
 .dbyt _M_help_to_sail_to
 .byte $00

_port_stat_help_nonhk:
 .dbyt _M_help_type_letter
 .dbyt _M_help_buy_sell
 .dbyt _M_help_quit_trading
 .dbyt _M_help_wh_bank_only
 .dbyt _M_help_avail_hk
 .byte $00

_port_stat_help_hk:
 .dbyt _M_help_type_letter
 .dbyt _M_help_buy_sell
 .dbyt _M_help_quit_trading
 .dbyt _M_help_wh_bank_only
 .dbyt _M_help_avail_hk_retire
 .dbyt _M_help_only_if_total
 .dbyt _M_help_million
 .byte $00

_name_firm_help:
 .dbyt _M_help_enter_firm
 .dbyt _M_help_doesnt_affect
 .dbyt _M_help_for_fun
 .dbyt _M_help_press_ret_done
 .byte $00

_sea_battle_help:
 .dbyt _M_help_under_attack
 .dbyt _M_help_fight
 .dbyt _M_help_throw
 .dbyt _M_help_run
 .dbyt _M_help_turbo
 .dbyt _M_help_ftr_any
 .dbyt _M_help_change_orders
 .byte $00

_wu_help:
 .dbyt _M_help_loan_shark
 .dbyt _M_help_if_debt
 .dbyt _M_help_may_loan
 .byte $00

_new_gun_help:
 .dbyt _M_help_y_or_n
 .dbyt _M_help_each_gun
 .byte $00

_new_ship_help:
 .dbyt _M_help_y_or_n
 .dbyt _M_help_transferred_to
 .byte $00

