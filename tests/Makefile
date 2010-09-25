CFLAGS ?= -g -O2 -fomit-frame-pointer -Wformat -pedantic
CFLAGS += --std=c99

ALL_TESTS := sleeps string funcsetting pipesleeps manysleep interrupt buffering

.PHONY: clean all $(ALL_TESTS)

.PRECIOUS: $(ALL_TESTS)

all: $(ALL_TESTS)

clean:
	-rm -f bash_found zsh_found dash_found any_found manysleep.err
	-rm -f utilities_found buffering.*

$(ALL_TESTS): utilities_found

utilities_found:
	command -v tr grep sort diff && touch utilities_found

bash_found:
	-command -v bash && touch bash_found

zsh_found:
	-command -v zsh && touch zsh_found

dash_found:
	-command -v dash && touch dash_found

any_found: zsh_found bash_found dash_found
	test -f bash_found -o -f zsh_found \
	-o -f dash_found && touch any_found

$(ALL_TESTS): any_found
	@echo; echo;
	@test -f bash_found && bash $@
	@test -f zsh_found && zsh $@
	@test -f dash_found && dash $@
	@echo; echo;

# For emacs' flymake-mode
.PHONY: check-syntax
check-syntax:
	gcc --std=c99 -Wall -Wextra -Wundef -Wshadow -Wunsafe-loop-optimizations -Wsign-compare -fsyntax-only ${CHK_SOURCES}
