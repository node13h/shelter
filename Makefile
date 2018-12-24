SHELL = bash

PROJECT := shelter

SEMVER_RE := ^([0-9]+.[0-9]+.[0-9]+)(-([0-9A-Za-z.-]+))?(\+([0-9A-Za-z.-]))?$
VERSION := $(shell cat VERSION)
VERSION_PRE := $(shell [[ "$(VERSION)" =~ $(SEMVER_RE) ]] && printf '%s\n' "$${BASH_REMATCH[3]:-}")

PKG_VERSION := $(shell [[ "$(VERSION)" =~ $(SEMVER_RE) ]] && printf '%s\n' "$${BASH_REMATCH[1]}")
ifdef VERSION_PRE
PKG_RELEASE := 1.$(VERSION_PRE)
else
PKG_RELEASE := 1
endif

BINTRAY_RPM_PATH := alikov/rpm/$(PROJECT)/$(PKG_VERSION)
BINTRAY_DEB_PATH := alikov/deb/$(PROJECT)/$(PKG_VERSION)

PREFIX := /usr/local
BINDIR = $(PREFIX)/bin
LIBDIR = $(PREFIX)/lib
SHAREDIR = $(PREFIX)/share
DOCSDIR = $(SHAREDIR)/doc
MANDIR = $(SHAREDIR)/man

SDIST_TARBALL := sdist/$(PROJECT)-$(VERSION).tar.gz
SDIST_DIR = $(PROJECT)-$(VERSION)
SPEC_FILE := $(PROJECT).spec
RPM_PACKAGE := bdist/noarch/$(PROJECT)-$(PKG_VERSION)-$(PKG_RELEASE).noarch.rpm
DEB_PACKAGE := bdist/$(PROJECT)_$(VERSION)_all.deb

.PHONY: all lint test doc build install uninstall clean release-start release-finish release sdist rpm publish-rpm deb publish-deb publish

all: build

lint:
	shellcheck *.sh

test: shelter-config.sh lint
	bash test.sh

doc/man/man3/shelter.sh.3:
	doxygen Doxyfile

doc: doc/man/man3/shelter.sh.3

shelter-config.sh: shelter-config.sh.in VERSION
	sed -e 's~@VERSION@~$(VERSION)~g' shelter-config.sh.in >shelter-config.sh

build: test doc shelter-config.sh

install: build
	install -m 0755 -d $(DESTDIR)$(BINDIR)
	install -m 0755 -d $(DESTDIR)$(MANDIR)/man3
	install -m 0755 -d $(DESTDIR)$(DOCSDIR)/shelter
	install -m 0755 doc/man/man3/shelter.sh.3 $(DESTDIR)$(MANDIR)/man3
	install -m 0755 shelter.sh $(DESTDIR)$(BINDIR)
	install -m 0644 shelter-config.sh $(DESTDIR)$(BINDIR)
	install -m 0644 README.* $(DESTDIR)$(DOCSDIR)/shelter

uninstall:
	rm -rf -- $(DESTDIR)$(DOCSDIR)/shelter
	rm -f -- $(DESTDIR)$(MANDIR)/man3/shelter.sh.3
	rm -f -- $(DESTDIR)$(BINDIR)/shelter.sh
	rm -f -- $(DESTDIR)$(BINDIR)/shelter-config.sh

clean:
	rm -f shelter-config.sh
	rm -rf doc
	rm -rf bdist sdist

release-start:
	bash release.sh start

release-finish:
	bash release.sh finish

release: release-start release-finish

$(SDIST_TARBALL):
	mkdir -p sdist; \
	git archive --prefix=$(SDIST_DIR)/ -o $(SDIST_TARBALL) $(VERSION)

sdist: $(SDIST_TARBALL)

$(RPM_PACKAGE): PREFIX := /usr
$(RPM_PACKAGE): $(SDIST_TARBALL)
	mkdir -p bdist; \
	rpmbuild -ba "$(SPEC_FILE)" \
	  --define rpm_version\ $(PKG_VERSION) \
	  --define rpm_release\ $(PKG_RELEASE) \
	  --define sdist_dir\ $(SDIST_DIR) \
	  --define sdist_tarball\ $(SDIST_TARBALL) \
	  --define prefix\ $(PREFIX) \
	  --define _srcrpmdir\ sdist/ \
	  --define _rpmdir\ bdist/ \
	  --define _sourcedir\ $(CURDIR)/sdist \
	  --define _bindir\ $(BINDIR) \
	  --define _libdir\ $(LIBDIR) \
	  --define _defaultdocdir\ $(DOCSDIR) \
	  --define _mandir\ $(MANDIR)

rpm: $(RPM_PACKAGE)

control: control.in VERSION
	sed -e 's~@VERSION@~$(VERSION)~g' control.in >control

$(DEB_PACKAGE): control $(SDIST_TARBALL)
	mkdir -p bdist; \
	target=$$(mktemp -d); \
	mkdir -p "$${target}/DEBIAN"; \
	cp control "$${target}/DEBIAN/control"; \
	tar -C sdist -xzf $(SDIST_TARBALL); \
	make -C sdist/$(SDIST_DIR) DESTDIR="$$target" PREFIX=/usr install; \
	dpkg-deb --build "$$target" $(DEB_PACKAGE); \
	rm -rf -- "$$target"

deb: $(DEB_PACKAGE)

publish-rpm: rpm
	jfrog bt upload --publish=true $(RPM_PACKAGE) $(BINTRAY_RPM_PATH)

publish-deb: deb
	jfrog bt upload --publish=true --deb xenial/main/all $(DEB_PACKAGE) $(BINTRAY_DEB_PATH)

publish: publish-rpm publish-deb
