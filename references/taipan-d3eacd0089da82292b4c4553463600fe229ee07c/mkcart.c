#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

/*
	mkcart.c, by B. Watson, part of DASM Atari 8-bit support.

	DASM and atari800 are both GPLv2 so I've lifted code straight
	from the emulator.

	This is not great C code. It's what happens when I try to write
	C after spending a week hacking assembly code.
 */

/* nobody needs more input files than this, right? I should
	define it to 640K :) */
#define MAX_INPUT_FILES 1024

/* this is the smallest supported cart size */
#define CARTBUFLEN 2048

typedef struct {
	char *name;
	int size;
} cart_t;

/* from atari800-3.1.0/src/cartridge.h */
enum {
	CARTRIDGE_UNKNOWN        = -1,
	CARTRIDGE_NONE           =  0,
	CARTRIDGE_STD_8          =  1,
	CARTRIDGE_STD_16         =  2,
	CARTRIDGE_OSS_034M_16    =  3,
	CARTRIDGE_5200_32        =  4,
	CARTRIDGE_DB_32          =  5,
	CARTRIDGE_5200_EE_16     =  6,
	CARTRIDGE_5200_40        =  7,
	CARTRIDGE_WILL_64        =  8,
	CARTRIDGE_EXP_64         =  9,
	CARTRIDGE_DIAMOND_64     = 10,
	CARTRIDGE_SDX_64         = 11,
	CARTRIDGE_XEGS_32        = 12,
	CARTRIDGE_XEGS_07_64     = 13,
	CARTRIDGE_XEGS_128       = 14,
	CARTRIDGE_OSS_M091_16    = 15,
	CARTRIDGE_5200_NS_16     = 16,
	CARTRIDGE_ATRAX_128      = 17,
	CARTRIDGE_BBSB_40        = 18,
	CARTRIDGE_5200_8         = 19,
	CARTRIDGE_5200_4         = 20,
	CARTRIDGE_RIGHT_8        = 21,
	CARTRIDGE_WILL_32        = 22,
	CARTRIDGE_XEGS_256       = 23,
	CARTRIDGE_XEGS_512       = 24,
	CARTRIDGE_XEGS_1024      = 25,
	CARTRIDGE_MEGA_16        = 26,
	CARTRIDGE_MEGA_32        = 27,
	CARTRIDGE_MEGA_64        = 28,
	CARTRIDGE_MEGA_128       = 29,
	CARTRIDGE_MEGA_256       = 30,
	CARTRIDGE_MEGA_512       = 31,
	CARTRIDGE_MEGA_1024      = 32,
	CARTRIDGE_SWXEGS_32      = 33,
	CARTRIDGE_SWXEGS_64      = 34,
	CARTRIDGE_SWXEGS_128     = 35,
	CARTRIDGE_SWXEGS_256     = 36,
	CARTRIDGE_SWXEGS_512     = 37,
	CARTRIDGE_SWXEGS_1024    = 38,
	CARTRIDGE_PHOENIX_8      = 39,
	CARTRIDGE_BLIZZARD_16    = 40,
	CARTRIDGE_ATMAX_128      = 41,
	CARTRIDGE_ATMAX_1024     = 42,
	CARTRIDGE_SDX_128        = 43,
	CARTRIDGE_OSS_8          = 44,
	CARTRIDGE_OSS_043M_16    = 45,
	CARTRIDGE_BLIZZARD_4     = 46,
	CARTRIDGE_AST_32         = 47,
	CARTRIDGE_ATRAX_SDX_64   = 48,
	CARTRIDGE_ATRAX_SDX_128  = 49,
	CARTRIDGE_TURBOSOFT_64   = 50,
	CARTRIDGE_TURBOSOFT_128  = 51,
	CARTRIDGE_ULTRACART_32   = 52,
	CARTRIDGE_LOW_BANK_8     = 53,
	CARTRIDGE_SIC_128        = 54,
	CARTRIDGE_SIC_256        = 55,
	CARTRIDGE_SIC_512        = 56,
	CARTRIDGE_STD_2          = 57,
	CARTRIDGE_STD_4          = 58,
	CARTRIDGE_RIGHT_4        = 59,
	CARTRIDGE_BLIZZARD_32    = 60,
	CARTRIDGE_MEGAMAX_2048   = 61,
	CARTRIDGE_THECART_128M   = 62,
	CARTRIDGE_MEGA_4096      = 63,
	CARTRIDGE_MEGA_2048      = 64,
	CARTRIDGE_THECART_32M    = 65,
	CARTRIDGE_THECART_64M    = 66,
	CARTRIDGE_XEGS_8F_64     = 67,
	CARTRIDGE_LAST_SUPPORTED = 67
};

