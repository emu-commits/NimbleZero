#!/usr/bin/env python3
"""Structural validation of a Cardputer Zero SD-card image (no root needed).

Checks the things a Raspberry Pi boot actually depends on: MBR layout, FAT boot
files, firmware config vs. shipped overlays, overlay applicability against the
CM0 base DTB, kernel image format, kernel/modules version match, rootfs
consistency, init, and that every ELF file is AArch64 with resolvable libraries.

usage: check-image.py sdcard.img [--json report.json]
needs: mtools, e2fsprogs (e2fsck, debugfs), device-tree-compiler (fdtoverlay, dtc), binutils (readelf)
"""
import sys, os, struct, subprocess, tempfile, json, re, shutil

img = sys.argv[1]
results = []
def check(name, ok, detail=""):
    results.append({"check": name, "ok": bool(ok), "detail": str(detail)[:300]})
    print(("PASS " if ok else "FAIL ") + name + (("  - " + str(detail)[:200]) if detail else ""))
    return ok
def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, errors="replace", **kw)

size = os.path.getsize(img)
with open(img, "rb") as f:
    mbr = f.read(512)
check("MBR boot signature 55AA", mbr[510:512] == b"\x55\xaa")
parts = []
for i in range(4):
    e = mbr[446 + 16 * i: 462 + 16 * i]
    boot, ptype, lba, n = e[0], e[4], struct.unpack("<I", e[8:12])[0], struct.unpack("<I", e[12:16])[0]
    if ptype: parts.append((i + 1, boot, ptype, lba, n))
check("three partitions (boot, system, data)", len(parts) == 3, parts)
p1, p2 = parts[0], parts[1]
p3 = parts[2] if len(parts) > 2 else None
if p3:
    check("p3 (data) is type DA (created or adopted at first start) and begins exactly where the image file ends, so flashing never overwrites it",
          p3[2] == 0xDA and p2[3] + p2[4] <= p3[3] and p3[3] * 512 == size, f"{p3} image={size // 512} sectors")
check("p1 is FAT32-LBA (0x0C) and bootable", p1[2] == 0x0C and p1[1] == 0x80, hex(p1[2]))
check("p2 is Linux (0x83)", p2[2] == 0x83, hex(p2[2]))
check("partitions inside image and not overlapping", p1[3] + p1[4] <= p2[3] and (p2[3] + p2[4]) * 512 <= size,
      f"p1 {p1[3]}+{p1[4]} p2 {p2[3]}+{p2[4]} img {size//512} sectors")
check("p1 starts on a 1 MiB boundary", p1[3] % 2048 == 0, p1[3])

tmp = tempfile.mkdtemp(prefix="nzimg.")
boot = os.path.join(tmp, "boot"); os.mkdir(boot)
fat = f"{img}@@{p1[3] * 512}"
r = run(["mcopy", "-s", "-n", "-i", fat, "::", boot])
check("FAT boot partition readable (mtools)", r.returncode == 0, r.stderr.strip())
B = lambda *p: os.path.join(boot, *p)
for f in ["bootcode.bin", "start.elf", "fixup.dat", "config.txt", "cmdline.txt", "bcm2710-rpi-cm0.dtb",
          "config-safe.txt", "cmdline-safe.txt"]:
    check(f"boot file {f}", os.path.isfile(B(f)) and os.path.getsize(B(f)) > 0)

def parse_cfg(path):
    kv, ovl = {}, []
    for line in open(path):
        line = line.split("#")[0].strip()
        if line.startswith("dtoverlay="): ovl.append(line[10:].split(",")[0])
        elif "=" in line and not line.startswith("["): k, v = line.split("=", 1); kv[k] = v
    return kv, ovl
