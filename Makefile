CFLAGS ?= -g -O2 -fomit-frame-pointer -Wformat -pedantic
CFLAGS += --std=c99

PRLL_DEFAULT_VERSION = 0.9999
PRLL_VERSION ?= $(PRLL_DEFAULT_VERSION)

CONFIGS = $(addprefix config_, keytype mallopt semun random)
PROGS   = prll_qer prll_bfr
DOCS    = README.md AUTHORS COPYING NEWS

# Installation-related variables; note PREFIX, DESTDIR support
NAME       = prll
PREFIX    ?= /usr/local
BIN_DIR   ?= $(DESTDIR)$(PREFIX)/bin
SHARE_DIR ?= $(DESTDIR)$(PREFIX)/share/$(NAME)
DOC_DIR   ?= $(DESTDIR)$(PREFIX)/share/doc/$(NAME)
MAN_DIR   ?= $(DESTDIR)$(PREFIX)/share/man/man1

.PHONY: clean compile test version prll.1

compile: $(PROGS)

clean:
	rm -f $(PROGS) $(addsuffix .o, $(PROGS) mkrandom)
	rm -f config.h $(CONFIGS) $(addsuffix .log, $(CONFIGS))
	$(MAKE) -C tests clean

test: prll_qer prll_bfr
	$(MAKE) -C tests

mkrandom.o: mkrandom.h | config.h

prll_bfr.o prll_qer.o: mkrandom.h abrterr.h | config.h

prll_bfr prll_qer: mkrandom.o

prll.1: prll.txt
	LC_TIME=C txt2man -P prll -t prll -r prll-$(PRLL_VERSION) -s 1 \
	< prll.txt > prll.1

version: prll.1
	sed -i -e 's/version $(PRLL_DEFAULT_VERSION)/version $(PRLL_VERSION)/' \
	    README.md prll.sh

config.h: $(addsuffix .c, $(CONFIGS))
	@echo
	@echo "--==CONFIGURING==--"
	@echo "// Automatically generated configuration for prll." > $@
	@$(foreach cfger,$^,\
	$(MAKE) $(cfger:.c=) 2>$(cfger:.c=.log) && ./$(cfger:.c=) >> $@ \
	|| true; )
	@echo "--==DONE CONFIGURING==--"
	@echo

install: $(PROGS) prll.1
	install -D -t $(BIN_DIR) $(PROGS)
	install -D -t $(SHARE_DIR) prll.sh
	install -D -t $(DOC_DIR) $(DOCS)
	install -D -t $(MAN_DIR) prll.1
	@echo
	@echo "Shell-glue script \`prll.sh' has been copied to $(SHARE_DIR)/, source it at shell startup to configure prll"

uninstall:
	rm -f $(foreach bin, $(PROGS), $(BIN_DIR)/$(bin))
	rm -f $(foreach doc, $(DOCS), $(DOC_DIR)/$(doc))
	rm -f $(MAN_DIR)/prll.1
	rmdir $(DOC_DIR) || true
	rm -f $(SHARE_DIR)/*
	rmdir $(SHARE_DIR) || true

# For emacs' flymake-mode
.PHONY: check-syntax
check-syntax:
	gcc --std=c99 -Wall -Wextra -Wundef -Wshadow -Wunsafe-loop-optimizations -Wsign-compare -fsyntax-only ${CHK_SOURCES}
