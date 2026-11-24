# M5Stack ecosystem compatibility: findings and test results

All statements here come from inspecting and running the real upstream artifacts
(release `.deb` files from `github.com/CardputerZero/*`, fetched 2026-11-17) and reading
`CardputerZero/launcher`, `CardputerZero/pi-gen` and `m5stack/m5stack-linux-dtoverlays`.
Runtime results are from QEMU (`TESTING.md` lists what that does and does not prove).
Raw data: `results/compat/deb-inspection.json`, `results/compat/lifecycle/`.

## 1. What the upstream software actually requires

### Application packages (`m5cardputerzero-*`, FactoryTest, ...)

| Property | Finding |
|---|---|
| Format | `.deb`, `Architecture: arm64`, zstd-compressed members |
| Payload | one self-contained ELF + assets under `/usr/share/APPLaunch/…`, one `.desktop` file in `/usr/share/APPLaunch/applications/` |
| Linked libraries | only `libc`, `libm`, `libstdc++`, `libgcc_s` (LVGL etc. are linked statically); Music also `libz` |
| Symbol versions | at most `GLIBC_2.38`, `GLIBCXX_3.4.32` -> satisfied by glibc 2.41 / gcc 14 in this OS |
| Maintainer scripts | none |
| Display / input | fbdev (`/dev/fb_lcd`, `/dev/fb0`) and evdev |
| Audio | miniaudio: tries `libpulse.so.0` at run time, falls back to ALSA |
| Declared dependencies | `libc6, libstdc++6, libgcc-s1` plus, per app, `libpulse0`, `pulseaudio-utils`, `ffmpeg`, `zlib1g` |

### APPLaunch (package `applaunch`, 47 MB, contains APPLaunch, AppStore, Calculator, LaunchWizard, ZClaw)

| Area | Requirement (source) |
|---|---|
| Libraries | `libcurl.so.4`, `libfreetype.so.6`, `libglib/gio/gobject-2.0`, `libinput.so.10`, `libxkbcommon.so.0` (+ X11 Compose data and a UTF-8 locale), `libssl/libcrypto.so.3`, `libcrypt.so.1` (readelf) |
| Service model | **systemd user service** `APPLaunch.service` of UID 1000 with lingering; `Wants=pipewire-pulse.service` (unit file) |
| postinst / prerm | `systemctl --global/--user`, `loginctl enable-linger`, `runuser`, `getent`; falls back to an "offline enable" symlink in `~/.config/systemd/user/default.target.wants/` when systemd is not PID 1 (script) |
| Self-update | `applaunch-updater.service` (system unit, started by the UI through polkit): downloads `applaunch_arm64.deb` from the `launcher-latest` GitHub release, `dpkg -i`, health-checks with `systemctl --user is-active/show`, rolls back with the cached previous `.deb` (script) |
| App updates | `applaunch-apps-updater`: GitHub release lookup, `apt-get update`, **`apt-get install -y ./pkg.deb`** – dependency resolution against Debian repositories (script) |
| AppStore | `apt-get`, `dpkg-query`, `dpkg-deb`, `sudo`, reads `/var/lib/dpkg/status`; registry JSON on GitHub Pages / Aliyun (strings) |
| Settings | NetworkManager (`nmcli`), BlueZ over the D-Bus **system bus**, `timedatectl`, `rfkill`, sysfs backlight/LEDs/battery (strings) |
| Privileges | user in group `sudo`, polkit rule allowing that group to start the three updater units |
| Licence | repository is MIT, but bundles SimpleBLE under BUSL-1.1 -> **not shipped in the images**; fetched on the device by `nz-m5` |

In short: the *apps* need little more than a glibc and a framebuffer; *APPLaunch and its
update machinery* assume a Debian system – APT with Debian repositories, systemd with
logind + PAM user sessions, polkit, D-Bus, NetworkManager, BlueZ, PipeWire.

## 2. What was implemented