for cfgname in ["config.txt", "config-safe.txt"]:
    if not os.path.isfile(B(cfgname)): continue
    kv, ovl = parse_cfg(B(cfgname))
    check(f"{cfgname}: arm_64bit=1", kv.get("arm_64bit") == "1")
    kern = kv.get("kernel", "kernel8.img")
    kp = B(kern)
    ok = os.path.isfile(kp)
    if ok:
        with open(kp, "rb") as f: head = f.read(64)
        ok = head[56:60] == b"ARM\x64"
    check(f"{cfgname}: kernel={kern} is an arm64 Image", ok)
    missing = [o for o in ovl if not os.path.isfile(B("overlays", o + ".dtbo"))]
    check(f"{cfgname}: every dtoverlay= has a .dtbo ({len(ovl)})", not missing, missing)
    cl = kv.get("cmdline", "cmdline.txt")
    c = open(B(cl)).read() if os.path.isfile(B(cl)) else ""
    check(f"{cfgname}: {cl} roots on partition 2", "root=/dev/mmcblk0p2" in c and "rootwait" in c, c.strip()[:120])
    # overlays must resolve against the CM0 base device tree
    base = B("bcm2710-rpi-cm0.dtb")
    if ovl and os.path.isfile(base) and not missing:
        # libfdt cannot apply some stock Raspberry Pi overlays (dwc2, imx219, vc4-kms-v3d fail with
        # FDT_ERR_NOTFOUND even on the unmodified firmware-repository DTB/overlay pair; the firmware's
        # own overlay loader handles them).  Those are skipped; every other overlay must apply.
        LIBFDT_UNSUPPORTED = {"dwc2", "imx219", "vc4-kms-v3d"}
        good, bad = [], []
        # Applied one after another in config.txt order, as the firmware does: an overlay may
        # refer to a node that an earlier one created (nz-panel-* change the LCD node that the
        # board overlay adds).
        for o in ovl:
            r = run(["fdtoverlay", "-i", base, "-o", os.path.join(tmp, "one.dtb")] + [B("overlays", g + ".dtbo") for g in good] + [B("overlays", o + ".dtbo")])
            (good if r.returncode == 0 else bad).append(o)
        unexpected = [o for o in bad if o not in LIBFDT_UNSUPPORTED]
        check(f"{cfgname}: overlays resolve against bcm2710-rpi-cm0.dtb (fdtoverlay)", not unexpected,
              f"applied: {good}; not checkable with libfdt: {[o for o in bad if o in LIBFDT_UNSUPPORTED]}; FAILED: {unexpected}")
        for o in bad:
            fix = run(["fdtget", "-p", B("overlays", o + ".dtbo"), "/__fixups__"]).stdout.split()
            syms = run(["fdtget", "-p", base, "/__symbols__"]).stdout.split()
            check(f"{cfgname}: {o}.dtbo external references exist in base DTB", all(f in syms for f in fix), [f for f in fix if f not in syms])
        r = run(["fdtoverlay", "-i", base, "-o", os.path.join(tmp, "merged.dtb")] + [B("overlays", o + ".dtbo") for o in good])
        if r.returncode == 0 and cfgname == "config.txt":
            dts = run(["dtc", "-q", "-I", "dtb", "-O", "dts", os.path.join(tmp, "merged.dtb")]).stdout
            for need in ["cardputerzero,st7789v_lcd", "m5stack,tca8418c", "m5stack,m5ioe1", "everest,es8390", "ti,bq27220",
                         "epson,rx8130", "bosch,bmi270", "m5stack,pwm-backlight", "cardputerzero,powerfail-suo"]:
                check(f"merged device tree has {need}", need in dts)
            # rc11: LCD clock and sync pin overlays must come after the board overlay and take effect
            lcd = "/soc/spi@7e204000/st7789v@0"; mdtb = os.path.join(tmp, "merged.dtb")
            check("config.txt: LCD asks for a 100 MHz clock (nz-panel-100m after the board overlay)",
                  run(["fdtget", "-t", "u", mdtb, lcd, "spi-max-frequency"]).stdout.strip() == "100000000")
            te = run(["fdtget", "-t", "u", mdtb, lcd, "te-gpios"]).stdout.split()
            check("config.txt: LCD sync pin is GPIO 5 (nz-panel-te)", len(te) == 3 and te[1] == "5", te)
            check("config.txt: nz-panel overlays are listed below the board overlay",
                  "cardputerzero-v5-overlay" in ovl and "nz-panel-te" in ovl and ovl.index("nz-panel-100m") > ovl.index("cardputerzero-v5-overlay") and ovl.index("nz-panel-te") > ovl.index("cardputerzero-v5-overlay"), ovl)
        if cfgname == "config-safe.txt":
            check("config-safe.txt: no nz-panel overlays (vendor clock)", not [o for o in ovl if o.startswith("nz-panel")], ovl)
with open(B("bcm2710-rpi-cm0.dtb"), "rb") as f:
    check("base DTB magic", f.read(4) == b"\xd0\x0d\xfe\xed")
