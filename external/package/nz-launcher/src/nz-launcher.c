// SPDX-License-Identifier: GPL-2.0-only
/*
 * nz-launcher - keyboard-first application launcher and lifecycle manager.
 *
 * Applications are ordinary freedesktop .desktop entries, read from
 *   /usr/share/applications            (native apps, Buildroot packages)
 *   /usr/share/APPLaunch/applications  (M5Stack app packages, if installed)
 *   /usr/local/share/applications, $HOME/.local/share/applications
 * so "installing an app" is just putting a .desktop file there - by hand, from a
 * tarball or with dpkg.  Keys used from each entry: Name, Comment, Exec,
 * Terminal, NoDisplay, Path.
 *
 * Lifecycle: one foreground app at a time.  The launcher gives up the screen and
 * keyboard, starts the app in its own process group, waits, and takes the screen
 * back when it exits.  Terminal=true apps run on the Linux text console.
 * Ctrl+Alt+Backspace sends SIGTERM to the app's process group (SIGKILL after 2 s).
 *
 * Power: after the idle time set in Options (file /data/etc/nz/screen-off, or
 * NZ_IDLE_S; default 120 s, 0 = never) the
 * backlight is switched off and the launcher stops redrawing and sleeps in
 * poll() until a key arrives; that key only wakes the screen.  While the screen
 * is on it wakes once a minute for the clock.  The same idle time applies while an
 * app runs (the launcher sees its keys too); the app keeps running in the dark.
 *
 * Keys: the F / X / Z / C keys carry the arrow legends on the Cardputer keyboard and
 * work as arrows without Fn:  F up, X down, Z page up, C page down.
 *       Up/Down (or F/X, K/J, W/S)  select    Enter  launch    R  rescan
 *       Z / C (or Left/Right, Tab)  page      O      options   Q  quit to login
 */
#define _GNU_SOURCE
#define NZUI_IMPLEMENTATION
#include "nzui.h"
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <signal.h>
#include <termios.h>
#include <linux/kd.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <time.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <linux/input-event-codes.h>

#define MAXAPPS 96
struct app { char name[40], comment[48], exec[256], path[128]; int terminal; };
static struct app apps[MAXAPPS]; static int napps, sel, top;
static char status[64];
static const char *extra_dir;

static int cmp_app(const void *a, const void *b) { return strcasecmp(((const struct app *)a)->name, ((const struct app *)b)->name); }

static void scan_dir(const char *dir)
{
	DIR *d = opendir(dir); struct dirent *e;
	if (!d) return;
	while ((e = readdir(d)) && napps < MAXAPPS) {
		char p[512], line[512]; size_t n = strlen(e->d_name); FILE *f; struct app a; int in = 0, hide = 0;
		if (n < 9 || strcmp(e->d_name + n - 8, ".desktop")) continue;
		snprintf(p, sizeof(p), "%s/%s", dir, e->d_name);
		if (!(f = fopen(p, "r"))) continue;
		memset(&a, 0, sizeof(a));
		while (fgets(line, sizeof(line), f)) {
			char *v; line[strcspn(line, "\r\n")] = 0;
			if (line[0] == '[') { in = !strcmp(line, "[Desktop Entry]"); continue; }
			if (!in || !(v = strchr(line, '='))) continue;
			*v++ = 0;
			if (!strcmp(line, "Name")) snprintf(a.name, sizeof(a.name), "%s", v);
			else if (!strcmp(line, "Comment")) snprintf(a.comment, sizeof(a.comment), "%s", v);
			else if (!strcmp(line, "Exec")) snprintf(a.exec, sizeof(a.exec), "%s", v);
			else if (!strcmp(line, "Path")) snprintf(a.path, sizeof(a.path), "%s", v);
			else if (!strcmp(line, "Terminal")) a.terminal = !strcasecmp(v, "true");
			else if (!strcmp(line, "NoDisplay") || !strcmp(line, "Hidden")) hide |= !strcasecmp(v, "true");
		}
		fclose(f);
		for (char *c = a.exec; (c = strchr(c, '%')); )          /* drop %f %u ... field codes */
			if (c[1] == '%') c += 2; else memmove(c, c + 2 > c + strlen(c) ? c + strlen(c) : c + 2, strlen(c + (c[1] ? 2 : 1)) + 1);
		if (a.name[0] && a.exec[0] && !hide) apps[napps++] = a;
	}
	closedir(d);
}

