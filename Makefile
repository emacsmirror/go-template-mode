EMACS ?= emacs
PKG   := go-template-mode
SOURCES := $(PKG)-font-lock.el $(PKG).el
TESTS := tests/$(PKG)-test.el

.PHONY: all compile test clean

all: compile test

compile:
	$(EMACS) -Q -batch -L . \
	  -f batch-byte-compile $(SOURCES)

test:
	$(EMACS) -Q -batch -L . -L tests \
	  -l $(PKG) -l $(TESTS) \
	  -f ert-run-tests-batch-and-exit

clean:
	rm -f *.elc tests/*.elc
