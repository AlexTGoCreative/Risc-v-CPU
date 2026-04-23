#ifndef __STDIO__
#define __STDIO__

#include <stddef.h>

int getchar(void);
int putchar(int c);
char *gets(char *p,int s);
void putstr(char *p);
int puts(char *p);
int printf(char *fmt,...);
void putx(unsigned);
void putd(int);
int atoi(char *);
int xtoi(char *);

#endif