model = run(["fdtget", B("bcm2710-rpi-cm0.dtb"), "/", "model"]).stdout.strip()
check("base DTB is the Compute Module 0", "Compute Module 0" in model, model)
check("base DTB carries __symbols__ (needed for overlays)", run(["fdtget", "-l", B("bcm2710-rpi-cm0.dtb"), "/__symbols__"]).returncode == 0)
kver = ""
if os.path.isfile(B("Image")):
    m = re.search(rb"Linux version (\S+)", open(B("Image"), "rb").read())
    kver = m.group(1).decode() if m else ""
check("kernel version string found in Image", bool(kver), kver)

# ---- root filesystem
ext = os.path.join(tmp, "rootfs.ext4")
with open(img, "rb") as f, open(ext, "wb") as o:
    f.seek(p2[3] * 512); left = p2[4] * 512
    while left > 0:
        b = f.read(min(left, 1 << 22))
        if not b: break
        o.write(b); left -= len(b)
r = run(["e2fsck", "-fn", ext])
check("ext4 rootfs is clean (e2fsck -fn)", r.returncode == 0, r.stdout.strip().splitlines()[-1] if r.stdout else r.stderr)
root = os.path.join(tmp, "root"); os.mkdir(root)
run(["debugfs", "-R", f"rdump / {root}", ext])
R = lambda p: os.path.join(root, p.lstrip("/"))
def resolve(p, depth=0):
    full = R(p)
    if os.path.islink(full) and depth < 8:
        t = os.readlink(full)
        return resolve(t if t.startswith("/") else os.path.join(os.path.dirname(p), t), depth + 1)
    return full
check("/sbin/init present", os.path.exists(resolve("/sbin/init")), os.path.relpath(resolve("/sbin/init"), root))
for f in ["/usr/bin/nz-diag", "/usr/bin/nz-perf", "/usr/bin/nz-console", "/etc/nz-release", "/etc/init.d/S00nz-early",
          "/lib/firmware/cardputerzero,st7789v_lcd.bin", "/lib/firmware/bmi270-init-data.fw"]:
    check(f"rootfs {f}", os.path.exists(R(f)))
