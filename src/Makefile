# Copyright (c) 2018, Marcelo Samsoniuk
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
# 
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# 
# * Neither the name of the copyright holder nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 

include config.mk

# Add your application here:

APPLICATION = mytest
#APPLICATION = darkshell
#APPLICATION = coremark
#APPLICATION = badapple
#APPLICATION = mandelbrot
#APPLICATION = donut
#APPLICATION = dhrystone
#APPLICATION = spidemo
#APPLICATION = primes

PROJ = darksocv
LIBS = $(APPLICATION)/$(APPLICATION).a $(DARKLIBC)/$(DARKLIBC).a 
OBJS = boot.o
ASMS = boot.S
SRCS = 

ifdef SMALL
    CPFLAGS += -DSMALL=1
endif

# uncomment for hardware mul
#export MAC = 1

ifdef MAC
    CFLAGS += -DMAC=1
endif

ifdef NOBANNER
    CFLAGS += -DNOBANNER=1
    ASFLAGS += -DNOBANNER=1
endif

ifeq ($(APPLICATION),spidemo)
    CFLAGS += -DSPI=1
    ASFLAGS += -DSPI=1
SPIBB := 1
ifdef SPIBB
    CFLAGS += -DSPIBB=1
    ASFLAGS += -DSPIBB=1
endif
SPI3WIRE:=1
ifdef SPI3WIRE
    CFLAGS += -DSPI3WIRE=1
    ASFLAGS += -DSPI3WIRE=1
endif
endif

DEPS = $(SRCS) $(ASMS) $(OBJS) $(PROJ).ld $(PROJ).lds $(LIBS) $(APPLICATION)/$(APPLICATION).a

ifdef HARVARD
	TARGETS = $(PROJ).rom.mem $(PROJ).ram.mem
else
	TARGETS = $(PROJ).mem
endif

.PHONY: all

all: $(TARGETS) $(DEPS)
	-echo build is ok for $(TARGETS)

$(DARKLIBC)/$(DARKLIBC).a:
	make -C $(DARKLIBC) all

$(APPLICATION)/$(APPLICATION).a:
	make -C $(APPLICATION) all

clean:
	make -C $(DARKLIBC) clean
	make -C $(APPLICATION) clean
	-$(HELPERS) rm $(OBJS) $(PROJ).S $(PROJ).bin $(PROJ).lst $(PROJ).map $(PROJ).ram $(PROJ).rom $(PROJ).x86 $(PROJ).text $(PROJ).data $(PROJ).ld $(PROJ).o $(PROJ).mem $(PROJ).rom.mem $(PROJ).ram.mem $(PROJ)_uart.bin

%.o: %.s Makefile
	$(AS) $(ASFLAGS) -c $< -o $@

%.s: %.c Makefile
	$(CC) $(CFLAGS) -S $< -o $@

$(PROJ).ld: $(PROJ).lds Makefile
	$(CPP) $(CPFLAGS) -DMLEN=$(shell $(HELPERS) extract_mlen ../rtl/config.vh) $(PROJ).lds $(PROJ).ld
	
$(PROJ).o: $(OBJS) $(PROJ).ld $(LIBS)
	$(LD) $(LDFLAGS) -o $@ $(OBJS) $(LDLIBS)
	$(OD) $(ODFLAGS) $@ > $(PROJ).S

$(PROJ).rom.mem: $(PROJ).o
	$(OC) $(OCFLAGS) $< $(PROJ).text --only-section .*text* 
	$(HELPERS) bin2hex $(PROJ).text $@ $(ENDIAN)
	$(HELPERS) rm $(PROJ).text
	$(HELPERS) count_lines $@
	@echo rom ok.

$(PROJ).ram.mem: $(PROJ).o
	$(OC) $(OCFLAGS) $< $(PROJ).data --only-section .*data*
	@echo building for $(ENDIAN)
	$(HELPERS) bin2hex $(PROJ).data $@ $(ENDIAN)
	$(HELPERS) rm $(PROJ).data
	$(HELPERS) count_lines $@
	@echo ram ok.

$(PROJ).mem: $(PROJ).o
	$(OC) $(OCFLAGS) $< $(PROJ).bin
	$(HELPERS) bin2hex $(PROJ).bin $@ $(ENDIAN)
	$(HELPERS) skip_copy $(PROJ).bin $(PROJ)_uart.bin 512
	$(HELPERS) rm $(PROJ).bin
	$(HELPERS) count_lines $@
	@echo mem ok for $(ENDIAN)-endian.
	
$(PROJ).x86: $(SRCS)
	$(HOST_CC) $(HOST_CFLAGS) $(SRCS) -o $(PROJ).x86 -DBUILD="\"$(BUILD)\"" -DARCH="\"x86\""
	@echo x86 ok.
