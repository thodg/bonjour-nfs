
PREFIX := /usr/local
DESTDIR :=

build: bonjour-nfs.plist

bonjour-nfs.plist: bonjour-nfs.plist.in
	sed -e 's|@PREFIX@|${PREFIX}|g' bonjour-nfs.plist.in > $@.tmp
	mv $@.tmp $@

CLEANFILES = bonjour-nfs.plist bonjour-nfs.plist.tmp
clean:
	rm -f ${CLEANFILES}

install: build
	install -d -m 755 ${DESTDIR}${PREFIX}/bin
	install -m 755 bonjour-nfs.rb ${DESTDIR}${PREFIX}/bin/bonjour-nfs
	install -d -m 755 ${DESTDIR}/Library/LaunchDaemons
	install -m 644 bonjour-nfs.plist ${DESTDIR}/Library/LaunchDaemons/bonjour-nfs.plist

deploy: install
	launchctl unload -w ${DESTDIR}/Library/LaunchDaemons/bonjour-nfs.plist || echo -n
	launchctl load -w ${DESTDIR}/Library/LaunchDaemons/bonjour-nfs.plist

.PHONY: build clean install deploy
