CFLAGS ?= -g -O2 -fomit-frame-pointer -Wformat -pedantic
CFLAGS += --std=c99

.PHONY: clean compile test

compile: prll_qer prll_bfr

clean:
	rm -f prll_qer prll_bfr mkrandom.o
	rm -f $(foreach cfger, .h _keytype _mallopt _semun, config$(cfger) \
		config$(cfger).log)
	$(MAKE) -C tests clean

test: prll_qer prll_bfr
	$(MAKE) -C tests

# For emacs' flymake-mode
.PHONY: check-syntax
check-syntax:
	gcc --std=c99 -Wall -Wextra -Wundef -Wshadow -Wunsafe-loop-optimizations -Wsign-compare -fsyntax-only ${CHK_SOURCES}

prll_bfr prll_qer: mkrandom.o mkrandom.h abrterr.h | config.h

prll.1: prll.txt
	LC_TIME=C txt2man -P prll -t prll -r prll-0.6 -s 1 \
	 -B prll_interrupt \
	< prll.txt > prll.1

config.h: config_keytype.c config_mallopt.c config_semun.c
	@echo "--==CONFIGURING==--"
	@echo "// Automatically generated configuration for prll." > $@
	@$(foreach cfger,$^,\
	$(MAKE) $(cfger:.c=) 2>$(cfger:.c=.log) && ./$(cfger:.c=) >> $@ \
	|| true; )
	@echo "--==DONE CONFIGURING==--"
