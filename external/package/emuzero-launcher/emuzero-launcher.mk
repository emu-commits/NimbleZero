################################################################################
#
# emuzero-launcher
#
################################################################################

EMUZERO_LAUNCHER_VERSION = 88f19951263282c83b17fc550869c39a0658d8ab
EMUZERO_LAUNCHER_SITE = $(call github,emu-commits,emuzero-launcher,$(EMUZERO_LAUNCHER_VERSION))
EMUZERO_LAUNCHER_LICENSE = MIT
EMUZERO_LAUNCHER_LICENSE_FILES = LICENSE
EMUZERO_LAUNCHER_DEPENDENCIES = freetype libpng host-pkgconf

# LVGL is built into the program from a pinned release tarball.
EMUZERO_LAUNCHER_LVGL_VERSION = 9.2.2
EMUZERO_LAUNCHER_LVGL_TARBALL = lvgl-$(EMUZERO_LAUNCHER_LVGL_VERSION).tar.gz
EMUZERO_LAUNCHER_EXTRA_DOWNLOADS = \
	https://github.com/lvgl/lvgl/archive/v$(EMUZERO_LAUNCHER_LVGL_VERSION)/$(EMUZERO_LAUNCHER_LVGL_TARBALL)

# Local builds of a working tree: set EMUZERO_LAUNCHER_OVERRIDE_SRCDIR in local.mk.
EMUZERO_LAUNCHER_OVERRIDE_SRCDIR_RSYNC_EXCLUSIONS = --exclude out --exclude spike/out

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
endef

$(eval $(generic-package))
