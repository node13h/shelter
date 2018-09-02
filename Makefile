PREFIX := /usr/local
BINDIR = $(PREFIX)/bin
LIBDIR = $(PREFIX)/lib
SHAREDIR = $(PREFIX)/share
DOCSDIR = $(SHAREDIR)/doc
MANDIR = $(SHAREDIR)/man

.PHONY: all lint test doc build install uninstall clean

all: build

lint:
	shellcheck *.sh

test: lint
	bash test.sh

doc:
	doxygen Doxyfile

build: test doc

install: build
	install -m 0755 -d "$(DESTDIR)$(BINDIR)"
	install -m 0755 -d "$(DESTDIR)$(MANDIR)/man3"
	install -m 0755 -d "$(DESTDIR)$(DOCSDIR)/shelter"
	install -m 0755 doc/man/man3/shelter.sh.3 "$(DESTDIR)$(MANDIR)/man3"
	install -m 0755 shelter.sh "$(DESTDIR)$(BINDIR)"
	install -m 0644 README.* "$(DESTDIR)$(DOCSDIR)/shelter"

uninstall:
	rm -rf -- "$(DESTDIR)$(DOCSDIR)/shelter"
	rm -f -- "$(DESTDIR)$(MANDIR)/man3/shelter.sh.3"
	rm -f -- "$(DESTDIR)$(BINDIR)/shelter.sh"

clean:
	rm -rf -- doc
