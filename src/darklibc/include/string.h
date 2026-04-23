#ifndef __STRING__
#define __STRING__

char *strcpy(char *s1, char *s2);
char *strncpy(char *s1, char *s2, int len);

int strcmp(char *s1, char *s2);
int strncmp(char *s1, char *s2, int len);
int strlen(char *s1);

char *memcpy(char *dptr,char *sptr,int len);
char *memcmp(char *dptr,char *sptr,int len);
char *memset(char *dptr, int c, int len);
char *strtok(char *str,char *dptr);

#endif
