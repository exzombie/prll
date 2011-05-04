CFLAGS ?= -g -O2 -fomit-frame-pointer -Wformat -pedantic
CFLAGS += --std=c99

ALL_TESTS := sleeps string funcsetting pipesleeps manysleep interrupt buffering

.PHONY: clean all $(ALL_TESTS)

.PRECIOUS: $(ALL_TESTS)

all: $(ALL_TESTS)

clean:
	-rm -f bash_found zsh_found dash_found sh_found any_found
	-rm -f utilities_found manysleep.err buffering.*

$(ALL_TESTS): utilities_found

utilities_found:
	for util in tr grep sort diff ; do \
		command -v $$util || exit 1 ; \
	done
	touch utilities_found

bash_found:
	-command -v bash && touch bash_found

zsh_found:
	-command -v zsh && touch zsh_found

dash_found:
	-command -v dash && touch dash_found

sh_found:
	-command -v sh && touch sh_found

any_found: zsh_found bash_found dash_found sh_found
	test -f bash_found -o -f zsh_found \
	-o -f dash_found -o -f sh_found && touch any_found

$(ALL_TESTS): any_found
	@echo; echo;
	@if test -f bash_found ; then bash $@ ; else true ; fi
	@if test -f zsh_found ; then zsh $@ ; else true ; fi
	@if test -f dash_found ; then dash $@ ; else true ; fi
	@if test -f sh_found ; then sh $@ ; else true ; fi
	@echo; echo;

# For emacs' flymake-mode
.PHONY: check-syntax
check-syntax:
	gcc --std=c99 -Wall -Wextra -Wundef -Wshadow -Wunsafe-loop-optimizations -Wsign-compare -fsyntax-only ${CHK_SOURCES}