#define CARTRIDGE_MAX_SIZE	(128 * 1024 * 1024)

#define CARTRIDGE_STD_8_DESC         "Standard 8 KB cartridge"
#define CARTRIDGE_STD_16_DESC        "Standard 16 KB cartridge"
#define CARTRIDGE_OSS_034M_16_DESC   "OSS two chip 16 KB cartridge (034M)"
#define CARTRIDGE_5200_32_DESC       "Standard 32 KB 5200 cartridge"
#define CARTRIDGE_DB_32_DESC         "DB 32 KB cartridge"
#define CARTRIDGE_5200_EE_16_DESC    "Two chip 16 KB 5200 cartridge"
#define CARTRIDGE_5200_40_DESC       "Bounty Bob 40 KB 5200 cartridge"
#define CARTRIDGE_WILL_64_DESC       "64 KB Williams cartridge"
#define CARTRIDGE_EXP_64_DESC        "Express 64 KB cartridge"
#define CARTRIDGE_DIAMOND_64_DESC    "Diamond 64 KB cartridge"
#define CARTRIDGE_SDX_64_DESC        "SpartaDOS X 64 KB cartridge"
#define CARTRIDGE_XEGS_32_DESC       "XEGS 32 KB cartridge"
#define CARTRIDGE_XEGS_07_64_DESC    "XEGS 64 KB cartridge (banks 0-7)"
#define CARTRIDGE_XEGS_128_DESC      "XEGS 128 KB cartridge"
#define CARTRIDGE_OSS_M091_16_DESC   "OSS one chip 16 KB cartridge"
#define CARTRIDGE_5200_NS_16_DESC    "One chip 16 KB 5200 cartridge"
#define CARTRIDGE_ATRAX_128_DESC     "Atrax 128 KB cartridge"
#define CARTRIDGE_BBSB_40_DESC       "Bounty Bob 40 KB cartridge"
#define CARTRIDGE_5200_8_DESC        "Standard 8 KB 5200 cartridge"
#define CARTRIDGE_5200_4_DESC        "Standard 4 KB 5200 cartridge"
#define CARTRIDGE_RIGHT_8_DESC       "Right slot 8 KB cartridge"
#define CARTRIDGE_WILL_32_DESC       "32 KB Williams cartridge"
#define CARTRIDGE_XEGS_256_DESC      "XEGS 256 KB cartridge"
#define CARTRIDGE_XEGS_512_DESC      "XEGS 512 KB cartridge"
#define CARTRIDGE_XEGS_1024_DESC     "XEGS 1 MB cartridge"
#define CARTRIDGE_MEGA_16_DESC       "MegaCart 16 KB cartridge"
#define CARTRIDGE_MEGA_32_DESC       "MegaCart 32 KB cartridge"
#define CARTRIDGE_MEGA_64_DESC       "MegaCart 64 KB cartridge"
#define CARTRIDGE_MEGA_128_DESC      "MegaCart 128 KB cartridge"
#define CARTRIDGE_MEGA_256_DESC      "MegaCart 256 KB cartridge"
#define CARTRIDGE_MEGA_512_DESC      "MegaCart 512 KB cartridge"
#define CARTRIDGE_MEGA_1024_DESC     "MegaCart 1 MB cartridge"
#define CARTRIDGE_SWXEGS_32_DESC     "Switchable XEGS 32 KB cartridge"
#define CARTRIDGE_SWXEGS_64_DESC     "Switchable XEGS 64 KB cartridge"
#define CARTRIDGE_SWXEGS_128_DESC    "Switchable XEGS 128 KB cartridge"
#define CARTRIDGE_SWXEGS_256_DESC    "Switchable XEGS 256 KB cartridge"
#define CARTRIDGE_SWXEGS_512_DESC    "Switchable XEGS 512 KB cartridge"
#define CARTRIDGE_SWXEGS_1024_DESC   "Switchable XEGS 1 MB cartridge"
#define CARTRIDGE_PHOENIX_8_DESC     "Phoenix 8 KB cartridge"
#define CARTRIDGE_BLIZZARD_16_DESC   "Blizzard 16 KB cartridge"
#define CARTRIDGE_ATMAX_128_DESC     "Atarimax 128 KB Flash cartridge"
#define CARTRIDGE_ATMAX_1024_DESC    "Atarimax 1 MB Flash cartridge"
#define CARTRIDGE_SDX_128_DESC       "SpartaDOS X 128 KB cartridge"
#define CARTRIDGE_OSS_8_DESC         "OSS 8 KB cartridge"
#define CARTRIDGE_OSS_043M_16_DESC   "OSS two chip 16 KB cartridge (043M)"
#define CARTRIDGE_BLIZZARD_4_DESC    "Blizzard 4 KB cartridge"
#define CARTRIDGE_AST_32_DESC        "AST 32 KB cartridge"
#define CARTRIDGE_ATRAX_SDX_64_DESC  "Atrax SDX 64 KB cartridge"
#define CARTRIDGE_ATRAX_SDX_128_DESC "Atrax SDX 128 KB cartridge"
#define CARTRIDGE_TURBOSOFT_64_DESC  "Turbosoft 64 KB cartridge"
#define CARTRIDGE_TURBOSOFT_128_DESC "Turbosoft 128 KB cartridge"
#define CARTRIDGE_ULTRACART_32_DESC  "Ultracart 32 KB cartridge"
#define CARTRIDGE_LOW_BANK_8_DESC    "Low bank 8 KB cartridge"
#define CARTRIDGE_SIC_128_DESC       "SIC! 128 KB cartridge"
#define CARTRIDGE_SIC_256_DESC       "SIC! 256 KB cartridge"
#define CARTRIDGE_SIC_512_DESC       "SIC! 512 KB cartridge"
#define CARTRIDGE_STD_2_DESC         "Standard 2 KB cartridge"
#define CARTRIDGE_STD_4_DESC         "Standard 4 KB cartridge"
#define CARTRIDGE_RIGHT_4_DESC       "Right slot 4 KB cartridge"
#define CARTRIDGE_BLIZZARD_32_DESC   "Blizzard 32 KB cartridge"
#define CARTRIDGE_MEGAMAX_2048_DESC  "MegaMax 2 MB cartridge"
#define CARTRIDGE_THECART_128M_DESC  "The!Cart 128 MB cartridge"
#define CARTRIDGE_MEGA_4096_DESC     "Flash MegaCart 4 MB cartridge"
#define CARTRIDGE_MEGA_2048_DESC     "MegaCart 2 MB cartridge"
#define CARTRIDGE_THECART_32M_DESC   "The!Cart 32 MB cartridge"
#define CARTRIDGE_THECART_64M_DESC   "The!Cart 64 MB cartridge"
#define CARTRIDGE_XEGS_8F_64_DESC    "XEGS 64 KB cartridge (banks 8-15)"

