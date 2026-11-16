# Makefile for clice.el

EMACS ?= emacs
BATCH = $(EMACS) -Q --batch

ELFILES := clice.el clice-protocol.el clice-context.el clice-cli.el \
           clice-fold.el clice-links.el clice-select.el \
           clice-semantic.el clice-toml.el
TESTFILES := $(wildcard test/*-test.el)

.PHONY: all compile test test-integration lint clean

all: compile test

compile:
	@$(BATCH) -L . -f batch-byte-compile $(ELFILES)

test:
	@$(BATCH) -L . -L test $(foreach f,$(TESTFILES),-l $(f)) \
	  -f ert-run-tests-batch-and-exit

# Requires a clice executable on PATH; skipped otherwise.
test-integration:
	@$(BATCH) -L . -L test -l test/integration/clice-integration-test.el \
	  -f ert-run-tests-batch-and-exit

lint:
	@$(BATCH) -L . --eval "(progn (require 'checkdoc) (dolist (f command-line-args-left) (with-current-buffer (find-file-noselect f) (checkdoc-current-buffer t))))" $(ELFILES)

clean:
	@rm -f *.elc test/*.elc
