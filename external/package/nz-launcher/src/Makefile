# Device build:     make CC=aarch64-linux-gcc NZUI=<dir with nzui.h>
# Simulator build:  make sim   (needs SDL2 development files on the host)
NZUI ?= ../../../../sdk/nzui
CFLAGS ?= -O2
NZ_CFLAGS = -Wall -Wextra -Wno-format-truncation -std=gnu11 -I$(NZUI)

nz-launcher: nz-launcher.c $(NZUI)/nzui.h
	$(CC) $(CFLAGS) $(NZ_CFLAGS) -o $@ nz-launcher.c $(LDFLAGS)

nz-pick: nz-pick.c $(NZUI)/nzui.h
	$(CC) $(CFLAGS) $(NZ_CFLAGS) -o $@ nz-pick.c $(LDFLAGS)

nz-keyheld: nz-keyheld.c
	$(CC) $(CFLAGS) $(NZ_CFLAGS) -o $@ nz-keyheld.c $(LDFLAGS)

sim: nz-launcher.c $(NZUI)/nzui.h
	$(CC) $(CFLAGS) $(NZ_CFLAGS) -DNZUI_SDL $$(sdl2-config --cflags) -o nz-launcher-sim nz-launcher.c $$(sdl2-config --libs)

clean:
	rm -f nz-launcher nz-pick nz-keyheld nz-launcher-sim
