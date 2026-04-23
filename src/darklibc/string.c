#include <string.h>
#include <stddef.h>

// string manipulation

char *strncpy(char *s1,char *s2,int len)
{
    char *ret = s1;

    while(--len && (*s1++=*s2++));
    
    return ret;
}


char *strcpy(char *s1,char *s2)
{
    return strncpy(s1,s2,-1);
}

int strncmp(char *s1,char *s2,int len)
{
    while(--len && *s1 && *s2 && (*s1==*s2)) s1++, s2++;
    
    return (*s1-*s2);
}

int strcmp(char *s1, char *s2)
{
    return strncmp(s1,s2,-1);
}

int strlen(char *s1)
{
    int len;
    
    for(len=0;s1&&*s1++;len++);

    return len;
}

char *strtok(char *str,char *dptr)
{
    static char *nxt = NULL;

    int dlen = strlen(dptr);
    char *tmp;

         if(str) tmp=str;
    else if(nxt) tmp=nxt;
    else return NULL;
    
    char *ret=tmp;

    while(*tmp)
    {
        if(strncmp(tmp,dptr,dlen)==0)
        {
            *tmp=NUL;
            nxt = tmp+1;
            return ret;
        }
        tmp++;
    }
    nxt = NULL;
    return ret;
}

// memory manipulation

char *memcpy(char *dptr,char *sptr,int len)
{
    char *ret = dptr;

    while(len--) *dptr++ = *sptr++;

    return ret;
}

char *memcmp(char *dptr, char *sptr,int len)
{
    while(len--)
        if(*dptr++ != *sptr++) 
            return --dptr;

    return 0;
}

char *memset(char *dptr, int c, int len)
{
    char *ret = dptr;
    
    while(len--) *dptr++ = c;
    
    return ret;
}
