# Bug list

Evidence tags: **hw:unit1** = reported by the owner on the one tested unit; **emu** = QEMU
raspi3b only (not hardware evidence). History and details: `KNOWN-ISSUES.md`.
Commands were renamed from `cz-*` to `nz-*` in rc8; older reports used the `cz-` names.

## Open

| # | Severity | Bug | Evidence | Status |
|---|---|---|---|---|
| B3 | medium | AdvanceWebUI (M5 app index) downloads but does not start. | hw:unit1 (rc7) | open; cause unknown. Since rc8 a graphical app's output is in `/tmp/nz-app.log` when started from the NimbleZero launcher: start it there and read that file. |
| B7 | low | Vendor audio driver logs `failed to set PGAL/PGAR Select` at load. Speaker and microphone work. | hw:unit1 | open; cosmetic unless a routing problem appears. |
| B8 | low (emulator only so far) | M5 launcher segfaults intermittently when entering some pages; timing-dependent. Not seen on hardware. | emu | open; not root-caused. |
| B9 | low | 55 of the 101 apps of the M5 app index cannot be installed (rc10; rc9: 69, rc8: 83). They need CJK fonts, pygame, systemd, a Wayland desktop, PipeWire, NetworkManager, BlueZ, Node.js or other Debian packages. The Store lists them with what is missing. | emu (rc10, index copy of 2026-11-19) | open; an add-on repository is planned for a future version. |
| B11 | medium | SDL2 has no display driver in this image, so an index app that opens an SDL window (for example `tic80-c0`, which asks for KMS/DRM) installs but cannot show anything. The Store lists it as installable. | emu (rc10: SDL2 reports the video drivers `dummy` and `evdev` only) | open. Needs the GPU stack (Mesa with GBM/EGL) or a framebuffer bridge; not small. |
| B10 | low | "Network info" runs as the normal user and cannot query the Wi-Fi daemon, so its Wi-Fi section says "not running". | source reading (rc8) | open. |
| B13 | low | `fontpreview` (index app) installs, then exits with code 1 at start. Its own log: "Noto CJK UI fonts are missing or unreadable". It needs the Noto CJK fonts for its interface but does not declare them as a dependency, so the Store lists it as installable. | hw:unit1 (exit code 1); emu (same exit code, log read) | open. Goes away with CJK fonts, which are planned for a future version (owner decision). Until then the Store could carry a short list of apps known not to start. |
| B14 | medium | Recorder (official M5 app): recording appears to work and a file is saved, but it cannot be played back. | hw:unit1 | open; cause unknown, details requested (what happens on playback, size of the saved file, `/tmp/nz-app.log`). Not reproducible in the emulator (no sound card). |
| B15 | low | Cardputer TV: sound lags the picture more than on the stock firmware (where it also lags, at a much lower frame rate). | hw:unit1 | open; owner attributes it to the app for now. Not investigated. |

## Fixed after v0.1.0

| # | Bug | Fix | Verified |
|---|---|---|---|
| B17 | After choosing the M5 launcher there was no way back without SSH, and even `nz-admin set launcher native` (the escape Options pointed to) did not stop it: the applaunch package links `APPLaunch.service` into `~/.config/systemd/user/default.target.wants`, and `S60nz-units` started every linked user unit at boot without looking at the launcher setting. Both launchers then drew on the screen. | `S60nz-units` starts `APPLaunch.service` only when the M5 launcher is the chosen one (`nz-admin boot-launcher`, the same test `nz-console` uses). Three ways back that need no SSH: an entry "NimbleZero launcher" in the M5 launcher's app list; Del (or Esc) held while switching on; an empty file `nz-native-launcher` on the boot partition, written from a PC. Options can also change over at once (`nz-admin switch-launcher native\|m5`). | hw (CardputerZero, APPLaunch 0.6.111): launcher set to native with APPLaunch installed and linked, reboot: only the NimbleZero launcher runs. The app-list entry, the boot-partition file and Options > Switch now each changed over (screenshots); M5 chosen + reboot still starts the M5 launcher. Held key: tested with an emulated keyboard, not yet with the real keyboard. |
| B18 | The `apt-get` shim treated every option as a no-op, including `-s`/`--simulate`/`--dry-run`: `apt-get -s remove applaunch` really removed the M5 launcher. | `-s` and its synonyms only print what would be done (`Inst`, `Remv`, `Purg` lines, as apt-get does) and change nothing; `remove --purge` purges; options apt-get takes that change nothing here (`-y`, `-q`, `--no-install-recommends`, ...) are accepted; any other option is refused with apt-get's own message and exit status 100. New test T7. | hw (CardputerZero): `-s`, `--dry-run`, `-sy`, `-s --purge` on the installed APPLaunch print `Remv`/`Purg` and leave it installed; a firmware package is reported as refused; `--bogus` and `-x` exit 100 and change nothing; `-y -q --no-install-recommends install ./x.deb` still installs. |

