CFLAGS ?= -g -O2 -fomit-frame-pointer -Wformat -pedantic
CFLAGS += --std=c99

.PHONY: clean compile test

compile: prll_qer

clean:
	rm -f sanitycheck check_key_size prll_qer 
	cd tests && $(MAKE) clean

sanitycheck: check_key_size
	./check_key_size && touch sanitycheck || (rm -f sanitycheck && false)

prll_qer: sanitycheck
	$(CC) $(CFLAGS) -o prll_qer prll_qer.c

test: prll_qer
	cd tests && $(MAKE)

# For emacs' flymake-mode
.PHONY: check-syntax
check-syntax:
	gcc -Wall -Wextra -Wundef -Wshadow -Wunsafe-loop-optimizations -Wsign-compare -fsyntax-only ${CHK_SOURCES}
