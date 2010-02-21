CFLAGS ?= -g -O2 -fomit-frame-pointer -Wformat -pedantic
CFLAGS += --std=c99

.PHONY: clean compile test

compile: prll_jobserver

clean:
	rm -f sanitycheck check_key_size prll_jobserver 
	$(MAKE) -C tests clean

sanitycheck: check_key_size
	./check_key_size && touch sanitycheck || (rm -f sanitycheck && false)

prll_jobserver: sanitycheck
	$(CC) $(CFLAGS) -o prll_jobserver prll_jobserver.c

test: prll_jobserver
	cd tests && $(MAKE)

# For emacs' flymake-mode
.PHONY: check-syntax
check-syntax:
	gcc -Wall -Wextra -Wundef -Wshadow -Wunsafe-loop-optimizations -Wsign-compare -fsyntax-only ${CHK_SOURCES}
