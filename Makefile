VERSION := $(shell cat VERSION)

PREFIX := /usr/local
BINDIR = $(PREFIX)/bin
LIBDIR = $(PREFIX)/lib
SHAREDIR = $(PREFIX)/share
DOCSDIR = $(SHAREDIR)/doc
MANDIR = $(SHAREDIR)/man

.PHONY: all lint test doc build install uninstall clean release sdist rpm

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
	rm -rf bdist sdist

release:
	git tag $(VERSION)

sdist:
	mkdir -p sdist; \
	git archive "--prefix=shelter-$(VERSION)/" -o "sdist/shelter-$(VERSION).tar.gz" "$(VERSION)"

rpm: PREFIX := /usr
rpm: sdist
	mkdir -p bdist; \
	rpm_version=$$(cut -f 1 -d '-' <<< "$(VERSION)"); \
	rpm_release=$$(cut -s -f 2 -d '-' <<< "$(VERSION)"); \
	sourcedir=$$(readlink -f sdist); \
	rpmbuild -ba "shelter.spec" \
		--define "rpm_version $${rpm_version}" \
		--define "rpm_release $${rpm_release:-1}" \
		--define "full_version $(VERSION)" \
		--define "prefix $(PREFIX)" \
		--define "_srcrpmdir sdist/" \
		--define "_rpmdir bdist/" \
		--define "_sourcedir $${sourcedir}" \
		--define "_bindir $(BINDIR)" \
		--define "_libdir $(LIBDIR)" \
		--define "_defaultdocdir $(DOCSDIR)" \
		--define "_mandir $(MANDIR)"
