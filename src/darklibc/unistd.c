#include <time.h>
#include <unistd.h>

// time management

void usleep(int delay)
{
    clock_t t = clock() + delay;
    
    while(clock()<t);
}