fw = [f for f in ["brcmfmac43436-sdio.bin", "brcmfmac43430-sdio.bin"] if os.path.exists(R("/lib/firmware/brcm/" + f))]
check("Wi-Fi firmware (brcmfmac4343x) present", bool(fw), fw)
# First hardware boot: the CM0 carries a CYW43439 and needs its own NVRAM.
cm0 = "/lib/firmware/brcm/brcmfmac43439-sdio.raspberrypi,0-compute-module."
check("Wi-Fi CM0 43439 firmware+NVRAM+CLM resolve", all(os.path.exists(R(cm0 + e)) for e in ("bin", "txt", "clm_blob")))
check("wireless regulatory.db present", os.path.exists(R("/lib/firmware/regulatory.db")))
if os.path.exists(R("/etc/inittab")):
    fst = open(R("/etc/fstab")).read(); itab = open(R("/etc/inittab")).read()
    check("root filesystem is mounted read-only (fstab ro, no remount-rw in inittab)",
          re.search(r"^/dev/root\s+/\s+\S+\s+ro,", fst, re.M) is not None and not re.search(r"^[^#]*remount,rw /\s*$", itab, re.M))
    check("data partition tools present (S12nz-data, nz-growpart, nz-rw, mke2fs)",
          all(os.path.exists(R(f)) for f in ["/etc/init.d/S12nz-data", "/usr/sbin/nz-growpart", "/usr/bin/nz-rw"]) and os.path.exists(R("/sbin/mke2fs")))
    check("SSH host keys kept on the data partition", os.path.islink(R("/etc/dropbear")) and os.readlink(R("/etc/dropbear")) == "/data/etc/dropbear")
    if os.path.exists(R("/usr/bin/nz-m5")):
        import glob as _g
        libcurl = (_g.glob(R("/usr/lib/libcurl.so.*")) or [""])[0]
        blob = open(libcurl, "rb").read() if libcurl else b""
        check("curl has TLS (libcurl links libssl) and a CA bundle is present",
              b"libssl.so" in blob and os.path.exists(R("/etc/ssl/certs/ca-certificates.crt")), libcurl)
    if os.path.exists(R("/usr/libexec/nz/dpkg")):
        names = re.findall(r"^Package: (\S+)", open(R("/var/dpkg-db/status")).read(), re.M) if os.path.isfile(R("/var/dpkg-db/status")) else []
        dupn = sorted({n for n in names if names.count(n) > 1})
        check(f"package database: {len(names)} entries, no name twice (dpkg refuses to read it otherwise)", names and not dupn, dupn)
        zero_v = re.findall(r"^Package: (\S+)\n(?:.*\n)*?Version: 0-nz1$", open(R("/var/dpkg-db/status")).read(), re.M) if names else []
        check("every firmware entry in the package database has a real version", names and not zero_v, zero_v)
        check("package database on the system partition, linked from /var/lib", os.path.islink(R("/var/lib/dpkg")) and os.path.isfile(R("/var/dpkg-db/status")))
    # ---- first public release: accounts, SSH, privileges
    sh_ = lambda f: open(R(f)).read() if os.path.isfile(R(f)) else ""
    dist = dict(l.split(":")[:2] for l in sh_("/etc/shadow.dist").splitlines() if ":" in l)
    check("password file lives on the data partition (/etc/shadow -> /data/etc/shadow, seed in shadow.dist)",
          os.path.islink(R("/etc/shadow")) and os.readlink(R("/etc/shadow")) == "/data/etc/shadow" and bool(dist))
    check("root has no usable password; user zero (UID 1000) has none until first boot", dist.get("root") == "*" and dist.get("zero") == "!"
          and re.search(r"^zero:x:1000:1000:", sh_("/etc/passwd"), re.M) is not None, {k: dist.get(k) for k in ("root", "zero")})
    check("no other account has a password", not [u for u, h in dist.items() if h.startswith("$")], [u for u, h in dist.items() if h.startswith("$")])
    drop = sh_("/etc/init.d/S50dropbear")
    check("SSH server refuses root (-w) and starts only with a password set", " -w" in drop and "has_password" in drop)
    sud = "\n".join(sh_("/etc/sudoers.d/" + f) for f in (os.listdir(R("/etc/sudoers.d")) if os.path.isdir(R("/etc/sudoers.d")) else []))
    nop = [l for l in sud.splitlines() if "NOPASSWD" in l and not l.strip().startswith("#")]
    check("sudo: password required, except the settings helper", nop == ["zero ALL=(root) NOPASSWD: /usr/sbin/nz-admin"] and "%sudo ALL=(ALL:ALL) ALL" in sud, nop)
    check("settings helper and first-boot prompt present", all(os.path.exists(R(f)) for f in ["/usr/sbin/nz-admin", "/usr/sbin/nz-firstboot", "/usr/share/udhcpc/default.script.d/nz-time"]))
    check("no diagnostic screen at start, no USB serial console", "nz.diag" not in open(B("cmdline.txt")).read() and "ttyGS0" not in itab and "nz-diag" not in sh_("/usr/bin/nz-console"))
    check("time zone link points into the data partition; zone data present", os.path.islink(R("/etc/localtime")) and os.readlink(R("/etc/localtime")) == "/data/etc/localtime" and os.path.exists(R("/usr/share/zoneinfo/Europe/Berlin")))
    if os.path.exists(R("/usr/bin/nz-launcher")):
        check("launcher menus present (nz-pick, Options, Services, Store + backend + official list)",
              all(os.path.exists(R(f)) for f in ["/usr/bin/nz-pick", "/usr/bin/nz-options", "/usr/bin/nz-services", "/usr/bin/nz-store", "/usr/bin/nz-store-backend", "/usr/share/nz/store-official.list",
                                                 "/usr/share/applications/nz-options.desktop", "/usr/share/applications/nz-services.desktop", "/usr/share/applications/nz-store.desktop"]))
        check("multimedia: ffmpeg, ffprobe, PulseAudio (daemon, pactl, libpulse), libv4l, v4l2-ctl",
              all(os.path.exists(R(f)) for f in ["/usr/bin/ffmpeg", "/usr/bin/ffprobe", "/usr/bin/pulseaudio", "/usr/bin/pactl", "/usr/lib/libpulse.so.0", "/usr/lib/libv4l2.so.0", "/usr/bin/v4l2-ctl"]))
    check("licence texts shipped in the image", os.path.isfile(R("/usr/share/licenses/NimbleZero/COPYING")) and os.path.isfile(R("/usr/share/licenses/manifest.csv")))
    check("no boot-time seed file write (S01seedrng removed)", not os.path.exists(R("/etc/init.d/S01seedrng")))
