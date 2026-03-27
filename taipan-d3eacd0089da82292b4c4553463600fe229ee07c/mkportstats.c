#include <conio.h>
#include <stdio.h>
#include <peekpoke.h>

#define FILENAME "H:PORTSTAT.DAT"

/* 0-based. Set to 1 because we don't include the top
   row (all spaces anyway) */
#define TOPLINE 1

/* Used to be 15, taipan.c now draws the horizontal line itself */
#define LINES 14

void port_stats() {
	cursor(0);
	clrscr();
	chlinexy(1, 1, 26);
	chlinexy(1, 7, 26);
	chlinexy(1, 13, 26);
	cvlinexy(0, 2, 5);
	cvlinexy(27, 2, 5);
	cvlinexy(0, 8, 5);
	cvlinexy(27, 8, 5);
	chlinexy(0, 15, 40);

	cputcxy(0, 1, 17); // upper left corner
	cputcxy(0, 7, 1); // |-
	cputcxy(0, 13, 26); // lower left corner

	cputcxy(27, 1, 5); // upper right corner
	cputcxy(27, 7, 4); // -|
	cputcxy(27, 13, 3); // lower right corner

	cputsxy(1, 2, "Hong Kong Warehouse");
	cputsxy(4, 3, "Opium           In use");
	cputsxy(4, 4, "Silk            ");
	cputsxy(4, 5, "Arms            Vacant");
	cputsxy(4, 6, "General         ");
	cputsxy(1, 8, "Hold ");
	cputsxy(16, 8, "Guns ");

	cputsxy(4, 9,  "Opium   ");
	cputsxy(4, 10, "Silk    ");
	cputsxy(4, 11, "Arms    ");
	cputsxy(4, 12, "General ");
	cputsxy(32, 2, "Date");
	cputsxy(29, 3, "15 "); 

	cputsxy(30, 5, "Location");
	cputsxy(32, 8, "Debt");
	cputsxy(29, 11, "Ship Status");
	cputsxy(0, 14, "Cash: ");
	cputsxy(20, 14, "Bank: ");
	gotoxy(0, 17);
}

void finish(void) {
	printf("You can exit the emulator now.\n");
	while(1)
		;
}

int main(void) {
	char *screenmem = (char *) (PEEK(88)+256*PEEK(89));
	FILE *f = fopen(FILENAME, "wb");
	if(!f) {
		printf("\nCan't create " FILENAME "\n");
		printf("Is the H: device configured?\n");
		finish();
	}
	port_stats();
	fwrite(screenmem + (40 * TOPLINE), 40, LINES, f);
	fclose(f);
	printf("\n" FILENAME " written\n");
	finish();
	return 0;
}
