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

BINTRAY_RPM_PATH := alikov/rpm/shelter/$(PKG_VERSION)
BINTRAY_DEB_PATH := alikov/deb/shelter/$(PKG_VERSION)

PREFIX := /usr/local
BINDIR = $(PREFIX)/bin
LIBDIR = $(PREFIX)/lib
SHAREDIR = $(PREFIX)/share
DOCSDIR = $(SHAREDIR)/doc
MANDIR = $(SHAREDIR)/man

CURRENT_DIR := $(shell printf '%q\n' "$$(pwd -P)")

SDIST_TARBALL := sdist/shelter-$(VERSION).tar.gz
SDIST_DIR = shelter-$(VERSION)
RPM_PACKAGE := bdist/noarch/shelter-$(PKG_VERSION)-$(PKG_RELEASE).noarch.rpm
DEB_PACKAGE := bdist/shelter_$(VERSION)_all.deb

.PHONY: all lint test doc build install uninstall clean release-start release-finish release sdist rpm publish-rpm deb publish-deb publish

all: build

lint:
	shellcheck *.sh

test: shelter-config.sh lint
	bash test.sh

doc/man/man3/shelter.sh.3:
	doxygen Doxyfile

doc: doc/man/man3/shelter.sh.3

shelter-config.sh:
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
	rpmbuild -ba "shelter.spec" \
	  --define rpm_version\ $(PKG_VERSION) \
	  --define rpm_release\ $(PKG_RELEASE) \
	  --define sdist_dir\ $(SDIST_DIR) \
	  --define sdist_tarball\ $(SDIST_TARBALL) \
	  --define prefix\ $(PREFIX) \
	  --define _srcrpmdir\ sdist/ \
	  --define _rpmdir\ bdist/ \
	  --define _sourcedir\ $(CURRENT_DIR)/sdist \
	  --define _bindir\ $(BINDIR) \
	  --define _libdir\ $(LIBDIR) \
	  --define _defaultdocdir\ $(DOCSDIR) \
	  --define _mandir\ $(MANDIR)

rpm: $(RPM_PACKAGE)

control:
	sed -e 's~@VERSION@~$(VERSION)~g' control.in >control

$(DEB_PACKAGE): control $(SDIST_TARBALL)
	mkdir -p bdist; \
	target=$$(mktemp -d); \
	mkdir -p "$${target}/DEBIAN"; \
	cp control "$${target}/DEBIAN/control"; \
	tar -C sdist -xzf $(SDIST_TARBALL); \
	( cd sdist/$(SDIST_DIR); make DESTDIR="$$target" PREFIX=/usr install; ); \
	dpkg-deb --build "$$target" $(DEB_PACKAGE); \
	rm -rf -- "$$target"

deb: $(DEB_PACKAGE)

publish-rpm: rpm
	jfrog bt upload --publish=true $(RPM_PACKAGE) $(BINTRAY_RPM_PATH)

publish-deb: deb
	jfrog bt upload --publish=true --deb xenial/main/all $(DEB_PACKAGE) $(BINTRAY_DEB_PATH)

publish: publish-rpm publish-deb
