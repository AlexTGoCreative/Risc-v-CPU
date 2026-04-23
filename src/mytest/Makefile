include ../config.mk

PROJ = mytest
OBJS = main.o
ASMS = main.s
SRCS = main.c

TARGETS = $(PROJ).a

.PHONY: all

all: $(TARGETS)
	@echo sources ok for $(TARGETS).

clean:
	-$(HELPERS) rm $(ASMS) $(OBJS) $(PROJ).a

%.o: %.s Makefile
	$(AS) $(ASFLAGS) -c $< -o $@

%.s: %.c Makefile
	$(CC) $(CFLAGS) -S $< -o $@

$(PROJ).a: $(OBJS) Makefile
	$(AR) $(ARFLAGS) $@ $(OBJS)
	$(RL) $@
