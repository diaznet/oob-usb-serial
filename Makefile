# Makefile for oob-usb-serial
#
# Supports staged installs (DESTDIR) so it works both for local `make install`
# and for Debian packaging via dh_auto_install.

PACKAGE  = oob-usb-serial
PREFIX  ?= /usr
BINDIR   = $(PREFIX)/bin
LIBDIR   = $(PREFIX)/lib/$(PACKAGE)
SHAREDIR = $(PREFIX)/share/$(PACKAGE)
DOCDIR   = $(PREFIX)/share/doc/$(PACKAGE)
ETCDIR   = /etc/$(PACKAGE)
UNITDIR  = /lib/systemd/system

INSTALL      = install
INSTALL_DATA = $(INSTALL) -m 0644
INSTALL_BIN  = $(INSTALL) -m 0755

.PHONY: all install uninstall check clean

all:
	@echo "Nothing to build. Use 'make install' (honours DESTDIR/PREFIX)."

install:
	# Executable CLI
	$(INSTALL) -d $(DESTDIR)$(BINDIR)
	$(INSTALL_BIN) src/bin/oob-usb-serial $(DESTDIR)$(BINDIR)/oob-usb-serial

	# Libraries
	$(INSTALL) -d $(DESTDIR)$(LIBDIR)
	$(INSTALL_BIN) src/lib/discover.sh     $(DESTDIR)$(LIBDIR)/discover.sh
	$(INSTALL_BIN) src/lib/screenrc-gen.sh $(DESTDIR)$(LIBDIR)/screenrc-gen.sh

	# Shared data
	$(INSTALL) -d $(DESTDIR)$(SHAREDIR)
	$(INSTALL_DATA) src/share/serial_speeds.txt $(DESTDIR)$(SHAREDIR)/serial_speeds.txt
	$(INSTALL_DATA) src/share/serial_framings.txt $(DESTDIR)$(SHAREDIR)/serial_framings.txt
	$(INSTALL) -d $(DESTDIR)$(SHAREDIR)/profile
	$(INSTALL_DATA) src/profile/oob-usb-serial.sh $(DESTDIR)$(SHAREDIR)/profile/oob-usb-serial.sh

	# Config (conffiles)
	$(INSTALL) -d $(DESTDIR)$(ETCDIR)
	$(INSTALL_DATA) src/etc/oob-usb-serial.conf $(DESTDIR)$(ETCDIR)/oob-usb-serial.conf
	$(INSTALL_DATA) src/etc/devices.conf        $(DESTDIR)$(ETCDIR)/devices.conf

	# systemd unit
	$(INSTALL) -d $(DESTDIR)$(UNITDIR)
	$(INSTALL_DATA) src/systemd/oob-usb-serial.service $(DESTDIR)$(UNITDIR)/oob-usb-serial.service

	# Man page
	$(INSTALL) -d $(DESTDIR)$(PREFIX)/share/man/man1
	$(INSTALL_DATA) src/man/oob-usb-serial.1 $(DESTDIR)$(PREFIX)/share/man/man1/oob-usb-serial.1

	# Bash completion
	$(INSTALL) -d $(DESTDIR)$(PREFIX)/share/bash-completion/completions
	$(INSTALL_DATA) src/completion/oob-usb-serial $(DESTDIR)$(PREFIX)/share/bash-completion/completions/oob-usb-serial

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/oob-usb-serial
	rm -rf $(DESTDIR)$(LIBDIR)
	rm -rf $(DESTDIR)$(SHAREDIR)
	rm -f $(DESTDIR)$(UNITDIR)/oob-usb-serial.service
	rm -f $(DESTDIR)$(PREFIX)/share/man/man1/oob-usb-serial.1
	rm -f $(DESTDIR)$(PREFIX)/share/bash-completion/completions/oob-usb-serial
	# Config in $(ETCDIR) is intentionally left in place.

check:
	# -x follows sourced libraries; SC1091 is excluded because the runtime
	# config files (sourced dynamically) do not exist at lint time.
	shellcheck -x -e SC1091 -s bash src/bin/oob-usb-serial src/lib/discover.sh src/lib/screenrc-gen.sh
	shellcheck -s bash build.sh scripts/build-apt-repo.sh scripts/setup-apt-signing-key.sh
	shellcheck -s sh src/profile/oob-usb-serial.sh

clean:
	@true
