# After configure each Makefile, you can just type 'make'

default: src/darksocv.mem
	make -C sim

all:
	make -C src all
	make -C sim all
	make -C boards all

src/darksocv.mem:
	make -C src all

install:
	make -C boards install

clean:
	make -C src clean
	make -C sim clean
	make -C boards clean