/* this bit didn't come from atari800 */
static cart_t cart_types[CARTRIDGE_LAST_SUPPORTED + 1];
#define UI_MENU_ACTION(index, desc) \
	cart_types[index].size = CARTRIDGE_kb[index]*1024; \
	cart_types[index].name = desc;

/* from atari800-3.1.0/src/cartridge.c */
int const CARTRIDGE_kb[CARTRIDGE_LAST_SUPPORTED + 1] = {
	0,
	8,        /* CARTRIDGE_STD_8 */
	16,       /* CARTRIDGE_STD_16 */
	16,       /* CARTRIDGE_OSS_034M_16 */
	32,       /* CARTRIDGE_5200_32 */
	32,       /* CARTRIDGE_DB_32 */
	16,       /* CARTRIDGE_5200_EE_16 */
	40,       /* CARTRIDGE_5200_40 */
	64,       /* CARTRIDGE_WILL_64 */
	64,       /* CARTRIDGE_EXP_64 */
	64,       /* CARTRIDGE_DIAMOND_64 */
	64,       /* CARTRIDGE_SDX_64 */
	32,       /* CARTRIDGE_XEGS_32 */
	64,       /* CARTRIDGE_XEGS_64_07 */
	128,      /* CARTRIDGE_XEGS_128 */
	16,       /* CARTRIDGE_OSS_M091_16 */
	16,       /* CARTRIDGE_5200_NS_16 */
	128,      /* CARTRIDGE_ATRAX_128 */
	40,       /* CARTRIDGE_BBSB_40 */
	8,        /* CARTRIDGE_5200_8 */
	4,        /* CARTRIDGE_5200_4 */
	8,        /* CARTRIDGE_RIGHT_8 */
	32,       /* CARTRIDGE_WILL_32 */
	256,      /* CARTRIDGE_XEGS_256 */
	512,      /* CARTRIDGE_XEGS_512 */
	1024,     /* CARTRIDGE_XEGS_1024 */
	16,       /* CARTRIDGE_MEGA_16 */
	32,       /* CARTRIDGE_MEGA_32 */
	64,       /* CARTRIDGE_MEGA_64 */
	128,      /* CARTRIDGE_MEGA_128 */
	256,      /* CARTRIDGE_MEGA_256 */
	512,      /* CARTRIDGE_MEGA_512 */
	1024,     /* CARTRIDGE_MEGA_1024 */
	32,       /* CARTRIDGE_SWXEGS_32 */
	64,       /* CARTRIDGE_SWXEGS_64 */
	128,      /* CARTRIDGE_SWXEGS_128 */
	256,      /* CARTRIDGE_SWXEGS_256 */
	512,      /* CARTRIDGE_SWXEGS_512 */
	1024,     /* CARTRIDGE_SWXEGS_1024 */
	8,        /* CARTRIDGE_PHOENIX_8 */
	16,       /* CARTRIDGE_BLIZZARD_16 */
	128,      /* CARTRIDGE_ATMAX_128 */
	1024,     /* CARTRIDGE_ATMAX_1024 */
	128,      /* CARTRIDGE_SDX_128 */
	8,        /* CARTRIDGE_OSS_8 */
	16,       /* CARTRIDGE_OSS_043M_16 */
	4,        /* CARTRIDGE_BLIZZARD_4 */
	32,       /* CARTRIDGE_AST_32 */
	64,       /* CARTRIDGE_ATRAX_SDX_64 */
	128,      /* CARTRIDGE_ATRAX_SDX_128 */
	64,       /* CARTRIDGE_TURBOSOFT_64 */
	128,      /* CARTRIDGE_TURBOSOFT_128 */
	32,       /* CARTRIDGE_ULTRACART_32 */
	8,        /* CARTRIDGE_LOW_BANK_8 */
	128,      /* CARTRIDGE_SIC_128 */
	256,      /* CARTRIDGE_SIC_256 */
	512,      /* CARTRIDGE_SIC_512 */
	2,        /* CARTRIDGE_STD_2 */
	4,        /* CARTRIDGE_STD_4 */
	4,        /* CARTRIDGE_RIGHT_4 */
	32,       /* CARTRIDGE_TURBO_HIT_32 */
	2048,     /* CARTRIDGE_MEGA_2048 */
	128*1024, /* CARTRIDGE_THECART_128M */
	4096,     /* CARTRIDGE_MEGA_4096 */
	2048,     /* CARTRIDGE_MEGA_2048 */
	32*1024,  /* CARTRIDGE_THECART_32M */
	64*1024,  /* CARTRIDGE_THECART_64M */
	64        /* CARTRIDGE_XEGS_64_8F */
};