check("config.txt disables the firmware framebuffer", parse_cfg(B("config.txt"))[0].get("max_framebuffers") == "0")
mods = os.listdir(R("/lib/modules")) if os.path.isdir(R("/lib/modules")) else []
check("modules directory matches kernel Image version", kver in mods, f"Image={kver} modules={mods}")
have = set(); compressed = False
for d, _, fs in os.walk(R("/lib/modules")):
    have |= {f.split(".ko")[0] for f in fs if ".ko" in f}
    if any(f.endswith((".ko.gz", ".ko.xz", ".ko.zst")) for f in fs): compressed = True
for m in mods:      # built-in drivers count as present
    bi = R(f"/lib/modules/{m}/modules.builtin")
    if os.path.exists(bi): have |= {os.path.basename(l.strip()).split(".ko")[0] for l in open(bi)}
need = ["m5ioe1", "panel-mipi-dbi-m", "pwm_bl_m5stack", "tca8418_keypad_m5stack", "es8389_m5stack", "cardputerzero-audio",
        "bq27xxx_battery", "bq27xxx_battery_i2c", "powerfail_suo", "gpio-forwarder", "bmi270_core", "bmi270_i2c",
        "bmc150_magn_bmi270", "i2c-bcm2835", "spi-bcm2835", "brcmfmac", "snd-soc-bcm2835-i2s", "rtc-ds1307", "imx219",
        "gpio-ir-recv", "gpio-ir-tx", "dwc2" if False else "g_serial"]
missing = [m for m in need if m not in have and m.replace("-", "_") not in have and m.replace("_", "-") not in have]
check(f"required kernel drivers present as module or built-in ({len(need)})", not missing, missing)
dup = [m for m in ["bmi270_core", "bmc150_magn"] if sum(1 for d, _, fs in os.walk(R("/lib/modules")) for f in fs if f.split(".ko")[0] == m) > 1]
check("no duplicate in-tree/out-of-tree IMU modules", not dup, dup)
check("kernel modules are stored uncompressed", not compressed)
check("modules.dep generated", any(os.path.exists(R(f"/lib/modules/{m}/modules.dep")) for m in mods))

# ---- ELF ABI + library closure
libdirs = [R("/lib"), R("/usr/lib"), R("/lib64"), R("/usr/lib64"), R("/usr/libexec")]  # libexec: private RUNPATH libraries (sudo)
libs = set()
for d in libdirs:
    if os.path.isdir(d):
        for dd, _, fs in os.walk(d): libs |= set(fs)
n_elf = 0; bad_arch = []; unresolved = {}
for d, _, fs in os.walk(root):
    if "/lib/modules" in d or "/usr/share/APPLaunch" in d: continue
    for f in fs:
        p = os.path.join(d, f)
        if os.path.islink(p) or not os.path.isfile(p): continue
        try:
            with open(p, "rb") as fh: h = fh.read(20)
        except OSError: continue
        if h[:4] != b"\x7fELF": continue
        n_elf += 1
        if h[4] != 2 or struct.unpack("<H", h[18:20])[0] != 183: bad_arch.append(os.path.relpath(p, root)); continue
        dyn = run(["readelf", "-dW", p]).stdout
        for lib in re.findall(r"NEEDED\)\s+Shared library: \[(.*?)\]", dyn):
            if lib not in libs: unresolved.setdefault(lib, []).append(os.path.relpath(p, root))
check(f"all {n_elf} ELF files are 64-bit AArch64", n_elf > 0 and not bad_arch, bad_arch[:5])
# rc11: display path settings and PulseAudio access
_mp = R("etc/modprobe.d/nz-panel.conf")
_opt = open(_mp).read() if os.path.exists(_mp) else ""
check("LCD driver starts with the smooth setting (/etc/modprobe.d/nz-panel.conf)",
      "options panel_mipi_dbi_m nz_path=1 nz_native=2 nz_te=1 nz_cached=1 nz_async=1 nz_fbdev_ms=8" in _opt)
_ko = [os.path.join(d, f) for d, _, fs in os.walk(R("lib/modules")) for f in fs if f == "panel-mipi-dbi-m.ko"]
_parm = run(["modinfo", _ko[0]]).stdout if _ko else ""
check("LCD driver module has the switches the settings file names",
      all(("parm:           %s:" % p) in _parm for p in ["nz_path", "nz_native", "nz_te", "nz_cached", "nz_async", "nz_fbdev_ms"]))
# USB and Wi-Fi switches (Options > USB, Wi-Fi at start)
_usbconf = R("etc/modprobe.d/nz-usb.conf")
check("USB controller loaded by S13nz-usb from the Options setting, not by udev",
      os.path.exists(_usbconf) and re.search(r"^blacklist dwc2$", open(_usbconf).read(), re.M) is not None
      and os.access(R("etc/init.d/S13nz-usb"), os.X_OK) and "usb apply" in open(R("etc/init.d/S13nz-usb")).read())
