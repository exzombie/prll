CFLAGS ?= -g -O2 -fomit-frame-pointer -Wformat -pedantic
CFLAGS += --std=c99

BASH_TESTS := 
ZSH_TESTS := ksharr
ANY_TESTS := sleeps string pipesleeps manysleep funcsetting interrupt buffering

.PHONY: clean all $(BASH_TEST) $(ZSH_TESTS) $(ANY_TESTS)

.PRECIOUS: $(BASH_TEST) $(ZSH_TESTS) $(ANY_TESTS)

all: $(ANY_TESTS) $(BASH_TESTS) $(ZSH_TESTS)

clean:
	rm -f bash_found zsh_found any_found both_found manysleep.err
	rm -f utilities_found buffering.*

$(ANY_TESTS) $(BASH_TESTS) $(ZSH_TESTS): utilities_found

utilities_found:
	/usr/bin/which tr grep sort diff && touch utilities_found

bash_found:
	-which bash && touch bash_found

zsh_found:
	-which zsh && touch zsh_found

any_found: zsh_found bash_found
	-test -f bash_found -a -f zsh_found  && touch both_found
	test -f bash_found -o -f zsh_found  && touch any_found

$(ANY_TESTS): any_found
	@if test -f both_found  ; then \
		echo "Testing both bash and zsh"; \
		echo "Test:" $@ ; \
		bash $@ && zsh $@; \
	elif test -f bash_found  ; then \
		echo "Testing bash only"; \
		bash $@; \
	elif test -f zsh_found  ; then \
		echo "Testing zsh only"; \
		zsh $@; \
	else \
		echo "Something's wrong"; \
		false; \
	fi

$(BASH_TESTS): bash_found
	@if test -f bash_found ; then \
		echo "Test: " $@ ; \
		bash $@; \
	else \
		true; \
	fi

$(ZSH_TESTS): zsh_found
	@if test -f zsh_found ; then \
		echo "Test: " $@ ; \
		zsh $@; \
	else \
		true; \
	fi

# For emacs' flymake-mode
.PHONY: check-syntax
check-syntax:
	gcc --std=c99 -Wall -Wextra -Wundef -Wshadow -Wunsafe-loop-optimizations -Wsign-compare -fsyntax-only ${CHK_SOURCES}
