CFLAGS ?= -g -O2 -fomit-frame-pointer -Wformat -pedantic
CFLAGS += --std=c99

.PHONY: clean compile

compile: prll_jobserver

clean:
	rm -f sanitycheck check_key_size prll_jobserver 

sanitycheck: check_key_size
	./check_key_size && touch sanitycheck || (rm -f sanitycheck && false)

prll_jobserver: | sanitycheck

# For emacs' flymake-mode
.PHONY: check-syntax
check-syntax:
	gcc -Wall -Wextra -Wundef -Wshadow -Wunsafe-loop-optimizations -Wsign-compare -fsyntax-only ${CHK_SOURCES}