| Component | Implementation | Upstream code changed |
|---|---|---|
| Package manager | **real dpkg 1.22.22** (the Debian trixie version; C tools only) | none |
| Dependency satisfaction | dpkg database seeded at build time with held "firmware" entries for what the image provides (`libc6`, `libstdc++6`, `libgcc-s1`, `zlib1g`, `libssl3t64`, `libcurl4t64`, `libglib2.0-0t64`, `libinput10`, …; 25 entries) from `package/nz-compat/files/provided.map` – an entry is only written if the library is really in the image | – |
| Protecting the Buildroot system | every firmware file is owned by the essential package `nz-firmware`; a guard at `/usr/bin/dpkg` refuses any `.deb` that ships a firmware file, also with `--force-*` | – |
| APT | **not ported.** An `apt-get` front end covers what the updaters call: `update` (no-op), `install ./x.deb` (dependency check against the dpkg database, then `dpkg -i`), `remove`, `purge`; `-s`/`--simulate` only prints what would be done, and options it does not know are refused. It never contacts a Debian mirror. | none |
| Runtime libraries | curl, freetype, glib, libinput, xkbcommon + xkb data, libX11 locale data, OpenSSL, libxcrypt, eudev, **D-Bus system bus**, `ldconfig`, `getent`, `sudo`, UID 1000 user `cardputer` | none |
| Service handling, config A | BusyBox init + `nz-unit` (runs simple unit files) + `systemctl`/`loginctl`/`runuser` shims; honours the upstream "offline enable" symlink | none |
| Service handling, config B | real systemd 259 + logind + PAM + D-Bus (`nz_compat_systemd_defconfig`) | none |
| Fetching upstream packages | `nz-m5 install-launcher`, `nz-m5 install <Repo>` download release assets from GitHub on the device | – |
| Coexistence | native launcher reads `/usr/share/APPLaunch/applications` too; when APPLaunch is enabled and chosen under Options > Launcher at start it owns the LCD instead. Ways back without SSH: "NimbleZero launcher" in its app list, Del held while switching on, or an empty file `nz-native-launcher` on the boot partition | – |

Not implemented: APT/Debian repositories, polkit, NetworkManager, BlueZ userspace,
PipeWire/PulseAudio, ffmpeg, the M5Stack splash/`fb_load`, ADB.

## 3. Application compatibility matrix

"Installs" = `apt-get install ./pkg.deb` through the shim on the compat image.

| Package (versions tested) | Declared deps beyond libc/libstdc++/libgcc | Installs | Runs | Notes |
|---|---|---|---|---|
| m5cardputerzero-compass 0.2.4, 1.0.1 | – | yes; upgrade 0.2.4 -> 1.0.1 ok | binary loads (`ldd` clean); not started (needs the IMU) | |
| m5cardputerzero-ir-remote 0.1.4 | – | yes | **yes** – draws its UI on the framebuffer as UID 1000 (`m5-app-ir-remote.png`) | IR hardware untested |
| m5cardputerzero-keyboard-guide 1.0.1 | `libpulse0` | **refused** (dependency) | – | would fall back to ALSA |
| m5cardputerzero-piano 0.1.1 | `libpulse0` | **refused** | – | |
| m5cardputerzero-recorder 0.1.7, 0.1.8 | `libpulse0`, `pulseaudio-utils` | **refused** | – | |
| m5cardputerzero-music 0.1.7 | `zlib1g`, `libpulse0`, `pulseaudio-utils` | **refused** | – | |
| m5cardputerzero-files 1.0.2, 1.0.3 | `ffmpeg` | **refused** | – | |
| applaunch 0.6.105, 0.6.106 | `xdg-user-dirs` (stub provided) | yes; upgrade ok; postinst/prerm run unmodified | **yes, with an open stability issue** (below) | Store, Wi-Fi/Bluetooth settings, updater not functional |

Five of the seven application packages examined are refused only because of PulseAudio or
ffmpeg dependencies. Adding Buildroot's `pulseaudio` and `ffmpeg` packages (and their
`provided.map` lines, which already exist) would lift that; it was not done because it adds
a sound server and a large codec library to the base image and none of it can be exercised
without hardware.

### APPLaunch run-time observations (QEMU, USB keyboard aliased to the board keyboard path)

- Renders its normal carousel (Store, CLI, Python, ZClaw, SSH, …) and reacts to keys
  (`results/compat/lifecycle/applaunch-0.6.10*-*.png`).
- **Without a D-Bus system bus it crash-loops** (SIGSEGV every 10-15 s). The faulting PC is a
  heap address shifted right by 12 bits – the signature of glibc's safe-linking value in a
  freed chunk being used as a function pointer, i.e. a use-after-free in APPLaunch's
  Bluetooth worker error path. With `dbus-daemon` running the loop disappears. D-Bus is
  therefore part of the compat image.