static void scan(void)
{
	char home[256]; const char *h = getenv("HOME");
	napps = 0;
	scan_dir("/usr/share/applications"); scan_dir("/usr/local/share/applications");
	scan_dir("/usr/share/APPLaunch/applications");
	if (h) { snprintf(home, sizeof(home), "%s/.local/share/applications", h); scan_dir(home); }
	if (extra_dir) scan_dir(extra_dir);
	qsort(apps, napps, sizeof(apps[0]), cmp_app);
	if (sel >= napps) sel = napps ? napps - 1 : 0;
}

static long rdl(const char *p) { FILE *f = fopen(p, "r"); long v = -1; if (f) { if (fscanf(f, "%ld", &v) != 1) v = -1; fclose(f); } return v; }

/* battery level in per cent (-1: no fuel gauge); *chg: 1 charging, 0 not */
static int battery(int *chg)
{
	DIR *d = opendir("/sys/class/power_supply"); struct dirent *e; int cap = -1;
	*chg = 0;
	while (d && (e = readdir(d)) && cap < 0) {
		char p[320], st[32] = ""; FILE *f; if (e->d_name[0] == '.') continue;
		snprintf(p, sizeof(p), "/sys/class/power_supply/%s/capacity", e->d_name); cap = (int)rdl(p);
		if (cap < 0) continue;
		snprintf(p, sizeof(p), "/sys/class/power_supply/%s/status", e->d_name);
		if ((f = fopen(p, "r"))) { if (fgets(st, sizeof(st), f)) *chg = !strncmp(st, "Charging", 8); fclose(f); }
	}
	if (d) closedir(d);
	return cap > 100 ? 100 : cap;
}

static int idle_setting(void)
{
	long v = rdl("/data/etc/nz/screen-off");
	if (getenv("NZ_IDLE_S")) return atoi(getenv("NZ_IDLE_S"));
	return v < 0 ? 120 : (int)v;
}

static void draw(void)
{
	const int rows = (nzui_h - 14 - 12) / 18; time_t t = time(NULL); struct tm *tm = localtime(&t); int chg, b = battery(&chg);
	uint16_t bar = NZUI_RGB(30, 70, 170), hi = NZUI_RGB(250, 200, 60);
	nzui_clear(NZUI_BLACK);
	nzui_rect(0, 0, nzui_w, 12, bar);
	nzui_text(4, 2, NZUI_WHITE, "NimbleZero");
	if (b >= 0) {   /* battery: outline, fill proportional to the level, "+" while charging */
		int x = nzui_w - 8 * 15, fill = b * 14 / 100;
		uint16_t lvl = b <= 15 ? NZUI_RGB(230, 60, 60) : b <= 35 ? NZUI_RGB(250, 200, 60) : NZUI_RGB(90, 220, 110);
		nzui_rect(x, 2, 18, 8, NZUI_WHITE); nzui_rect(x + 18, 4, 2, 4, NZUI_WHITE);
		nzui_rect(x + 1, 3, 16, 6, bar); nzui_rect(x + 2, 4, fill, 4, lvl);
		nzui_text(x + 23, 2, NZUI_WHITE, "%d%%%s", b, chg ? "+" : "");
	}
	nzui_text(nzui_w - 8 * 6, 2, NZUI_WHITE, "%02d:%02d", tm->tm_hour, tm->tm_min);
	if (sel < top) top = sel;
	if (sel >= top + rows) top = sel - rows + 1;
	for (int i = 0; i < rows && top + i < napps; i++) {
		struct app *a = &apps[top + i]; int y = 15 + i * 18, s = top + i == sel;
		if (s) nzui_rect(0, y - 1, nzui_w, 18, NZUI_RGB(40, 40, 60));
		nzui_text(6, y, s ? hi : NZUI_WHITE, "%c %.34s", s ? '>' : ' ', a->name);
		nzui_text(22, y + 9, NZUI_GREY, "%.36s", a->comment[0] ? a->comment : a->terminal ? "(terminal)" : "");
	}
	if (!napps) nzui_text(6, 40, NZUI_GREY, "no applications installed");
	nzui_rect(0, nzui_h - 11, nzui_w, 11, NZUI_RGB(25, 25, 25));
	nzui_text(4, nzui_h - 9, NZUI_GREY, "%.39s", status[0] ? status : "Enter:run  O:options  F/X:move");
	nzui_flush();
}

static void backlight_power(int on)
{
	DIR *d = opendir("/sys/class/backlight"); struct dirent *e;
	while (d && (e = readdir(d))) {
		char p[320]; FILE *f; if (e->d_name[0] == '.') continue;
		snprintf(p, sizeof(p), "/sys/class/backlight/%s/bl_power", e->d_name);
		if ((f = fopen(p, "w"))) { fputs(on ? "0\n" : "4\n", f); fclose(f); }
	}
	if (d) closedir(d);
}

