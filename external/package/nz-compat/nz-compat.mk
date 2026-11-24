################################################################################
#
# nz-compat
#
################################################################################

NZ_COMPAT_VERSION = 1.0
NZ_COMPAT_SITE = $(BR2_EXTERNAL_NZ_PATH)/package/nz-compat/files
NZ_COMPAT_SITE_METHOD = local
NZ_COMPAT_LICENSE = GPL-2.0
NZ_COMPAT_DEPENDENCIES = dpkg

# ~/.config must belong to the user before any maintainer script creates
# sub-directories in it as root (the upstream applaunch postinst does)
define NZ_COMPAT_PERMISSIONS
	/home/zero/.config d 755 1000 1000 - - - - -
endef

define NZ_COMPAT_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)/home/zero/.config
	echo 'LANG=C.UTF-8' > $(TARGET_DIR)/etc/locale.conf
	mkdir -p $(TARGET_DIR)/etc/profile.d
	echo 'export LANG=$${LANG:-C.UTF-8}' > $(TARGET_DIR)/etc/profile.d/nz-locale.sh
	$(INSTALL) -D -m 0644 $(@D)/provided.map $(TARGET_DIR)/usr/share/nz/provided.map
	$(INSTALL) -D -m 0755 $(@D)/xdg-user-dirs-update $(TARGET_DIR)/usr/bin/xdg-user-dirs-update
	$(INSTALL) -D -m 0755 $(@D)/nz-m5 $(TARGET_DIR)/usr/bin/nz-m5
	# way back from the M5 launcher: an entry in its app list (its Icon is one of APPLaunch's own)
	$(INSTALL) -D -m 0755 $(@D)/nz-native-launcher $(TARGET_DIR)/usr/bin/nz-native-launcher
	$(INSTALL) -D -m 0644 $(@D)/nz-native-launcher.desktop $(TARGET_DIR)/usr/share/APPLaunch/applications/nz-native-launcher.desktop
	$(INSTALL) -D -m 0644 $(@D)/70-nz-compat.rules $(TARGET_DIR)/etc/udev/rules.d/70-nz-compat.rules
	$(INSTALL) -D -m 0755 $(@D)/runuser $(TARGET_DIR)/usr/sbin/runuser
	$(INSTALL) -D -m 0755 $(@D)/apt-get $(TARGET_DIR)/usr/bin/apt-get
	ln -sf apt-get $(TARGET_DIR)/usr/bin/apt
	# dpkg insists on ldconfig; ship the toolchain's own (same glibc).  Its
	# configuration is written by seed-dpkg.sh (Buildroot forbids ld.so.conf earlier).
	$(INSTALL) -D -m 0755 $(STAGING_DIR)/sbin/ldconfig $(TARGET_DIR)/sbin/ldconfig
	# maintainer scripts look users up with getent (glibc's, from the toolchain sysroot)
	$(INSTALL) -D -m 0755 $(STAGING_DIR)/usr/bin/getent $(TARGET_DIR)/usr/bin/getent
	# guard in front of dpkg (see files/dpkg-wrapper); the real binary moves aside once
	if [ ! -x $(TARGET_DIR)/usr/libexec/nz/dpkg ] || ! head -c 2 $(TARGET_DIR)/usr/bin/dpkg | grep -q '#!'; then \
		mkdir -p $(TARGET_DIR)/usr/libexec/nz && mv $(TARGET_DIR)/usr/bin/dpkg $(TARGET_DIR)/usr/libexec/nz/dpkg; \
	fi
	$(INSTALL) -m 0755 $(@D)/dpkg-wrapper $(TARGET_DIR)/usr/bin/dpkg
endef

ifeq ($(BR2_PACKAGE_NZ_COMPAT_SHIMS),y)
define NZ_COMPAT_INSTALL_SHIMS
	$(INSTALL) -D -m 0755 $(@D)/nz-unit $(TARGET_DIR)/usr/sbin/nz-unit
	$(INSTALL) -D -m 0755 $(@D)/systemctl $(TARGET_DIR)/usr/bin/systemctl
	$(INSTALL) -D -m 0755 $(@D)/loginctl $(TARGET_DIR)/usr/bin/loginctl
	$(INSTALL) -D -m 0755 $(@D)/S60nz-units $(TARGET_DIR)/etc/init.d/S60nz-units
endef
NZ_COMPAT_POST_INSTALL_TARGET_HOOKS += NZ_COMPAT_INSTALL_SHIMS
endif

$(eval $(generic-package))
