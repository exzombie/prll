CFLAGS ?= -g -O2 -fomit-frame-pointer -Wformat -pedantic
CFLAGS += --std=c99

.PHONY: clean compile test

compile: prll_qer

clean:
	rm -f prll_qer mkrandom.o
	cd tests && $(MAKE) clean

test: prll_qer
	cd tests && $(MAKE)

# For emacs' flymake-mode
.PHONY: check-syntax
check-syntax:
	gcc -Wall -Wextra -Wundef -Wshadow -Wunsafe-loop-optimizations -Wsign-compare -fsyntax-only ${CHK_SOURCES}

prll_qer: mkrandom.o mkrandom.h