- **Open issue:** with D-Bus present, 2 of 4 full test runs still recorded one or two
  segfaults while entering carousel pages (one run on 0.6.105, one on 0.6.106); the other two
  runs, including the final one, had none. Not root-caused. It may be another missing
  service (NetworkManager, BlueZ, PipeWire), the emulated environment, or an upstream bug
  that also exists on the stock image. The service restarts within a second each time.
- Warnings that remain: `libcurl.so.4: no version information available` (Debian builds
  curl with versioned symbols; functionally harmless), `unzip: can't open /var/template.zip`
  (a pi-gen-installed file this OS does not have), BlueZ agent registration fails (no BlueZ).

## 4. Package lifecycle tests (config A, final run: 53/53)

`tests/compat/lifecycle.script`, executed inside the booted image by `tests/qemu-boot.py`.

| # | Requirement from the project brief | Test | Result |
|---|---|---|---|
| 1 | install an existing package | A1 compass 0.2.4, A4 ir-remote, L1 applaunch 0.6.105 (upstream postinst runs) | pass |
| 2 | launch it through APPLaunch | L4-L6: APPLaunch itself starts as UID 1000 and stays up; **launching an installed app from inside APPLaunch was not exercised** – only APPLaunch start and the app binary started directly (A6) | partial |
| 3 | upgrade to a newer version | A3 compass -> 1.0.1; L8 applaunch -> 0.6.106; T2 test package 1.0 -> 2.0 | pass |
| 4 | preserve user configuration | L7/L9 files in `~/.config` and `/var/cache/APPLaunch` survive; T2 edited conffile kept | pass |
| 5 | uninstall | U1, U2 (upstream prerm runs), T4 remove vs. purge | pass |
| 6 | recover from interrupted installation | I1 SIGKILL during unpack -> `half-installed` detected; I2 reinstall completes; I3 same for an APPLaunch upgrade | pass |
| 7 | preserve the underlying Buildroot system | H1-H4 hostile package refused (plain, `--force-overwrite`, `--force-all`), `nz-firmware` cannot be removed; F1 sha256 of every firmware file identical before/after the whole run | pass |
| – | rollback | T3 downgrade to the previous version keeps config | pass |
| – | unmet dependencies | A5, T5 refused with the missing names | pass |

A first version of the protection (dpkg `path-exclude` only) **failed** this suite: a forced
install followed by a purge deleted `/lib/libc.so.6`. The recorded run is kept in
`results/compat/qemu-run1-protection-bug/`.

Multiple real historical versions were available for APPLaunch, Compass, Files and Recorder,
so upgrades were tested with upstream packages; the `nz-test-*` packages
(`tests/compat/make-test-debs.sh`) add conffile, maintainer-script, hostile and
interrupted-install cases that no upstream package exercises.

**What "updates work" means here:** a newer upstream `.deb` installs over an older one with
plain dpkg, without rebuilding the OS. The upstream *automatic* update paths (in-UI updater
via polkit, AppStore, `apt-get` dependency resolution) are not functional on config A and
were not exercised on config B.

## 5. systemd comparison

See `ARCHITECTURE-DECISION.md` for numbers. Dependency findings:

| Dependency | Needed by | Config A (BusyBox + shims) | Config B (systemd) |
|---|---|---|---|
| system services / `systemctl start` | updater units | `nz-unit` runs simple oneshot/simple units; no polkit, so only root can start them | native; polkit still missing |
| user services, lingering | `APPLaunch.service` | emulated: user units started at boot as that user | native, **requires logind + PAM** (without PAM `user@1000` fails: "XDG_RUNTIME_DIR is not set") |
| `systemctl is-active / show MainPID` | updater health checks | shim | native |
| D-Bus system bus | BlueZ client inside APPLaunch | `dbus-daemon` from init script | `dbus-daemon` under systemd |
| udev | libinput (APPLaunch input) | eudev | systemd-udevd |
| cgroups, socket activation, timers | not used by the inspected units | – | available |
| journald | nothing requires it | BusyBox syslogd ring buffer | journald |
| polkit | starting updater units from the UI | absent | absent |


## rc8: Store, multimedia libraries, accounts

- **Store** (`nz-store`, launcher entry): official M5Stack apps from
  `github.com/CardputerZero/<repo>` releases (list in `/usr/share/nz/store-official.list`)
  and the M5 app index `https://cardputerzero.github.io/packages/dists/stable/main/binary-arm64/Packages`
  (absolute download URLs with SHA-256). The privileged half is `nz-store-backend`, reached
  through `sudo nz-admin store ...`. With the index copy of 2026-11-18 (101 apps), the rc8
  image can install 18 index apps; 83 need packages it lacks. Most frequent missing
  packages in that index: python3 (51 apps), python3-pil (32), libjpeg62-turbo (20),
  python3-numpy (18), fonts-dejavu-core (18), python3-evdev (16), fonts-noto-cjk (9),
  libsdl2-2.0-0 (7).
