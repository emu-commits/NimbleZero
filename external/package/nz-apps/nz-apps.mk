################################################################################
#
# nz-apps
#
################################################################################

NZ_APPS_VERSION = 1.0
NZ_APPS_SITE = $(BR2_EXTERNAL_NZ_PATH)/package/nz-apps/files
NZ_APPS_SITE_METHOD = local
NZ_APPS_LICENSE = GPL-2.0
NZ_APPS_DEPENDENCIES = nz-launcher
NZ_APPS_SDK_DIR = $(BR2_EXTERNAL_NZ_PATH)/../sdk

define NZ_APPS_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) -Wall -std=gnu11 -I$(NZ_APPS_SDK_DIR)/nzui \
		-o $(@D)/nz-snake $(NZ_APPS_SDK_DIR)/examples/snake.c $(TARGET_LDFLAGS)
endef

define NZ_APPS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/nz-snake $(TARGET_DIR)/usr/bin/nz-snake
	$(foreach s,nz-wifi nz-netinfo nz-ssh nz-poweroff nz-options nz-services nz-store nz-store-backend nz-app-remove,$(INSTALL) -D -m 0755 $(@D)/$(s) $(TARGET_DIR)/usr/bin/$(s)
	)
	$(INSTALL) -D -m 0644 $(@D)/store-official.list $(TARGET_DIR)/usr/share/nz/store-official.list
	mkdir -p $(TARGET_DIR)/usr/share/applications
	$(INSTALL) -m 0644 $(@D)/*.desktop $(TARGET_DIR)/usr/share/applications/
	# entries for programs this image does not contain are not installed
	for e in htop; do \
		[ -x $(TARGET_DIR)/usr/bin/$$e ] || rm -f $(TARGET_DIR)/usr/share/applications/$$e.desktop; \
	done
	# the Editor tile (nano) is gone: Notes takes its place; nano stays for the Terminal.
	# (removed here too, so a target directory from an older build loses it)
	rm -f $(TARGET_DIR)/usr/share/applications/nano.desktop
endef

$(eval $(generic-package))
