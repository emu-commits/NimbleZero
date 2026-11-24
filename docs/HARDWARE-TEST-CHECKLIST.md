# Hardware test checklist: v0.1.0 (NimbleZero)

**v0.1.0 check (short), reported 2026-11-20: Wi-Fi works on v0.1.0 on both devices** (the
Cardputer Zero and the Cardputer Zero Lite). Flash `nimblezero-v0.1.0.img.xz` over
the rc11 card.
1. It starts to the launcher; About shows v0.1.0.
2. **Wi-Fi connects** (the only function the v0.1.0 changes could affect), on both devices
   if possible. On the Lite, `dmesg | grep brcmfmac` over SSH tells which radio chip it has.
3. Optional: G4 below (display fallback), H3 (Music).

Everything below is the rc11 checklist with the results reported so far.

**New in rc11 - do these first (blocks G and H at the end of this file), then C-F.**
Flash `nimblezero-compat-rc11.img.xz` over the rc10 card; your data partition is kept.
If the screen stays dark or garbled: put the card in the PC and create an empty file
`nz-display-original` on `NZBOOT` (vendor display behaviour), and report it.

On hardware so far (hw:unit1): with rc10, A pass, B pass except B5 (clock in UTC, no zone
chosen); display measurements with rc10 + test kit: `DISPLAY.md`.

**rc11 on a second device, 2026-11-19 late evening (hw:unit2, a Cardputer Zero Lite, same
card):** boots; Doom runs fine; the benchmark in Diagnostics shows 62 frames/s with no
display problems; IMU, magnetometer and camera are shown as absent, as expected on the
Lite; "nothing out of the ordinary with a few other spot checks".

**rc11 on unit 1, 2026-11-19 evening** (image confirmed by the owner afterwards):
- A all pass. B all pass.
- C1-C5 pass. C6: Recorder seems to record and saves a file, but cannot play it back (bug
  B14). C7: `airfiles` draws to the screen. C8: `fontpreview` does not start, exit code 1
  (bug B13: it needs Noto CJK fonts).
- E: data is kept after a flash.
- Cardputer TV works with sound (bug B12 fixed); sound lags the picture more than on the
  stock firmware (B15).
- D (reported 2026-11-19, late): the M5 launcher was removed with `dpkg` typed in the
  terminal on the device, then the POWER switch was used; the device started again. On rc7
  this sequence left the card unbootable. Not stated: whether the M5 launcher was the
  program running on the screen at that moment (the emulator test covers that case).
- Not reported yet: F, G2 and G4 (`nz-panel auto` on rc11, the fallback test), H3 (Music),
  unit 3.

Results of rc1-rc7 are in `KNOWN-ISSUES.md`.

Use the separate test card. Blocks A and B were done on rc10; with rc11 a quick look at A3,
A4 and B1 is enough unless something looks different.

After each numbered block, the newest `nz-logs/boot-N.txt` from the boot partition
(`NZBOOT`) is the most useful thing to send if something looks wrong.

## A. First start (most likely place for a new problem)

- [ ] A1 The screen lights and shows "NimbleZero starting...". Note what the next line
      says: "Keeping your data..." (the rc7 data partition was adopted) or
      "First start: preparing storage...".
- [ ] A2 "Welcome to NimbleZero" asks for a password for user `zero`. Type one (6+
      characters) twice. Does it say "Password set" and "SSH is on"? If the two entries
      "differ" although you typed the same, note which keys you used.
- [ ] A3 The launcher appears, titled "NimbleZero". **If the screen stays dark or shows a
      login prompt instead, stop here and send the boot log**: the launcher now runs as a
      normal user and that has never been tried on the real display.
- [ ] A4 Top bar: battery outline with a level and a percentage; `+` appears when the
      charger is plugged in.

## B. Launcher keys and menus

- [ ] B1 Without Fn: F moves up, X down, C a page down, Z a page up. With Fn the arrow keys
      still work.
- [ ] B2 Press O: Options opens. Change Brightness (does the screen change at once?),
      Screen off after, Time zone. Esc goes back.
- [ ] B3 Options > Volume: does the speaker volume change (play something, or note
      "No volume control was found")?
- [ ] B4 Options > Wi-Fi network: join your network as before. Options > Wi-Fi country:
      set yours.