- **M5Stack packages refused before** for `ffmpeg`, `libpulse0`, `pulseaudio-utils` now
  install (emulator): music 0.1.7, recorder 0.1.8, files 1.0.3, piano 0.1.1,
  keyboard-guide 1.0.1; their programs resolve every library. They have not been run.
- **ffmpeg 6.1.5** configured with: gpl, gnutls, postproc, libx264, libx265, libvpx,
  libdav1d, libopus, libmp3lame, libvorbis, libtheora, libspeex, libopenjpeg, libass,
  libfreetype, libharfbuzz, libfribidi, libxml2, libsoxr, libdrm, alsa, libpulse, libv4l2;
  all built-in encoders, decoders, muxers, demuxers, filters and protocols; no nonfree.
  Not matched to Debian 13's package (list of Debian's options from memory, not checked
  against the package): version (7.1 there, so different library names), ffplay/SDL2,
  libaom, libwebp, libsvtav1, librav1e, libzimg, libvidstab, libxvid, libjxl, librist,
  libsrt, libssh, libbluray, libopenmpt, libgme, libcodec2, libgsm, libshine, libtwolame,
  libsnappy, librubberband, libzmq, libzvbi, lv2, OpenAL/OpenCL/OpenGL outputs.
- **Accounts**: apps started from the NimbleZero launcher run as `zero` (UID 1000, the
  UID the M5Stack packages assume) instead of root. The M5 launcher's own Store asks for
  the sudo password. `sudo` no longer works without a password except for `nz-admin`.
- New firmware names known to the dependency check: pulseaudio, libv4l-0(t64), v4l-utils,
  iw, tzdata, libpng16-16(t64), libzstd1, libopus0, libdrm2, openssl, libvorbis0a,
  libmp3lame0, libbz2-1.0, udev, unzip (each only if its file is in the image).

## rc9: Python

- Python 3.14.5 (Debian 13 has 3.13) with Pillow 12.0.0, NumPy 2.4.0, evdev 1.9.2, qrcode 8.2,
  requests 2.33.1; DejaVu fonts, also reachable as `/usr/share/fonts/truetype/dejavu`;
  `/usr/lib/python3/dist-packages` is on the module search path. Known to the dependency
  check as python3, python3-minimal, libpython3-stdlib, python3-pil, python3-numpy,
  python3-evdev, python3-qrcode, python3-requests, fonts-dejavu-core.
- With the index copy of 2026-11-19 (101 apps): 32 index apps installable, 69 not.
  `airfiles` 0.4.0 (Python, Pillow, qrcode, fonts) installed through the Store helper and
  rendered its home screen to a file in the emulator (320x170, 706 colours); it was not run
  on a display.
- Not provided: `libjpeg62-turbo` (jpeg-turbo is built as `libjpeg.so.8`; Debian programs
  want `libjpeg.so.62`), python3-pygame, python3-cryptography, python3-gi, python3-dbus,
  python3-aiohttp, SDL2, CJK fonts. A Python extension module compiled for Debian's
  Python 3.13 would not load in 3.14; pure-Python apps are not affected.

## rc10: PNG, JPEG, SDL2

- libpng 1.6.58 (`libpng16-16`, `libpng16-16t64`), jpeg-turbo 3.1.2 built with the classic
  interface so the library is `libjpeg.so.62` (`libjpeg62-turbo`), SDL2 2.32.10 with
  SDL2_ttf 2.24.0, SDL2_image 2.8.12, SDL2_mixer 2.6.3 (`libsdl2-2.0-0`, `libsdl2-ttf-2.0-0`,
  `libsdl2-image-2.0-0`, `libsdl2-mixer-2.0-0`).
- Index copy of 2026-11-19: 46 index apps installable, 55 not.
- SDL2 video drivers in this build: `dummy`, `evdev` (input). Audio: alsa, dsp, disk, dummy.
  `fontpreview` 0.4.7 and `refract-pocket` 6.5 install and resolve every library; both
  draw to `/dev/fb0` themselves. `tic80-c0` sets `SDL_VIDEODRIVER=kmsdrm` and cannot display.
