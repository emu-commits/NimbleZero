// SPDX-License-Identifier: GPL-2.0-only
/*
 * nz-keyheld - is one of these keys held down right now?  For boot-time escape hatches
 * ("hold Del while switching on").
 *
 *   nz-keyheld [-w MS] KEYCODE...      exit 0: one of the keys is down on some keyboard
 *                                      exit 1: none is down (or no keyboard appeared)
 *
 * KEYCODE is a number from linux/input-event-codes.h (14 = KEY_BACKSPACE, 1 = KEY_ESC).
 * -w MS: if no keyboard exists yet (its driver may still be probing), wait up to MS
 * milliseconds for one to appear.  The kernel keeps the state of every key whether or not
 * anything has the device open, so a key held since power-on reads as down.
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/input.h>

#define BITS(n) (((n) + 8 * sizeof(long) - 1) / (8 * sizeof(long)))
static int bit(const unsigned long *b, int n) { return (b[n / (8 * sizeof(long))] >> (n % (8 * sizeof(long)))) & 1; }

/* 1: a key is held, 0: keyboards found but none held, -1: no keyboard */
static int check(const int *keys, int nkeys)
{
	DIR *d = opendir("/dev/input"); struct dirent *e; int found = -1;
	if (!d) return -1;
	while ((e = readdir(d))) {
		unsigned long caps[BITS(KEY_CNT)], state[BITS(KEY_CNT)]; char p[300]; int fd, any = 0;
		if (strncmp(e->d_name, "event", 5)) continue;
		snprintf(p, sizeof(p), "/dev/input/%s", e->d_name);
		if ((fd = open(p, O_RDONLY | O_NONBLOCK | O_CLOEXEC)) < 0) continue;
		memset(caps, 0, sizeof(caps)); memset(state, 0, sizeof(state));
		if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(caps)), caps) >= 0 && ioctl(fd, EVIOCGKEY(sizeof(state)), state) >= 0) {
			for (int i = 0; i < nkeys; i++) if (bit(caps, keys[i])) { any = 1; if (bit(state, keys[i])) { close(fd); closedir(d); return 1; } }
			if (any) found = 0;
		}
		close(fd);
	}
	closedir(d);
	return found;
}

int main(int argc, char **argv)
{
	int keys[16], n = 0, wait_ms = 0, a = 1, r;
	if (argc > 2 && !strcmp(argv[1], "-w")) { wait_ms = atoi(argv[2]); a = 3; }
	for (; a < argc && n < 16; a++) {
		int k = atoi(argv[a]);
		if (k <= 0 || k >= KEY_CNT) { fprintf(stderr, "nz-keyheld: bad key code %s\n", argv[a]); return 2; }
		keys[n++] = k;
	}
	if (!n) { fprintf(stderr, "usage: nz-keyheld [-w MS] KEYCODE...\n"); return 2; }
	for (int t = 0; (r = check(keys, n)) < 0 && t < wait_ms; t += 50) {
		struct timespec ts = { 0, 50 * 1000000L }; nanosleep(&ts, NULL);
	}
	return r == 1 ? 0 : 1;
}