- [ ] B5 After Wi-Fi is up: does the clock in the top bar become correct within a minute?
      (Services > "Set the clock now" forces it and prints the result.)
- [ ] B6 Services > SSH server: note the address shown. From the PC: `ssh zero@<address>`
      with your password works; `ssh root@<address>` is refused. Switch SSH off in the menu:
      the PC can no longer connect. Switch it on again.
- [ ] B7 In the SSH session: `sudo id` asks for your password and prints `uid=0`.
- [ ] B8 Snake, Diagnostics, Terminal, Power off still work from the launcher.

## C. Store

- [ ] C1 Launcher > Store > "Refresh the app list". How many apps does it report?
- [ ] C2 Install "IR Remote" (official app) from the Store. Start it from the launcher.
- [ ] C3 Install one app from "Can be installed" in the index part (for example `kanstl` or
      `craps`). Does it install, appear in the launcher and start?
- [ ] C4 Open an app under "Need software this OS lacks": does the page name what is missing?
- [ ] C5 Remove the app from C3 in the Store.
- [ ] C5b Install it again, then remove it from the launcher: select it, press Del, then
      "Yes, remove" (the question starts on "No"). Del on a NimbleZero app (for example
      Diagnostics) says it cannot be removed.
- [ ] C6 Music or Recorder (official): do they install now, start, and play or record sound?
- [ ] C7 Install a Python app from the index, for example `airfiles`. Does it start and draw
      its screen? (In the emulator it only drew to a file.)
- [ ] C8 Install `fontpreview` or `refract-pocket` (they use SDL2 for sound and input and
      draw to the screen themselves). Does it start and show something? Then, if you like,
      `tic80-c0`: I expect it to install and then show nothing (SDL2 has no display driver here).

## D. The rc7 failure, repeated on purpose

- [ ] D1 Store > M5 Launcher > Install. Options > Launcher at start > M5 launcher. Switch
      off with the POWER switch, switch on: the M5 launcher runs.
- [ ] D2 Over SSH: `sudo dpkg -r applaunch`. It should print "stopping APPLaunch.service".
      **Then use the POWER switch** (the sequence that made rc7 unbootable) and switch on.
      Expected: it boots to the NimbleZero launcher.
- [ ] D3 If D2 fails to boot: reflash; your data should still be there (that is test E).

## E. Data across a reflash

- [ ] E1 Create a file (`echo hi > ~/keep.txt` in Terminal). Flash the same image again.
      Boot: "Keeping your data...", no password prompt, Wi-Fi reconnects, `keep.txt` is there.
      Apps installed from the Store are gone (expected).
- [ ] E2 Optional: Options > Erase all data, type ERASE. After the restart the password
      prompt appears again and `keep.txt` is gone.

## F. Carried over

- [ ] F1 Battery / idle measurement against stock firmware (`measure.sh`), when convenient.
- [ ] F2 Camera: `v4l2-ctl --list-devices` and `v4l2-ctl -d /dev/video0 --all` over SSH;
      send the output. (No camera app yet.)

## G. Display (new in rc11)

The numbers to compare with are from unit 1 with rc10 + test kit (`DISPLAY.md`).

1. Boot. Text during start, the first-start/launcher screens: upright, nothing mirrored,
   nothing left over from an earlier screen?
2. `sudo nz-panel auto` over SSH; send `~/panel-auto.txt`. Expected on unit 1: sync pin
   62 pulses/s; tests C and E near 62 per second; bars solid in B-E.
3. Use launcher, Options, console typing, Store for a few minutes. Anything misplaced,
   flickering, sluggish?
4. Fallback test: `sudo nz-panel dcs 34` (turns the panel's sync output off), then
   `sudo nz-panel bars 5`. Expected: a short stutter, then bars at about 100 per second with
   tearing, and `te_given_up=1`. Restart afterwards. **This code has never run on hardware.**
5. Units 2 and 3: steps 1-3. These are the first runs of this display path on those units.

## H. Sound through PulseAudio (new in rc11)

1. `pactl list short sinks` as user zero: is there a sink other than `auto_null`?
2. Cardputer TV (or `ffmpeg -f lavfi -i sine=frequency=440:duration=2 -f pulse default`):
   sound from the speaker?
3. An M5Stack app that worked before (Music): still plays?
