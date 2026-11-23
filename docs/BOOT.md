# Boot chain, card layout, first boot and recovery

## Boot sequence

1. The SoC boot ROM reads `bootcode.bin` from the first FAT partition of the microSD card.
2. `start.elf` (+ `fixup.dat`) reads `config.txt`, loads `bcm2710-rpi-cm0.dtb`, applies the
   `dtoverlay=`/`dtparam=` lines, loads the kernel (`Image`) and passes `cmdline.txt`.
3. Linux mounts `/dev/mmcblk0p2` (ext4) and runs `/sbin/init` (BusyBox init in the minimal
   and compat images).
4. `/etc/init.d/S00nz-early` mounts the boot partition read-only on `/boot` and loads the
   display path first (I2C/SPI bus drivers, IO expander, backlight, panel, keyboard), so the
   LCD shows the console as early as possible. Remaining drivers load through the normal
   coldplug (`mdev`/`udev`).
5. `tty1` (the LCD) runs `nz-diag` once per boot, then a login prompt.

The boot firmware blobs are the standard Raspberry Pi ones from `raspberrypi/firmware`
(Buildroot's pinned commit; redistribution permitted by `LICENCE.broadcom`). The stock image
replaces `start.elf` with an M5Stack build that shows a splash screen; this OS does not ship
that file, so there is no vendor splash.

Device-tree overlays: the standard Raspberry Pi overlays are compiled from the same kernel
tree as the kernel itself; the board overlays are compiled from the M5Stack driver tree with
the upstream recipe (`cpp` + `dtc -@`, `CONFIG_CARDPUTERO_V0_5`).

## Card layout

| # | Offset | Size | Type | Content |
|---|---|---|---|---|
| – | 0 | 4 MiB | – | MBR + alignment gap |
| 1 | 4 MiB | 64 MiB | FAT32 (0x0C), bootable, label `NZBOOT` | firmware, `config.txt`, `cmdline.txt`, `Image`, DTBs, `overlays/` |
| 2 | 68 MiB | 256 MiB (minimal) / 768 MiB (compat) | Linux ext4 (0x83) | system, mounted **read-only** |
| 3 | after 2 | 16 MiB placeholder in the image (type 0xDA, unformatted); on first start grown to the end of the card, formatted ext4 `NZDATA`, then set to 0x83 | `/data`: everything that persists |

## Storage model: why the power switch is safe

The device is normally turned off with the slide switch, so the system is built to lose
power at any moment:

- **The system partition is read-only.** Nothing writes to it during normal use, so it
  cannot be left half-written. `/tmp`, `/run`, `/var/log` are in RAM.
- **Persistent data is on `/data`** (ext4 with a journal, flushed every 5 s): `/home` and
  `/root` (bind mounts of `/data/home`, `/data/root`), `/var/lib` (application settings,
  mixer levels; bind mount of `/data/var/lib`), saved Wi-Fi network
  (`/data/etc/wpa_supplicant.conf`), SSH host keys, downloaded packages. Worst case after a
  sudden cut is the loss of the last few seconds written there.
- **The package database is the one part of `/var/lib` that stays on the system
  partition** (`/var/lib/dpkg` is a link to `/var/dpkg-db`), so it can never disagree with
  the installed files.
- **Deliberate system changes go through `nz-rw`**, which opens the system partition, runs
  one command, syncs and closes it again: `nz-rw passwd`, `nz-rw vi /etc/hostname`.
  `dpkg` (and therefore `apt-get`, `nz-m5`) does this by itself. Cutting power in the middle
  of a package installation is the one risky moment; dpkg's own recovery
  (`dpkg --configure -a`) is tested for that case.
- **What the switch does** (vendor driver `powerfail_suo`, read from source; the 0.5 s delay
  and the LED sequence were observed on hardware): the switch raises an interrupt; after a
  0.5 s debounce the kernel remounts all filesystems read-only, turns the backlight off and
  releases the power latch.
- **"Power off" in the launcher** stops the system and leaves "Slide the POWER switch off"
  on the LCD. The Compute Module cannot remove its own power.

**First start** takes several seconds longer (6.5 s measured on a 16 GB card): "First start: preparing storage..." is on
the screen while the data partition is created. If power is cut during that step it is
simply repeated next time (the partition is marked finished only afterwards).

If `/data` cannot be mounted (damaged or missing partition) the system still boots, says
"Storage problem: settings will not be kept" and uses a RAM disk for `/data`. It never
runs a filesystem repair during boot. To recover the partition from a shell:
`e2fsck -f /dev/mmcblk0p3`, or re-flash the card.

## Files on the boot partition you can edit from any PC

| File | Purpose |
|---|---|
| `config.txt` | normal firmware configuration |
| `config-safe.txt` + `cmdline-safe.txt` | conservative fallback: only the board overlay, HDMI forced on, verbose kernel log on LCD/HDMI/UART. **To use it, rename `config-safe.txt` to `config.txt`.** |
| `wifi.conf.example` | rename to `wifi.conf` and fill in SSID/passphrase to join Wi-Fi at boot |
| `nz-debug` | while this (empty) file exists, every boot writes a log to `nz-logs/`. Delete it to stop the writes. |
| `nz-serial-init` | create this (empty) file to run every init script before the launcher starts (the v0.1.0 order). Normally the launcher starts right after the data partition is mounted and D-Bus, network, SSH, sound and services start behind it (`/etc/init.d/rcS`; their output is in `/run/nz/late.log`). |
| `nz-nodiag` | create this (empty) file to skip the diagnostic UI and go straight to a login prompt |
| `nz-logs/boot-N.txt` | written by the device: hardware report, display/keymap/storage/Wi-Fi state, init script timings, module list, processes, I2C scan, full kernel log (last 5 boots) |
| `nz-logs/diag-report.txt` | written when you press `S` in the diagnostic UI |
| `nz-release.txt` | which image this is |

## Access

| Path | Details |
|---|---|
| LCD + keyboard | diagnostic UI, `Esc`/`Q` for a login prompt |
| SSH | `root` / `cardputer` over Wi-Fi or the Ethernet port (Dropbear). Change the password with `nz-rw passwd`. |
| UART | GPIO14/15 header pins, 115200 8N1 (`enable_uart=1`), login prompt on `ttyS0` |
| USB serial gadget | `ttyGS0` if the USB-C port enumerates as a device |

The default password is public. The image is meant for bring-up on a bench network.

## If the screen stays dark

The system can be fully up with a dark LCD (it happened on rc1). Check in this order:

1. `config.txt` on the `NZBOOT` partition contains `max_framebuffers=0`.
2. Put the card in a PC and read `nz-logs/boot-N.txt`: "LCD fb OK panel-mipi-dbid" means the
   panel driver bound; `fb-activate` output is included from rc2 on.
3. Over SSH / serial: `nz-diag --activate` lights the panel by hand; `cat /sys/class/backlight/*/brightness`
   shows the backlight level.
4. Send the newest `boot-N.txt` back; it has the full kernel log.

## Recovery

- This OS never writes to anything but its own microSD card. Keep the factory card untouched
  and flash a separate one; putting the factory card back restores the device completely.
- Nothing appears on the LCD: read `nz-logs/` on a PC. If the directory does not exist the
  kernel never reached userspace – switch to `config-safe.txt`, connect HDMI or a 3.3 V UART
  adapter, and capture the kernel log.
- A wrong setting in `config.txt` can always be fixed from a PC; there is no on-device
  bootloader state to corrupt.

## Flashing

Use Raspberry Pi Imager ("Use custom"), balenaEtcher, or
`xz -dc cardputerzero-<variant>.img.xz | sudo dd of=/dev/sdX bs=4M conv=fsync`.
Verify the download first: `sha256sum -c --ignore-missing cardputerzero-<variant>.sha256`.


## rc8: first start, accounts, keeping data

- First start: the LCD asks for a password for user `zero` (SSH and sudo). Skipping leaves
  SSH off. The marker `/data/etc/nz/firstboot-done` stops the prompt from returning.
- Accounts: `/etc/shadow` is a link to `/data/etc/shadow`, seeded from `/etc/shadow.dist`
  (root `*`, zero `!`). `nz-admin set-password` changes it (asks for the current one).
- Settings live in `/data/etc/nz/`: `ssh`, `ntp`, `bootlog`, `wifi-country`, `brightness`,
  `screen-off`, `volume`, `launcher`; the time zone is the link `/data/etc/localtime`.
- Reflash: the image ends at the start of partition 3. `S12nz-data` sees type DA, grows the
  partition entry, and if a filesystem labelled `NZDATA` or `CZDATA` that fits is there, it
  only sets the type back to 83 ("Keeping your data..."). Otherwise it formats.
- Clean start: an empty file `nz-reset-data` on the boot partition makes the next start
  format the data partition and delete the file. Options > Erase all data writes it.
- Package operations: `nz-rw` restarts services and closes programs that still run from
  replaced or removed files, then returns the system partition to read-only. The system
  partition has no ext4 `orphan_file` feature, so a forced read-only by the switch cannot
  make it unmountable (BUG-LIST B1).
- Serial consoles: UART only. The USB gadget console is gone.
