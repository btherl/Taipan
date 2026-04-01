#include <stdio.h>
#include <stdlib.h>

/*
example: 10 / 3

num   denom   quotient    result
10    3       1           0
10    6       2           2
4     3       1           3
*/

/*
	// working, let's simplify it.
int divide(int num, int denom) {
	int result = 0, quotient = 1, newdenom;
	fprintf(stderr, "\tdivide(%d, %d)\n", num, denom);
	do {
		fprintf(stderr, "outer loop\n");
		newdenom = denom;
		quotient = 1;
		if(newdenom > num) {
			fprintf(stderr, "%d > %d: quotient = 0;\n", newdenom, num);
			quotient = 0;
			num = 0;
			// return result;
		} else if(newdenom == num) {
			fprintf(stderr, "%d == %d: quotient = 1;\n", newdenom, num);
			quotient = 1;
			num = 0;
			// return ++result;
		} else {
			while(newdenom <= num) {
				fprintf(stderr, "inner loop %d %d %d\n", num, newdenom, quotient);
				newdenom <<= 1;
				quotient <<= 1;
			}
			newdenom >>= 1;
			num -= newdenom;
			quotient >>= 1;
		}
		result += quotient;
		fprintf(stderr, "num==%d, newdenom==%d, quotient==%d, result==%d\n", num, newdenom, quotient, result);
	} while(num);
	return result;
}
*/

int divide(int num, int denom) {
	int result, quotient, newdenom, halfnum;

	result = 0;
outerloop:
	newdenom = denom;
	quotient = 1;

	if(newdenom < num)
		goto innerprep;
	if(newdenom == num)
		goto innerprep;

	quotient = 0;
	num = 0;
	goto addquot;

innerprep:
	halfnum = num >> 1;

innerloop:
	if(newdenom > halfnum)
		goto innerdone;
	newdenom <<= 1;
	quotient <<= 1;
	goto innerloop;

innerdone:
	num -= newdenom;

addquot:
	result += quotient;
	if(num) goto outerloop;

	return result;
}

/*
	// working, but recursive, doesn't lend itself well to
	// rewriting in asm.
int divide(int num, int denom) {
	int quotient = 1, olddenom = denom;
	fprintf(stderr, "\tdivide(%d, %d)\n", num, denom);
	if(denom > num) return 0;
	if(denom == num) return 1;
	while(denom <= num) {
		denom <<= 1;
		quotient <<= 1;
		fprintf(stderr, "num==%d, denom==%d, quotient==%d\n", num, denom, quotient);
	}
	num -= (denom >> 1);
	return ((quotient >> 1) + divide(num, olddenom));
}
*/

int main(int argc, char **argv) {
	int num = 100, denom = 10, result1, result2;

	if(argc > 1) num = atoi(argv[1]);
	if(argc > 2) denom = atoi(argv[2]);
	result1 = num / denom;
	result2 = divide(num, denom);
	printf("%d / %d == %d\n", num, denom, result1);
	printf("divide(%d, %d) == %d\n", num, denom, result2);
	if(result1 == result2) {
		puts("OK");
		return 0;
	}
	puts("FAIL");
	return 1;
}
