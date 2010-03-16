CFLAGS ?= -g -O2 -fomit-frame-pointer -Wformat -pedantic
CFLAGS += --std=c99

.PHONY: clean compile test

compile: prll_qer prll_bfr

clean:
	rm -f prll_qer prll_bfr mkrandom.o
	cd tests && $(MAKE) clean

test: prll_qer prll_bfr
	cd tests && $(MAKE)

# For emacs' flymake-mode
.PHONY: check-syntax
check-syntax:
	gcc --std=c99 -Wall -Wextra -Wundef -Wshadow -Wunsafe-loop-optimizations -Wsign-compare -fsyntax-only ${CHK_SOURCES}

prll_bfr prll_qer: mkrandom.o mkrandom.h