/* Adapted from from atari800-3.1.0/src/ui.c, by s/,$/;/ */
void init() {
		UI_MENU_ACTION(CARTRIDGE_STD_8, CARTRIDGE_STD_8_DESC);
		UI_MENU_ACTION(CARTRIDGE_STD_16, CARTRIDGE_STD_16_DESC);
		UI_MENU_ACTION(CARTRIDGE_OSS_034M_16, CARTRIDGE_OSS_034M_16_DESC);
		UI_MENU_ACTION(CARTRIDGE_5200_32, CARTRIDGE_5200_32_DESC);
		UI_MENU_ACTION(CARTRIDGE_DB_32, CARTRIDGE_DB_32_DESC);
		UI_MENU_ACTION(CARTRIDGE_5200_EE_16, CARTRIDGE_5200_EE_16_DESC);
		UI_MENU_ACTION(CARTRIDGE_5200_40, CARTRIDGE_5200_40_DESC);
		UI_MENU_ACTION(CARTRIDGE_WILL_64, CARTRIDGE_WILL_64_DESC);
		UI_MENU_ACTION(CARTRIDGE_EXP_64, CARTRIDGE_EXP_64_DESC);
		UI_MENU_ACTION(CARTRIDGE_DIAMOND_64, CARTRIDGE_DIAMOND_64_DESC);
		UI_MENU_ACTION(CARTRIDGE_SDX_64, CARTRIDGE_SDX_64_DESC);
		UI_MENU_ACTION(CARTRIDGE_XEGS_32, CARTRIDGE_XEGS_32_DESC);
		UI_MENU_ACTION(CARTRIDGE_XEGS_07_64, CARTRIDGE_XEGS_07_64_DESC);
		UI_MENU_ACTION(CARTRIDGE_XEGS_128, CARTRIDGE_XEGS_128_DESC);
		UI_MENU_ACTION(CARTRIDGE_OSS_M091_16, CARTRIDGE_OSS_M091_16_DESC);
		UI_MENU_ACTION(CARTRIDGE_5200_NS_16, CARTRIDGE_5200_NS_16_DESC);
		UI_MENU_ACTION(CARTRIDGE_ATRAX_128, CARTRIDGE_ATRAX_128_DESC);
		UI_MENU_ACTION(CARTRIDGE_BBSB_40, CARTRIDGE_BBSB_40_DESC);
		UI_MENU_ACTION(CARTRIDGE_5200_8, CARTRIDGE_5200_8_DESC);
		UI_MENU_ACTION(CARTRIDGE_5200_4, CARTRIDGE_5200_4_DESC);
		UI_MENU_ACTION(CARTRIDGE_RIGHT_8, CARTRIDGE_RIGHT_8_DESC);
		UI_MENU_ACTION(CARTRIDGE_WILL_32, CARTRIDGE_WILL_32_DESC);
		UI_MENU_ACTION(CARTRIDGE_XEGS_256, CARTRIDGE_XEGS_256_DESC);
		UI_MENU_ACTION(CARTRIDGE_XEGS_512, CARTRIDGE_XEGS_512_DESC);
		UI_MENU_ACTION(CARTRIDGE_XEGS_1024, CARTRIDGE_XEGS_1024_DESC);
		UI_MENU_ACTION(CARTRIDGE_MEGA_16, CARTRIDGE_MEGA_16_DESC);
		UI_MENU_ACTION(CARTRIDGE_MEGA_32, CARTRIDGE_MEGA_32_DESC);
		UI_MENU_ACTION(CARTRIDGE_MEGA_64, CARTRIDGE_MEGA_64_DESC);
		UI_MENU_ACTION(CARTRIDGE_MEGA_128, CARTRIDGE_MEGA_128_DESC);
		UI_MENU_ACTION(CARTRIDGE_MEGA_256, CARTRIDGE_MEGA_256_DESC);
		UI_MENU_ACTION(CARTRIDGE_MEGA_512, CARTRIDGE_MEGA_512_DESC);
		UI_MENU_ACTION(CARTRIDGE_MEGA_1024, CARTRIDGE_MEGA_1024_DESC);
		UI_MENU_ACTION(CARTRIDGE_SWXEGS_32, CARTRIDGE_SWXEGS_32_DESC);
		UI_MENU_ACTION(CARTRIDGE_SWXEGS_64, CARTRIDGE_SWXEGS_64_DESC);
		UI_MENU_ACTION(CARTRIDGE_SWXEGS_128, CARTRIDGE_SWXEGS_128_DESC);
		UI_MENU_ACTION(CARTRIDGE_SWXEGS_256, CARTRIDGE_SWXEGS_256_DESC);
		UI_MENU_ACTION(CARTRIDGE_SWXEGS_512, CARTRIDGE_SWXEGS_512_DESC);
		UI_MENU_ACTION(CARTRIDGE_SWXEGS_1024, CARTRIDGE_SWXEGS_1024_DESC);
		UI_MENU_ACTION(CARTRIDGE_PHOENIX_8, CARTRIDGE_PHOENIX_8_DESC);
		UI_MENU_ACTION(CARTRIDGE_BLIZZARD_16, CARTRIDGE_BLIZZARD_16_DESC);
		UI_MENU_ACTION(CARTRIDGE_ATMAX_128, CARTRIDGE_ATMAX_128_DESC);
		UI_MENU_ACTION(CARTRIDGE_ATMAX_1024, CARTRIDGE_ATMAX_1024_DESC);
		UI_MENU_ACTION(CARTRIDGE_SDX_128, CARTRIDGE_SDX_128_DESC);
		UI_MENU_ACTION(CARTRIDGE_OSS_8, CARTRIDGE_OSS_8_DESC);
		UI_MENU_ACTION(CARTRIDGE_OSS_043M_16, CARTRIDGE_OSS_043M_16_DESC);
		UI_MENU_ACTION(CARTRIDGE_BLIZZARD_4, CARTRIDGE_BLIZZARD_4_DESC);
		UI_MENU_ACTION(CARTRIDGE_AST_32, CARTRIDGE_AST_32_DESC);
		UI_MENU_ACTION(CARTRIDGE_ATRAX_SDX_64, CARTRIDGE_ATRAX_SDX_64_DESC);
		UI_MENU_ACTION(CARTRIDGE_ATRAX_SDX_128, CARTRIDGE_ATRAX_SDX_128_DESC);
		UI_MENU_ACTION(CARTRIDGE_TURBOSOFT_64, CARTRIDGE_TURBOSOFT_64_DESC);
		UI_MENU_ACTION(CARTRIDGE_TURBOSOFT_128, CARTRIDGE_TURBOSOFT_128_DESC);
		UI_MENU_ACTION(CARTRIDGE_ULTRACART_32, CARTRIDGE_ULTRACART_32_DESC);
		UI_MENU_ACTION(CARTRIDGE_LOW_BANK_8, CARTRIDGE_LOW_BANK_8_DESC);
		UI_MENU_ACTION(CARTRIDGE_SIC_128, CARTRIDGE_SIC_128_DESC);
		UI_MENU_ACTION(CARTRIDGE_SIC_256, CARTRIDGE_SIC_256_DESC);
		UI_MENU_ACTION(CARTRIDGE_SIC_512, CARTRIDGE_SIC_512_DESC);
		UI_MENU_ACTION(CARTRIDGE_STD_2, CARTRIDGE_STD_2_DESC);
		UI_MENU_ACTION(CARTRIDGE_STD_4, CARTRIDGE_STD_4_DESC);
		UI_MENU_ACTION(CARTRIDGE_RIGHT_4, CARTRIDGE_RIGHT_4_DESC);
		UI_MENU_ACTION(CARTRIDGE_BLIZZARD_32, CARTRIDGE_BLIZZARD_32_DESC);
		UI_MENU_ACTION(CARTRIDGE_MEGAMAX_2048, CARTRIDGE_MEGAMAX_2048_DESC);
		UI_MENU_ACTION(CARTRIDGE_THECART_128M, CARTRIDGE_THECART_128M_DESC);
		UI_MENU_ACTION(CARTRIDGE_MEGA_4096, CARTRIDGE_MEGA_4096_DESC);
		UI_MENU_ACTION(CARTRIDGE_MEGA_2048, CARTRIDGE_MEGA_2048_DESC);
		UI_MENU_ACTION(CARTRIDGE_THECART_32M, CARTRIDGE_THECART_32M_DESC);
		UI_MENU_ACTION(CARTRIDGE_THECART_64M, CARTRIDGE_THECART_64M_DESC);
		UI_MENU_ACTION(CARTRIDGE_XEGS_8F_64, CARTRIDGE_XEGS_8F_64_DESC);
}

