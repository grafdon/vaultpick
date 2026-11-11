PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
SCRIPTS = vaultpick tests/run.sh tests/demo tests/env.sh tests/stubs/rbw tests/stubs/clipstub tests/stubs-fzf/fzf

.PHONY: install uninstall test lint check

install:
	install -d "$(DESTDIR)$(BINDIR)"
	install -m 755 vaultpick "$(DESTDIR)$(BINDIR)/vaultpick"

uninstall:
	rm -f "$(DESTDIR)$(BINDIR)/vaultpick"

test:
	sh tests/run.sh
	python3 tests/e2e.py

lint:
	shellcheck $(SCRIPTS)

check: lint test