_adm = open(R("usr/sbin/nz-admin")).read()
check("settings helper has the Wi-Fi and USB switches",
      all(k in _adm for k in ["wifi-power)", "usb)", "wifi-boot)", "/etc/nz/defaults"]))
_early = open(R("etc/init.d/S00nz-early")).read()
check("vendor display behaviour selectable from the boot partition (nz-display-original) and in the safe configuration",
      "nz-display-original" in _early and "nz.safe=1" in _early and "nz.safe=1" in open(B("cmdline-safe.txt")).read())
check("nz-panel and nz-paneltest present", os.path.exists(R("usr/sbin/nz-panel")) and os.path.exists(R("usr/bin/nz-paneltest")))
if os.path.exists(R("usr/bin/pulseaudio")):
    _grp = [l for l in open(R("etc/group")).read().splitlines() if l.startswith("pulse-access:")]
    _mem = _grp[0].split(":")[3].split(",") if _grp else []
    check("PulseAudio: zero and root may use the system sound service (group pulse-access)", "zero" in _mem and "root" in _mem, _grp)
    check("PulseAudio: clients do not start a second service (autospawn = no)", "\nautospawn = no" in open(R("etc/pulse/client.conf")).read())
# release: firmware set and third-party notices
_fw = R("lib/firmware/brcm")
if os.path.isdir(_fw):
    _names = sorted(os.listdir(_fw))
    _dangling = [n for n in _names if not os.path.exists(os.path.join(_fw, n))]
    check("Wi-Fi firmware: every file name for the Compute Module 0 resolves to a file (43439, 43436s, 43430 names)",
          not _dangling and all(os.path.exists(os.path.join(_fw, n)) for n in
          ["brcmfmac43439-sdio.raspberrypi,0-compute-module.bin", "brcmfmac43439-sdio.raspberrypi,0-compute-module.txt",
           "brcmfmac43439-sdio.raspberrypi,0-compute-module.clm_blob", "brcmfmac43436s-sdio.raspberrypi,0-compute-module.bin",
           "brcmfmac43436s-sdio.raspberrypi,0-compute-module.txt", "brcmfmac43430-sdio.raspberrypi,0-compute-module.bin",
           "brcmfmac43430-sdio.raspberrypi,0-compute-module.txt"]), _dangling)
    check("Wi-Fi firmware for chips no Compute Module 0 carries (43455, 43456) is not in the image",
          not [n for n in _names if "43455" in n or "43456" in n or n.startswith("BCM4345")], [n for n in _names if "4345" in n][:4])
if os.path.exists(R("lib/firmware/bmi270-init-data.fw")):
    import hashlib as _h
    check("IMU configuration data is the file whose origin is on record (Bosch, BSD-3-Clause) and its notice is in the image",
          _h.sha256(open(R("lib/firmware/bmi270-init-data.fw"), "rb").read()).hexdigest().startswith("2d75e68e343a13ff")
          and os.path.exists(R("usr/share/licenses/bosch-bmi270/LICENSE")))
check("every NEEDED shared library exists in the rootfs", not unresolved, {k: v[:2] for k, v in list(unresolved.items())[:5]})
interp = run(["readelf", "-lW", resolve("/bin/busybox")]).stdout
m = re.search(r"interpreter: (\S+?)\]", interp)
check("program interpreter exists", bool(m) and os.path.exists(resolve(m.group(1))), m.group(1) if m else "static?")
it = "\n".join(l for l in open(R("/etc/inittab")) if not l.startswith("#")) if os.path.exists(R("/etc/inittab")) else ""
if it: check("inittab: console supervisor on tty1 + getty on ttyS0", "nz-console tty1" in it and "nz-console ttyS0" in it and "getty -L" not in it)

shutil.rmtree(tmp, ignore_errors=True)
fails = [r for r in results if not r["ok"]]
print(f"\n{len(results) - len(fails)}/{len(results)} checks passed")
if "--json" in sys.argv:
    json.dump({"image": os.path.basename(img), "size": size, "kernel": kver, "passed": len(results) - len(fails), "total": len(results), "results": results},
              open(sys.argv[sys.argv.index("--json") + 1], "w"), indent=1)
sys.exit(1 if fails else 0)