/* Screen off = backlight off AND the display switched off, so the panel driver can put
 * the controller to sleep (hardware 2026-11-23: about 7 mA less than backlight alone). */
static void screen_power(int on)
{
#ifndef NZUI_SDL
	if (on && ioctl(nzui__fd, FBIOBLANK, FB_BLANK_UNBLANK)) {}
#endif
	backlight_power(on);
#ifndef NZUI_SDL
	if (!on && ioctl(nzui__fd, FBIOBLANK, FB_BLANK_POWERDOWN)) {}
#endif
}

/* ---- lifecycle: run one foreground application ---- */
static void grab_keys(int on)
{
#ifndef NZUI_SDL
	for (int i = 0; i < nzui__nin; i++) if (ioctl(nzui__in[i].fd, EVIOCGRAB, on)) {}
#endif
}

static int run_app(struct app *a, int idle_s)
{
	pid_t pid; int st = 0, ctrl = 0, alt = 0, wake_key = 0; struct nzui_event ev; time_t killed = 0, last_key;
	enum { LIT, DARK, WAKING } scr = LIT;
#ifndef NZUI_SDL
	/* empty the text console and hide its cursor first: nzui_suspend() switches to text
	 * mode, which repaints whatever the console holds (e.g. echoed key presses) */
	if (!a->terminal) { if (write(1, "\033[2J\033[H\033[?25l", 13) < 0) {} }
	nzui_suspend();                          /* text mode + release evdev */
	if (a->terminal) { if (write(1, "\033[2J\033[H", 7) < 0) {} }
	else {
		/* Graphical app: it draws on the framebuffer itself.  Keep the text console out
		 * of the picture (graphics mode: no console text, no cursor), otherwise whatever
		 * the app prints is drawn over its own screen (seen on hardware with the M5Stack
		 * IR-Remote app, whose log went to the console). */
		ioctl(0, KDSETMODE, KD_GRAPHICS);
	}
#endif
	if ((pid = fork()) == 0) {
		setpgid(0, 0);
		if (!a->terminal) {
			/* its output goes to a log instead: /tmp/nz-app.log (last graphical app) */
			int fd = open("/tmp/nz-app.log", O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0644), nul = open("/dev/null", O_RDONLY);
			if (fd >= 0) { dup2(fd, 1); dup2(fd, 2); if (fd > 2) close(fd); }
			if (nul >= 0) { dup2(nul, 0); if (nul > 2) close(nul); }
		}
		if (a->path[0] && chdir(a->path)) {}
		execl("/bin/sh", "sh", "-c", a->exec, (char *)NULL);
		_exit(127);
	}
	if (pid < 0) return -1;
#ifndef NZUI_SDL
	tcsetpgrp(0, pid);                       /* give the child the controlling terminal */
	nzui__inputs();                          /* keep watching for the kill chord only */
#endif
	last_key = time(NULL);
	for (;;) {
		pid_t r = waitpid(pid, &st, WNOHANG);
		if (r == pid || (r < 0 && errno != EINTR)) break;
		if (killed && time(NULL) - killed >= 2) kill(-pid, SIGKILL);
#ifndef NZUI_SDL
		if (scr != LIT) {
			/* Screen off while the app runs: the keys come to the launcher alone (grab, so
			 * neither the app nor the text console sees them).  As in the menu, the first
			 * press only wakes the screen; the app gets keys again once that key is let go. */
			grab_keys(1);                    /* again each time: nzui_poll() may reopen the devices */
			if (poll(nzui__in, nzui__nin, 500) > 0)
				while (nzui_poll(&ev, 0) == 1) {
					if (scr == DARK && ev.value == 1) { scr = WAKING; wake_key = ev.key; screen_power(1); }
					else if (scr == WAKING && ev.key == wake_key && ev.value == 0) { scr = LIT; last_key = time(NULL); grab_keys(0); break; }
				}
			continue;
		}
#endif
		if (nzui_poll(&ev, 200) == 1) {
			if (ev.value == 1) last_key = time(NULL);
			if (ev.key == KEY_LEFTCTRL || ev.key == KEY_RIGHTCTRL) ctrl = ev.value != 0;
			if (ev.key == KEY_LEFTALT || ev.key == KEY_RIGHTALT) alt = ev.value != 0;
			if (ev.key == KEY_BACKSPACE && ev.value == 1 && ctrl && alt && !killed) { kill(-pid, SIGTERM); killed = time(NULL); }
		}
		/* the same idle time as in the menu: the launcher sees every key the app gets */
#ifndef NZUI_SDL
		if (idle_s > 0 && time(NULL) - last_key >= idle_s) { scr = DARK; ctrl = alt = 0; screen_power(0); }
#endif
	}
	if (scr != LIT) { grab_keys(0); screen_power(1); }   /* the app quit with the screen off */
#ifndef NZUI_SDL
	signal(SIGTTOU, SIG_IGN); tcsetpgrp(0, getpgrp());
	tcflush(0, TCIFLUSH);                    /* keys typed in a graphical app also reached the tty */
	if (!a->terminal) { if (write(1, "\033[2J\033[H\033[?25h", 13) < 0) {} }
	nzui_resume();
#endif
	if (WIFEXITED(st) && WEXITSTATUS(st)) snprintf(status, sizeof(status), "%.20s exited with status %d", a->name, WEXITSTATUS(st));
	else if (WIFSIGNALED(st)) snprintf(status, sizeof(status), "%.20s killed by signal %d", a->name, WTERMSIG(st));
	else status[0] = 0;
	return 0;
}

