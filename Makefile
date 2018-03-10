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
ENV_DIR   ?= /etc/profile.d
LIB_DIR   ?= $(PREFIX)/lib/$(NAME)
DOC_DIR   ?= $(PREFIX)/share/doc/$(NAME)
MAN_DIR   ?= $(PREFIX)/share/man/man1

.PHONY: clean compile test version

compile: $(PROGS)

clean:
	rm -f $(PROGS) $(addsuffix .o, $(PROGS) mkrandom)
	rm -f config.h $(CONFIGS) $(addsuffix .log, $(CONFIGS))
	rm -f prll.preinst
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
	install -d $(DESTDIR)$(LIB_DIR)
	install -d $(DESTDIR)$(ENV_DIR)
	install -d $(DESTDIR)$(DOC_DIR)
	install -d $(DESTDIR)$(MAN_DIR)
	install $(PROGS) $(DESTDIR)$(LIB_DIR)
	install -m 0644 $(DOCS) $(DESTDIR)$(DOC_DIR)
	install -m 0644 prll.1 $(DESTDIR)$(MAN_DIR)
	sed -e 's#PRLL_HELPER_PATH=.*#PRLL_HELPER_PATH=$(LIB_DIR)#' \
	    prll.sh > prll.preinst
	install -m 0644 prll.preinst $(DESTDIR)$(ENV_DIR)/prll.sh
	rm prll.preinst
	@echo
	@echo "Shell-glue script \`prll.sh' has been copied to $(ENV_DIR)/, source it at shell startup to configure prll (may happen automatically)"

uninstall:
	rm -f $(foreach bin, $(PROGS), $(DESTDIR)$(LIB_DIR)/$(bin))
	rm -f $(foreach doc, $(DOCS), $(DESTDIR)$(DOC_DIR)/$(doc))
	rmdir $(DESTDIR)$(LIB_DIR) || true
	rmdir $(DESTDIR)$(DOC_DIR) || true
	rm -f $(DESTDIR)$(MAN_DIR)/prll.1
	rm -f $(DESTDIR)$(ENV_DIR)/prll.sh

# For emacs' flymake-mode
.PHONY: check-syntax
check-syntax:
	gcc --std=c99 -Wall -Wextra -Wundef -Wshadow -Wunsafe-loop-optimizations -Wsign-compare -fsyntax-only ${CHK_SOURCES}
