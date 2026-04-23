#ifndef __TIMEH__
#define __TIMEH__

#define CLOCKS_PER_SEC 1000000

typedef unsigned int clock_t;
typedef unsigned int time_t;

struct timeval
{
    time_t       tv_sec;
    clock_t      tv_usec;
};

time_t time(time_t *);
clock_t clock();

int gettimeofday(struct timeval *);

#endif
