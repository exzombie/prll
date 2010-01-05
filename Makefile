CFLAGS ?= -g -O2 -fomit-frame-pointer -Wformat -pedantic
CFLAGS += --std=c99

.PHONY: clean compile

compile: prll_jobserver

clean:
	rm -f prll_jobserver

.PHONY: check-syntax
check-syntax:
	gcc -Wall -Wextra -Wundef -Wshadow -Wunsafe-loop-optimizations -Wsign-compare -fsyntax-only ${CHK_SOURCES}
