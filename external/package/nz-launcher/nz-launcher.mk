################################################################################
#
# nz-launcher
#
################################################################################

NZ_LAUNCHER_VERSION = 1.0
NZ_LAUNCHER_SITE = $(BR2_EXTERNAL_NZ_PATH)/package/nz-launcher/src
NZ_LAUNCHER_SITE_METHOD = local
NZ_LAUNCHER_LICENSE = GPL-2.0, Public Domain (font8x8)
NZ_LAUNCHER_INSTALL_STAGING = YES
NZ_LAUNCHER_NZUI_DIR = $(BR2_EXTERNAL_NZ_PATH)/../sdk/nzui

define NZ_LAUNCHER_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) $(TARGET_CONFIGURE_OPTS) NZUI=$(NZ_LAUNCHER_NZUI_DIR) nz-launcher nz-pick nz-keyheld
endef

define NZ_LAUNCHER_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0644 $(NZ_LAUNCHER_NZUI_DIR)/nzui.h $(STAGING_DIR)/usr/include/nzui.h
	$(INSTALL) -D -m 0644 $(NZ_LAUNCHER_NZUI_DIR)/font8x8_basic.h $(STAGING_DIR)/usr/include/font8x8_basic.h
endef

define NZ_LAUNCHER_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/nz-launcher $(TARGET_DIR)/usr/bin/nz-launcher
	$(INSTALL) -D -m 0755 $(@D)/nz-pick $(TARGET_DIR)/usr/bin/nz-pick
	$(INSTALL) -D -m 0755 $(@D)/nz-keyheld $(TARGET_DIR)/usr/bin/nz-keyheld
	mkdir -p $(TARGET_DIR)/usr/share/applications
endef

$(eval $(generic-package))
