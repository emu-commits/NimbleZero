# NimbleZero

A small Linux system for the **M5Stack Cardputer Zero** (Raspberry Pi Compute Module 0),
built with Buildroot. It starts in about 7 seconds to a keyboard launcher, runs unmodified
M5Stack Cardputer Zero app packages, and drives the LCD at its full refresh rate without
tearing.

**Unofficial firmware. Not an M5Stack product, and not endorsed by M5Stack or Raspberry Pi
Ltd.** Licence of the project's own code: GPL-2.0 (`COPYING`). No warranty.

## Status: v0.1.0, first public release

Tested by one person on two devices (a Cardputer Zero and a Cardputer Zero Lite), plus an
emulator test suite. That is thin evidence for a public release; treat it as an early
version.

- **Use a spare microSD card.** Keep the card your device came with untouched, so you can
  always go back to the stock firmware by swapping cards. NimbleZero never writes to
  anything but the card it runs from.
- What was verified on hardware and what was not: `docs/RELEASE-NOTES.md`.
- What does not work: `docs/KNOWN-ISSUES.md`.

## Install

1. Download `nimblezero-v0.1.0.img.xz` from this repository's Releases page and
   check it against the `.sha256` file.
2. Write it to a spare microSD card (4 GB or larger) with Raspberry Pi Imager ("Use
   custom"), balenaEtcher or `dd`.
3. Optional: on the card's `NZBOOT` partition, rename `wifi.conf.example` to `wifi.conf`
   and put your network in it. You can also set up Wi-Fi later from the device.
4. Put the card in the Cardputer Zero and switch it on.

The first start prepares the card and asks on the LCD for a password for the user `zero`
(typed twice, 6 characters or more). It is the password for SSH and `sudo`. Enter alone
skips it; SSH then stays off until you set one under Options.

The published image is the regular (`compat`) build: launcher, Store, M5Stack app
packages, Python, ffmpeg, PulseAudio; about 240 MB installed. A `minimal` build (console,
diagnostics, SSH and Wi-Fi only; about 46 MB) exists as a build option (see "Building")
and is not published as an image for this release.

Updating: write a newer image over the same card. Your password, Wi-Fi networks, settings
and `/home/zero` are kept (they live in a separate data partition); apps installed from
the Store are not. If you build your own images, use the same variant as before.

## Using it

- **Launcher keys:** F / X up and down, Z / C page up and down, Enter starts, O opens
  Options, Del removes the selected app (it asks first; NimbleZero's own apps cannot be
  removed). The arrow keys with Fn work too. Ctrl+Alt+Backspace closes a hanging app.
- **Options:** brightness, screen-off time, volume, Wi-Fi network and country, time zone,
  which launcher starts (NimbleZero's or M5Stack's), password, services (SSH, network
  time), erase all data.
- **Store:** installs M5Stack's Cardputer Zero apps (from M5Stack's own package index and
  GitHub releases) and the M5Stack launcher. Apps that need software this system lacks are
  listed with what is missing.
- **SSH:** `ssh zero@<address>` (the address is shown under Options > Services). `root`
  cannot log in; use `sudo`.
- **Power switch:** always safe. The system partition is read-only; your files are in
  `/home/zero`. To change a system file: `sudo nz-rw <command>`.
- **Logs:** each start writes `nz-logs/boot-N.txt` to `NZBOOT`, readable on a PC. Attach
  the newest one to a bug report.

## If something goes wrong

| Problem | What to do |
|---|---|
| Screen dark or garbled after flashing | On a PC, create an empty file `nz-display-original` on `NZBOOT`. The display then uses the vendor's settings (slower, with tearing). Please report it with the boot log. |
| Still nothing | Rename `config-safe.txt` to `config.txt` on `NZBOOT` (see `docs/BOOT.md`). |
| Forgot the password, or want a clean start | Create an empty file `nz-reset-data` on `NZBOOT`: the next start erases settings and `/home`. |
| Back to stock | Put the original card back in. |

## What is in it

- Raspberry Pi kernel 6.18 with M5Stack's board drivers; glibc; BusyBox init (no systemd).
- NimbleZero launcher, Options, Store, terminal, diagnostics, written for the 320x170 LCD
  and the built-in keyboard.
- A runtime for M5Stack's `.deb` app packages: `dpkg`/`apt`, a small stand-in for the
  systemd services those packages expect, D-Bus.
- Python 3 with Pillow, NumPy and evdev; ffmpeg; PulseAudio; SDL2 (sound and input only);
  PNG and JPEG libraries.
- Display path: 100 MHz panel clock, synchronised to the panel, 61.8 frames per second
  (`docs/DISPLAY.md`).

Not in it yet: Bluetooth, a camera app, GPU acceleration, CJK fonts.

## The NimbleZero repositories

| Repository | Content |
|---|---|
| **NimbleZero** (this one) | source of the system, documentation, and the released images with their source archives |
| **NimbleZero-dependencies** | libraries and runtimes that apps need and the base image does not carry (planned; empty at v0.1.0) |
| **NimbleZero-apps** | apps written for NimbleZero (planned; empty at v0.1.0) |

## Build it yourself

```sh
./build.sh compat      # or: minimal
```

Buildroot 2026.02.3, Bootlin toolchain, all versions pinned; builds work offline once the
sources are downloaded. Details: `docs/BUILD.md`. Tests: `docs/TESTING.md`.

## Documentation

| File | Content |
|---|---|
| `docs/RELEASE-NOTES.md` | what this release contains, test results, what is not verified |
| `docs/KNOWN-ISSUES.md` | what does not work; history of hardware results |
| `docs/BUG-LIST.md` | open bugs and the to-do list |
| `docs/DISPLAY.md` | the display path, its switches, how to go back |
| `docs/BOOT.md` | boot chain, card layout, boot-partition files, recovery |
| `docs/M5-COMPAT.md` | what M5Stack software needs and how it is provided |
| `docs/APP-DEVELOPMENT.md` | writing apps: SDK, packaging |
| `docs/HARDWARE.md` | hardware facts and support matrix |
| `docs/HARDWARE-TEST-CHECKLIST.md` | the checks run on real devices |
| `docs/BUILD.md`, `docs/TESTING.md` | building and testing |

## Licences

Everything written for this project is GPL-2.0 (`COPYING`), including the SDK header
`nzui.h`: a program that includes it is a GPL-2.0 work; programs that do not use it are not
affected. Every other component keeps its own licence. The image carries all licence texts
and a package list in `/usr/share/licenses`; the same list is published with each release
(`*.licence-manifest.csv`), together with the source archives of every package.

The image contains a few binary-only files, redistributed unmodified under their vendors'
terms (texts included in the image and next to the download):

- Raspberry Pi boot firmware: Broadcom / Raspberry Pi licence (use on Raspberry Pi devices);
- Wi-Fi/Bluetooth firmware for the Compute Module 0's radio chips: Cypress, Synaptics and
  Broadcom licence agreements (use with those vendors' chips);
- BMI270 motion-sensor configuration data: Bosch Sensortec, BSD-3-Clause.

**No M5Stack application binaries are included.** The Store downloads them from M5Stack's
own servers onto your device when you ask for them.