## Fixed in rc11, waiting for a hardware test

| # | Bug | Fix | Verified |
|---|---|---|---|
| B12 | **PulseAudio refused every program** ("Access denied"; Cardputer TV: `PulseAudio outdev ... Context failed`, `Could not write header`). The sound service runs system-wide and only accepts members of the group `pulse-access`; `zero` and `root` were not in it. The rc8-rc10 release test started a private second service by hand and so never tested the real path. | `zero` and `root` are in `pulse-access`; clients no longer start a second service; the release test now uses the system service as both users and plays through ffmpeg with the app's arguments. On an rc10 card: `sudo nz-rw sed -i 's/^\(pulse-access:x:[0-9]*:pulse\)$/\1,zero,root/' /etc/group`. | hw:unit1 report of the failure (rc10); fix: emu, and hw:unit1 with rc11 (2026-11-19: "cardputer tv works now", sound heard, `pactl` shows PulseAudio in use). |

## Fixed in rc8, waiting for a hardware test

| # | Bug | Fix | Verified |
|---|---|---|---|
| B1 | **Card stopped booting** after removing or upgrading a running program and then using the POWER switch (`Orphan file not empty on read-only fs`, kernel panic). Seen after `dpkg -r applaunch` on rc7. | (1) After a package operation, programs still running from replaced or removed files are restarted or closed, so the system partition is read-only again at once. (2) The system partition is created without ext4's `orphan_file` feature, so even a forced read-only with a deleted file still open no longer blocks the next start. | emu: reproduced on rc7 with a deterministic test (kernel panic at the next boot); the same test on the rc7 image with only `orphan_file` removed boots; rc8 passes tests B1-B5 of `release.script` and boots afterwards (`second-boot.script`). hw:unit1 with rc11 (2026-11-19): M5 launcher removed with `dpkg` from the terminal on the device, POWER switch used, device started again. |
| B2 | System partition stayed writable after a package operation while a program held deleted files. | Same as B1 (1); a program that cannot be closed (the caller itself) is named in the message and the kernel log. | emu |
| B4 | With the M5 launcher installed, the diagnostic screen was drawn on top at boot. | No diagnostic at start. | emu |
| B5 | USB serial gadget loaded although a PC detects nothing (port is charge-only by its label). | Gadget and its console removed. | emu |
| B6 | No camera capture tool. | `v4l2-ctl` (v4l-utils) and ffmpeg are in the image. A camera app comes in the next version. | emu: programs present; no camera in the emulator. |

## To-do list (not bugs)

- Local time: on hardware (rc10) the clock is set from the network and showed UTC because
  no zone had been chosen (the owner had not noticed Options > Time zone). Still to
  confirm on hardware: after choosing a zone, the launcher's clock follows it. Consider
  asking for the zone at first boot.
- Display (see `DISPLAY.md`): solved on hw:unit1 with rc10 + test kit (61.8 frames/s, no
  tearing; the unexplained 7-8 ms per frame was the read-back from the write-combined
  picture buffer) and built into rc11. Still to do: the
  no-sync fallback (never run on hardware); unit 3; long runs, heat and battery
  consumption with the faster panel link; GPU/GLES for apps (bug B11) is separate.
- Emulator test bed: the emulated SD controller stalls on single-sector reads of the FAT
  partition after start-up, and the emulated keyboard loses key presses now and then.
  Both are worked around in the tests, not solved.

- Clean rebuild from the tagged source on the owner's PC.
- Boot log off by default (it stays on in the first release; Options switches it).
- Battery / idle measurement on stock firmware and on this OS (`measure.sh`).
- Camera app and Bluetooth: next version.
- Test the third unit and a second card (unit 2, a Lite, ran rc11 on 2026-11-19).
- `compat_systemd` is still the rc1 build.