int main(int argc, char **argv)
{
	struct nzui_event ev; int r, screen_on = 1, idle_s = idle_setting();
	time_t last_key = time(NULL);
	if (argc > 2 && !strcmp(argv[1], "--apps")) extra_dir = argv[2];
	if (argc > 1 && !strcmp(argv[1], "--list")) {   /* headless: print what would be shown */
		if (argc > 2) extra_dir = argv[2];
		scan(); for (int i = 0; i < napps; i++) printf("%s\t%s\t%s\n", apps[i].name, apps[i].terminal ? "terminal" : "graphical", apps[i].exec);
		return 0;
	}
	if (nzui_init("nz-launcher")) { fprintf(stderr, "nz-launcher: no display\n"); return 1; }
	scan(); draw();
	{   /* boot report (nz-boottime): uptime at the first frame.  nz-console creates the
	     * file empty for us at boot; a later start of the launcher finds it filled. */
		int fd = open("/run/nz/t_launcher_frame", O_WRONLY | O_APPEND | O_NOFOLLOW | O_CLOEXEC);
		struct stat st; FILE *u; char t[32] = "";
		if (fd >= 0 && !fstat(fd, &st) && st.st_size == 0 && (u = fopen("/proc/uptime", "r"))) {
			if (fscanf(u, "%31s", t) == 1) { strcat(t, "\n"); if (write(fd, t, strlen(t)) < 0) {} }
			fclose(u);
		}
		if (fd >= 0) close(fd);
	}
	for (;;) {
		time_t now = time(NULL);
		int to = !screen_on ? -1 : (int)(60 - now % 60) * 1000;
		if (screen_on && idle_s > 0) { int left = (int)(last_key + idle_s - now); if (left * 1000 < to) to = left > 0 ? left * 1000 : 0; }
		if ((r = nzui_poll(&ev, to)) < 0) break;
		now = time(NULL);
		if (r == 1 && ev.value) {
			last_key = now;
			if (!screen_on) { screen_on = 1; screen_power(1); draw(); continue; }   /* first key only wakes */
			switch (ev.key) {
			case KEY_UP: case KEY_F: case KEY_K: case KEY_W: if (sel > 0) sel--; break;
			case KEY_DOWN: case KEY_X: case KEY_J: case KEY_S: if (sel < napps - 1) sel++; break;
			case KEY_RIGHT: case KEY_C: case KEY_PAGEDOWN: sel = sel + 6 < napps ? sel + 6 : napps ? napps - 1 : 0; break;
			case KEY_LEFT: case KEY_Z: case KEY_PAGEUP: sel = sel > 6 ? sel - 6 : 0; break;
			case KEY_TAB: sel = sel + 6 < napps ? sel + 6 : 0; break;
			case KEY_R: scan(); snprintf(status, sizeof(status), "%d applications", napps); break;
			case KEY_O:
				if (ev.value == 1) {
					static struct app opt = { "Options", "", "nz-options", "", 1 };
					run_app(&opt, idle_s); scan(); idle_s = idle_setting(); last_key = time(NULL);
				}
				break;
			case KEY_ENTER: if (napps && ev.value == 1) { run_app(&apps[sel], idle_s); scan(); idle_s = idle_setting(); last_key = time(NULL); } break;
			case KEY_Q: if (ev.value == 1) { nzui_quit(); return 0; } break;
			}
		}
		if (screen_on && idle_s > 0 && now - last_key >= idle_s) { screen_on = 0; screen_power(0); continue; }
		if (screen_on) draw();
	}
	nzui_quit();
	return 0;
}
