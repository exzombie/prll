CFLAGS += --std=c99 -Wformat -pedantic -g -O2 -fomit-frame-pointer

.PHONY: clean compile

compile: mapp_jobserver

clean:
	rm -f mapp_jobserver

.PHONY: check-syntax
check-syntax:
	gcc -Wall -Wextra -Wundef -Wshadow -Wunsafe-loop-optimizations -Wsign-compare -fsyntax-only ${CHK_SOURCES}
