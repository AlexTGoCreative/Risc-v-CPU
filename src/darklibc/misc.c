// mul/div

int mac(int,int,int);

unsigned __umulsi3(unsigned x,unsigned y)
{
    unsigned acc;

#ifdef MAC

    unsigned short xh,xl,yh,yl;

    xl = x&0xffff;
    yl = y&0xffff;

    acc = mac(0,xl,yl);

    xh = x>>16;
    yh = y>>16;

    if(xh) acc += mac(0,xh,yl)<<16;
    if(yh) acc += mac(0,xl,yh)<<16;

#else
    if(x<y) { unsigned z = x; x = y; y = z; }
    
    for(acc=0;y;x<<=1,y>>=1) if (y & 1) acc += x;
#endif
    return acc;
}

int __mulsi3(int x, int y)
{
    unsigned acc,xs,ys;
    
    if(x<0) { xs=1; x=-x; } else xs=0;
    if(y<0) { ys=1; y=-y; } else ys=0;

    acc = __umulsi3(x,y);
    
    return xs^ys ? -acc : acc;
}

unsigned __udiv_umod_si3(unsigned x,unsigned y,int opt)
{
    unsigned acc,aux;

    if(!y) return 0;

    for(aux=1;y<x&&!(y&(1<<31));aux<<=1,y<<=1);
    for(acc=0;x&&aux;aux>>=1,y>>=1) if(y<=x) x-=y,acc+=aux;

    return opt ? acc : x;
}

int __udivsi3(int x, int y)
{
    return __udiv_umod_si3(x,y,1);
}

int __umodsi3(int x,int y)
{
    return __udiv_umod_si3(x,y,0);
}

int __div_mod_si3(int x,int y,int opt)
{
    unsigned acc,xs,ys;

    if(!y) return 0;

    if(x<0) { xs=1; x=-x; } else xs=0;
    if(y<0) { ys=1; y=-y; } else ys=0;

    acc = __udiv_umod_si3(x,y,opt);

    if(opt) return xs^ys ? -acc : acc;
    else    return xs    ? -acc : acc;
}

int __divsi3(int x, int y)
{
    return __div_mod_si3(x,y,1);
}

int __modsi3(int x,int y)
{
    return __div_mod_si3(x,y,0);
}