static int type = -1; /* -1 = guess */
static int extracting = 0;
static const char *outfile = NULL;
static FILE *output;
static const char *inputfiles[MAX_INPUT_FILES+1];
static int inputcount = 0;
static int checksum = 0;
static int keep_outfile = 0;
static unsigned char buf[CARTBUFLEN];

void list_types() {
	int i;
	for(i = 1; i <= CARTRIDGE_LAST_SUPPORTED; i++) {
		printf("%d %d %s\n", i, cart_types[i].size, cart_types[i].name);
	}
}

void usage() {
	puts("mkcart v20150421 - create atari800 CART image from raw binaries");
	puts("\nUsage: mkcart -oCARTFILE -tTYPE RAWFILE [RAWFILE ...]");
	puts(  "       mkcart -cCARTFILE");
	puts(  "       mkcart -xRAWFILE CARTFILE");
	puts(  "       mkcart -l");
	printf("\n  -tTYPE       Cartridge type (1-%d), default = guess (poorly!)\n",
			CARTRIDGE_LAST_SUPPORTED);
	puts(    "  -oCARTFILE   Create CARTFILE from RAWFILE(s)");
	puts(    "  -cCARTFILE   Check integrity of file (checksum and size)");
	puts(    "  -xRAWFILE    Create raw binary from CARTFILE (remove header)");
	puts(    "  -l           List all supported -t types and exit");
	puts(    "  -h, -?       This help message");
}

