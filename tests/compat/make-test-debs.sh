#!/bin/sh
# Build locally constructed test packages that exercise paths upstream packages
# do not: firmware-file collisions, conffiles, maintainer scripts, version bumps.
#   make-test-debs.sh OUTDIR
set -e
O=$(cd "$1" && pwd); T=$(mktemp -d)
mk() { # name version [extra control lines]
	d=$T/$1-$2; mkdir -p "$d/DEBIAN"
	printf 'Package: %s\nVersion: %s\nArchitecture: arm64\nMaintainer: nz tests <root@localhost>\nDescription: nz test package\n%s' "$1" "$2" "$3" > "$d/DEBIAN/control"
	echo "$d"
}
# 1. hostile package: tries to replace firmware files, also ships one legitimate file
d=$(mk nz-test-hostile 1.0 "")
mkdir -p "$d/bin" "$d/lib" "$d/usr/lib" "$d/etc" "$d/opt/nz-test"
echo "HOSTILE" > "$d/bin/busybox"; echo "HOSTILE" > "$d/lib/libc.so.6"; echo "HOSTILE" > "$d/usr/lib/libstdc++.so.6"
echo "hostile:x:0:0::/:/bin/sh" > "$d/etc/passwd"; echo "legit" > "$d/opt/nz-test/marker"
dpkg-deb -Zzstd --root-owner-group -b "$d" "$O/nz-test-hostile_1.0_arm64.deb" >/dev/null
# 2. lifecycle package in two versions: conffile + scripts + user data
for v in 1.0 2.0; do
	d=$(mk nz-test-app $v "Depends: libc6 (>= 2.38), libstdc++6
")
	mkdir -p "$d/usr/share/APPLaunch/applications" "$d/etc/nz-test-app" "$d/opt/nz-test-app"
	echo "version $v" > "$d/opt/nz-test-app/VERSION"
	printf '[Desktop Entry]\nName=NZ Test %s\nExec=/bin/true\nType=Application\n' $v > "$d/usr/share/APPLaunch/applications/nz-test-app.desktop"
	echo "setting=default-$v" > "$d/etc/nz-test-app/app.conf"; echo "/etc/nz-test-app/app.conf" > "$d/DEBIAN/conffiles"
	printf '#!/bin/sh\nset -e\nmkdir -p /var/lib/nz-test-app\necho "postinst %s $1 $2" >> /var/lib/nz-test-app/history\n' $v > "$d/DEBIAN/postinst"
	printf '#!/bin/sh\nset -e\necho "prerm %s $1 $2" >> /var/lib/nz-test-app/history\n' $v > "$d/DEBIAN/prerm"
	printf '#!/bin/sh\nset -e\n[ "$1" = purge ] && rm -rf /var/lib/nz-test-app || true\n' > "$d/DEBIAN/postrm"
	chmod 755 "$d/DEBIAN/postinst" "$d/DEBIAN/prerm" "$d/DEBIAN/postrm"
	dpkg-deb -Zzstd --root-owner-group -b "$d" "$O/nz-test-app_${v}_arm64.deb" >/dev/null
done
# 3. package with a dependency the firmware does not provide
d=$(mk nz-test-needs-debian 1.0 "Depends: libc6, libnonexistent42 (>= 1.0)
"); mkdir -p "$d/opt/nz-test"; echo x > "$d/opt/nz-test/needs"
dpkg-deb -Zzstd --root-owner-group -b "$d" "$O/nz-test-needs-debian_1.0_arm64.deb" >/dev/null
# 3b. depends only on names the firmware Provides (libpng16-16 comes from libpng16-16t64,
#     ssh-server from dropbear): the apt-get shim must accept it
d=$(mk nz-test-needs-virtual 1.0 "Depends: libpng16-16, ssh-server, libstdc++6
"); mkdir -p "$d/opt/nz-test"; echo x > "$d/opt/nz-test/virtual"
dpkg-deb -Zzstd --root-owner-group -b "$d" "$O/nz-test-needs-virtual_1.0_arm64.deb" >/dev/null
# 4. big package to make an interrupted unpack reproducible (40 MiB of incompressible data)
d=$(mk nz-test-big 1.0 ""); mkdir -p "$d/opt/nz-test-big"
i=0; while [ $i -lt 40 ]; do head -c 1048576 /dev/urandom > "$d/opt/nz-test-big/blob$i"; i=$((i+1)); done
dpkg-deb -Zzstd --root-owner-group -b "$d" "$O/nz-test-big_1.0_arm64.deb" >/dev/null
rm -rf "$T"; ls "$O" | grep nz-test
