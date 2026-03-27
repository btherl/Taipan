extern void __fastcall__ print_game_help(void);

extern const char *game_help;

extern const char get_amount_help[];
extern const char port_choices_help[];
extern const char name_firm_help[];
extern const char sea_battle_help[];
extern const char wu_help[];
extern const char new_gun_help[];
extern const char new_ship_help[];

#define SET_HELP(x) (game_help = x)
#define CLEAR_HELP  (game_help = (void *)0)