void open_output() {
	if(!outfile) {
		fprintf(stderr, "No output file given, use -o option\n");
		exit(1);
	}
	if( !(output = fopen(outfile, "wb")) ) {
		perror(outfile);
		exit(1);
	}
}

FILE *open_input(const char *fname) {
	FILE *f;

	f = fopen(fname, "rb");
	if(!f) {
		perror(fname);
		exit(1);
	}
	return f;
}

int has_cart_header(const unsigned char *b) {
	return ( (buf[0] == 'C') &&
	         (buf[1] == 'A') &&
	         (buf[2] == 'R') &&
	         (buf[3] == 'T') );
}

void write_header() {
	int i, j, size = 0, checkhdr;
	FILE *f;
	size_t got;

	for(i = 0; i < inputcount; i++) {
		 f = open_input(inputfiles[i]);

		 if(extracting) {
			 /* read and check header insead of writing one */
			 if(fread(buf, 1, 16, f) < 16) {
				 perror(inputfiles[i]);
				 exit(-1);
			 }
			 if(!has_cart_header(buf)) {
				 fprintf(stderr, "%s doesn't have a CART header\n", inputfiles[i]);
				 exit(-1);
			 }
			 return;
		 }

		 checkhdr = 1;

		 while( (got = fread(buf, 1, CARTBUFLEN, f)) > 0) {
			 if(checkhdr) { /* only do this on first chunk read */
				 if(has_cart_header(buf)) {
					 fprintf(stderr,
							 "warning: raw file %s appears to have a CART header\n",
							 inputfiles[i]);
				 }
				 checkhdr = 0;
			 }
			 if(got < CARTBUFLEN) {
				 fprintf(stderr, "warning: %s size not a multiple of %d bytes\n",
						 inputfiles[i], CARTBUFLEN);
			 }
			 for(j = 0; j < got; j++) checksum += buf[j];
			 size += got;
		 }
		 if(ferror(f)) {
			 perror(inputfiles[i]);
			 exit(1);
		 }
		 fclose(f);
	}

	if(type > 0 && size != cart_types[type].size) {
		fprintf(stderr,
				"warning: cart type %d (%s) must be %d bytes, "
				"but we read %d from our input files\n",
				type, cart_types[type].name, cart_types[type].size, size);
	}

	if(type < 1) {
		for(i = 1; i <= CARTRIDGE_LAST_SUPPORTED; i++) {
			if(size == (cart_types[i].size)) {
				type = i;
				fprintf(stderr, "warning: no -t option, guessing type %d (%s)\n",
						i, cart_types[i].name);
				break;
			}
		}
		if(type < 1) {
			fprintf(stderr,
					"fatal: no -t option, no type matches file size %d bytes\n",
					size);
			exit(-1);
		}
	}

	/* more like assembly than C, but it avoids endian issues */
	buf[0] = 'C';
	buf[1] = 'A';
	buf[2] = 'R';
	buf[3] = 'T';
	buf[4] = buf[5] = buf[6] = 0;
	buf[7] = type;
	buf[8] = (checksum >> 24) & 0xff;
	buf[9] = (checksum >> 16) & 0xff;
	buf[10] = (checksum >> 8) & 0xff;
	buf[11] = checksum  & 0xff;
	buf[12] = buf[13] = buf[14] = buf[15] = 0;

	i = fwrite(buf, 1, 16, output);
	if(i < 0) {
		perror(outfile);
		exit(-1);
	} else if(i < 16) {
		fprintf(stderr, "short write on %s\n", outfile);
		exit(-1);
	}
	/* leave output open here */
}

