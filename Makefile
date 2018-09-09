SHELL = bash
SEMVER_RE := ^([0-9]+.[0-9]+.[0-9]+)(-([0-9A-Za-z.-]+))?(\+([0-9A-Za-z.-]))?$
VERSION := $(shell cat VERSION)
VERSION_PRE := $(shell [[ "$(VERSION)" =~ $(SEMVER_RE) ]] && printf '%s\n' "$${BASH_REMATCH[3]:-}")

PKG_VERSION := $(shell [[ "$(VERSION)" =~ $(SEMVER_RE) ]] && printf '%s\n' "$${BASH_REMATCH[1]}")
ifneq ($(VERSION_PRE),)
PKG_RELEASE := 1.$(VERSION_PRE)
else
PKG_RELEASE := 1
endif

BINTRAY_RPM_PATH := alikov/fedora/shelter/$(PKG_VERSION)

PREFIX := /usr/local
BINDIR = $(PREFIX)/bin
LIBDIR = $(PREFIX)/lib
SHAREDIR = $(PREFIX)/share
DOCSDIR = $(SHAREDIR)/doc
MANDIR = $(SHAREDIR)/man

.PHONY: all lint test doc build install uninstall clean release sdist rpm publish-rpm publish

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
	sourcedir=$$(readlink -f sdist); \
	rpmbuild -ba "shelter.spec" \
		--define "rpm_version $(PKG_VERSION)" \
		--define "rpm_release $(PKG_RELEASE)" \
		--define "full_version $(VERSION)" \
		--define "prefix $(PREFIX)" \
		--define "_srcrpmdir sdist/" \
		--define "_rpmdir bdist/" \
		--define "_sourcedir $${sourcedir}" \
		--define "_bindir $(BINDIR)" \
		--define "_libdir $(LIBDIR)" \
		--define "_defaultdocdir $(DOCSDIR)" \
		--define "_mandir $(MANDIR)"

publish-rpm:
	jfrog bt upload --publish=true bdist/noarch/shelter-$(PKG_VERSION)-$(PKG_RELEASE).noarch.rpm $(BINTRAY_RPM_PATH)

publish: publish-rpm
