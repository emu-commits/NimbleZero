################################################################################
#
# emuzero-launcher
#
################################################################################

EMUZERO_LAUNCHER_VERSION = fb819a83810875fa68278f128a03456d5236438b
EMUZERO_LAUNCHER_SITE = $(call github,emu-commits,emuzero-launcher,$(EMUZERO_LAUNCHER_VERSION))
EMUZERO_LAUNCHER_LICENSE = MIT
EMUZERO_LAUNCHER_LICENSE_FILES = LICENSE
EMUZERO_LAUNCHER_DEPENDENCIES = freetype libpng host-pkgconf sqlite zlib

# LVGL is built into the program from a pinned release tarball.
EMUZERO_LAUNCHER_LVGL_VERSION = 9.2.2
EMUZERO_LAUNCHER_LVGL_TARBALL = lvgl-$(EMUZERO_LAUNCHER_LVGL_VERSION).tar.gz
EMUZERO_LAUNCHER_EXTRA_DOWNLOADS = \
	https://github.com/lvgl/lvgl/archive/v$(EMUZERO_LAUNCHER_LVGL_VERSION)/$(EMUZERO_LAUNCHER_LVGL_TARBALL)

# Local builds of a working tree: set EMUZERO_LAUNCHER_OVERRIDE_SRCDIR in local.mk.
EMUZERO_LAUNCHER_OVERRIDE_SRCDIR_RSYNC_EXCLUSIONS = --exclude out --exclude spike/out --exclude .git

# With EMUZERO_LAUNCHER_OVERRIDE_SRCDIR (local.mk) the source tree arrives by rsync and
# brings its own third_party/lvgl (from third_party/fetch.sh); otherwise unpack the tarball.
define EMUZERO_LAUNCHER_EXTRACT_LVGL
	if [ ! -f $(@D)/third_party/lvgl/lvgl.h ]; then \
		mkdir -p $(@D)/third_party/lvgl && \
		$(call suitable-extractor,$(EMUZERO_LAUNCHER_LVGL_TARBALL)) \
			$(EMUZERO_LAUNCHER_DL_DIR)/$(EMUZERO_LAUNCHER_LVGL_TARBALL) | \
			$(TAR) --strip-components=1 -C $(@D)/third_party/lvgl $(TAR_OPTIONS) - ; \
	fi
endef
EMUZERO_LAUNCHER_PRE_BUILD_HOOKS += EMUZERO_LAUNCHER_EXTRACT_LVGL

define EMUZERO_LAUNCHER_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) $(TARGET_CONFIGURE_OPTS) \
		PLATFORM=fbdev VERSION=$(EMUZERO_LAUNCHER_VERSION) OUT=out/buildroot
endef

define EMUZERO_LAUNCHER_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/out/buildroot/emuzero-launcher $(TARGET_DIR)/usr/bin/emuzero-launcher
	$(INSTALL) -D -m 0755 $(EMUZERO_LAUNCHER_PKGDIR)/files/emuzero-at-start $(TARGET_DIR)/usr/bin/emuzero-at-start
	$(INSTALL) -D -m 0644 $(EMUZERO_LAUNCHER_PKGDIR)/files/emuzero-launcher.desktop \
		$(TARGET_DIR)/usr/share/APPLaunch/applications/emuzero-launcher.desktop
	if [ -d $(@D)/themes ]; then \
		mkdir -p $(TARGET_DIR)/usr/share/emuzero/themes && \
		cp -a $(@D)/themes/. $(TARGET_DIR)/usr/share/emuzero/themes/; \
	fi
	# icons for apps without their own; README.md carries M5Stack's MIT notice for theirs
	if [ -d $(@D)/icons ]; then \
		mkdir -p $(TARGET_DIR)/usr/share/emuzero/icons && \
		$(INSTALL) -m 0644 $(@D)/icons/*.png $(@D)/icons/README.md $(TARGET_DIR)/usr/share/emuzero/icons/; \
	fi
	# Notes (apps/notes, from launcher sources that have it): the app, its Markdown guide,
	# nz-clip (the shared clipboard from a shell) and its tile, which replaces the Editor's
	if [ -x $(@D)/out/buildroot/emuzero-notes ]; then \
		$(INSTALL) -D -m 0755 $(@D)/out/buildroot/emuzero-notes $(TARGET_DIR)/usr/bin/emuzero-notes && \
		$(INSTALL) -D -m 0755 $(@D)/apps/notes/nz-clip $(TARGET_DIR)/usr/bin/nz-clip && \
		$(INSTALL) -D -m 0644 $(@D)/apps/notes/guide.md $(TARGET_DIR)/usr/share/emuzero/notes/guide.md && \
		$(INSTALL) -D -m 0644 $(@D)/apps/notes/emuzero-notes.desktop $(TARGET_DIR)/usr/share/applications/emuzero-notes.desktop; \
	fi
	# Wiki (apps/wiki, from launcher sources that have it): the app, its tile and the survival
	# pack (guides, triage, pictures, FM 21-76), kept built in the launcher's source (its
	# `make check` holds it to apps/wiki/content). The Wikipedia pack is copied to the device
	# separately.
	if [ -x $(@D)/out/buildroot/emuzero-wiki ]; then \
		$(INSTALL) -D -m 0755 $(@D)/out/buildroot/emuzero-wiki $(TARGET_DIR)/usr/bin/emuzero-wiki && \
		$(INSTALL) -D -m 0644 $(@D)/apps/wiki/packs/survival.wpack $(TARGET_DIR)/usr/share/emuzero/wiki/survival.wpack && \
		$(INSTALL) -D -m 0644 $(@D)/apps/wiki/emuzero-wiki.desktop $(TARGET_DIR)/usr/share/applications/emuzero-wiki.desktop; \
	fi
	# the tile M5's launcher has built in for its Calculator (shown while that program is there)
	if [ -f $(@D)/apps/calculator.desktop ]; then \
		$(INSTALL) -D -m 0644 $(@D)/apps/calculator.desktop $(TARGET_DIR)/usr/share/applications/calculator.desktop; \
	fi
endef

$(eval $(generic-package))