void write_data() {
	int i;
	FILE *f;
	size_t got;

	for(i = 0; i < inputcount; i++) {
		 f = open_input(inputfiles[i]);
		 if(extracting) fread(buf, 1, 16, f); /* skip header */
		 while( (got = fread(buf, 1, CARTBUFLEN, f)) > 0) {
			 if( (fwrite(buf, 1, got, output)) < got ) {
				 perror(outfile);
				 exit(-1);
			 }
		 }
		 if(ferror(f)) {
			 perror(inputfiles[i]);
			 exit(1);
		 }
		 fclose(f);
	}

	/* if we made it here with no errors, the output file is good */
	keep_outfile = 1;
}

void add_file(const char *filename) {
	if(inputcount > MAX_INPUT_FILES) {
		fprintf(stderr, "Too many input files (limit is %d, sorry)\n",
				MAX_INPUT_FILES);
		exit(1);
	}
	inputfiles[inputcount++] = filename;
}

int extract4(const unsigned char *b) {
	return ( (b[0] << 24) |
	         (b[1] << 16) |
	         (b[2] <<  8) |
	         (b[3]      ) );
}

void check_file(const char *filename) {
	int j, hdr_checksum, hdr_type, hdr_unused, ok = 1;
	FILE *f;
	int got, size, hdr_size;

	f = open_input(filename);
	got = fread(buf, 1, 16, f);
	if(got < 0) {
		perror(filename);
		exit(1);
	} else if(got < 16) {
		fprintf(stderr, "%s is only %d bytes long, not a valid CART\n",
				filename, (int)got);
		exit(1);
	}

	if(!has_cart_header(buf)) {
		fprintf(stderr, "%s missing CART header\n", filename);
		exit(1);
	}

	printf("%s has CART header\n", filename);

	hdr_type = extract4(buf + 4);
	hdr_checksum = extract4(buf + 8);
	hdr_unused = extract4(buf + 12);

	if(hdr_type < 1 || hdr_type > CARTRIDGE_LAST_SUPPORTED) {
		fprintf(stderr, "%s has invalid cart type %d (should be 1-%d)\n",
				filename, hdr_type, CARTRIDGE_LAST_SUPPORTED);
		exit(1);
	}

	printf("%s is type %d: %s (%d bytes)\n",
			filename, hdr_type, cart_types[hdr_type].name, cart_types[hdr_type].size);

	if(hdr_unused) {
		fprintf(stderr, "warning: %s unused area in CART header is non-zero\n", filename);
	}

	hdr_size = CARTRIDGE_kb[hdr_type] * 1024;

	while( (got = fread(buf, 1, CARTBUFLEN, f)) > 0) {
		if(got < CARTBUFLEN) {
			fprintf(stderr, "warning: %s data size not a multiple of %d bytes\n",
					filename, CARTBUFLEN);
		}
		for(j = 0; j < got; j++) checksum += buf[j];
		size += got;
	}
	if(ferror(f)) {
		perror(filename);
		exit(1);
	}
	fclose(f);

	if(size != hdr_size) {
		ok = 0;
		fprintf(stderr,
				"%s header says the data size should be %d bytes, but we read %d, ",
				filename, hdr_size, size);
	}

	if(size > hdr_size) {
		fprintf(stderr, "junk at the end? downloaded in ASCII mode?\n");
	} else if(size < hdr_size) {
		fprintf(stderr, "truncated?\n");
	} else {
		printf("%s has correct data size, %d bytes\n", filename, size);
	}

	if(hdr_checksum == checksum) {
		printf("%s has valid checksum\n", filename);
	} else {
		ok = 0;
		fprintf(stderr, "%s has BAD checksum\n", filename);
	}

	printf("%s results: %s\n", filename, (ok ? "OK" : "FAILED"));
	exit(!ok);
}

