#include <conio.h>
#include <peekpoke.h>

char turbo;
extern void __fastcall__ damage_lorcha(int which);
extern void __fastcall__ draw_lorcha(int which);
extern void __fastcall__ flash_lorcha(int which);
extern void __fastcall__ clear_lorcha(int which);
extern void __fastcall__ sink_lorcha(int which);

int main(void) {
	int i, j;
	POKE(756, 0xb8);
	for(i=0; i<10; i++) {
		// draw_lorcha(i);
		// cgetc();
		// clear_lorcha(i);
		// cgetc();
		draw_lorcha(i);
		cgetc();
		sink_lorcha(i);
		cgetc();
		draw_lorcha(i);
		for(j=0; j<5; j++) {
			cgetc();
			flash_lorcha(i);
			cgetc();
			flash_lorcha(i);
			cgetc();
			damage_lorcha(i);
		}
	}
}