void cleanup() {
	if(outfile && !keep_outfile) unlink(outfile); /* ignore error here */
}

int main(int argc, char **argv) {
	init();
	atexit(cleanup);

	if(argc < 2) {
		usage();
		exit(0);
	}

	while(++argv, --argc > 0) {
		if(argv[0][0] == '-') {
			switch(argv[0][1]) {
				case 'l':
					list_types();
					exit(0);
					break;

				case 't':
					type = atoi(&argv[0][2]);
					if(type < 1 || type > CARTRIDGE_LAST_SUPPORTED) {
						fprintf(stderr, "Invalid -t, use -t1 thru -t%d (not -t 1)\n\n",
								CARTRIDGE_LAST_SUPPORTED);
						usage();
						exit(1);
					}
					break;

				case 'o':
					if(argv[0][2]) {
						outfile = &argv[0][2];
					} else {
						fprintf(stderr, "Invalid -o, use -ofilename (not -o filename)\n\n");
						exit(1);
					}
					break;

				case 'x':
					if(argv[0][2]) {
						outfile = &argv[0][2];
						extracting = 1;
					} else {
						fprintf(stderr, "Invalid -x, use -xfilename (not -x filename)\n\n");
						exit(1);
					}
					break;

				case 'c':
					if(argv[0][2]) {
						check_file(&argv[0][2]); /* exits */
					} else {
						fprintf(stderr, "Invalid -c, use -cfilename (not -c filename)\n\n");
						exit(1);
					}
					break;

				case 'h':
				case '?':
					usage();
					exit(0);
					break;

				default:
					fprintf(stderr, "Invalid option %s\n\n", *argv);
					usage();
					exit(1);
					break;
			}
		} else { /* argv[0][0] != '-' */
			add_file(*argv);
		}
	}

	open_output();
	write_header();
	write_data();
	exit(0);
}
