################################################################################
#
# nz-libcamera - Raspberry Pi libcamera, library version 0.8
#
# M5Stack's camera apps (Camera, FxCam, ...) link libcamera.so.0.8 and use the
# Raspberry Pi pipeline.  Recipe adapted from Buildroot's package/libcamera.
#
################################################################################

NZ_LIBCAMERA_VERSION = 0.8.0+rpt20261104
NZ_LIBCAMERA_SITE = $(call github,raspberrypi,libcamera,v$(NZ_LIBCAMERA_VERSION))
NZ_LIBCAMERA_DEPENDENCIES = \
	host-openssl \
	host-pkgconf \
	host-python-jinja2 \
	host-python-ply \
	host-python-pyyaml \
	libyaml \
	gnutls
NZ_LIBCAMERA_CONF_OPTS = \
	-Dauto_features=disabled \
	-Dandroid=disabled \
	-Ddocumentation=disabled \
	-Dcam=disabled \
	-Dqcam=disabled \
	-Dgstreamer=disabled \
	-Dpycamera=disabled \
	-Dv4l2=disabled \
	-Dlc-compliance=disabled \
	-Dtracing=disabled \
	-Drpi-awb-nn=disabled \
	-Dpipelines=rpi/vc4 \
	-Dipas=rpi/vc4 \
	-Dtest=false \
	-Dwerror=false
NZ_LIBCAMERA_INSTALL_STAGING = YES
NZ_LIBCAMERA_LICENSE = \
	LGPL-2.1+ (library), \
	BSD-2-Clause (raspberrypi), \
	GPL-2.0+ (utils), \
	CC0-1.0 (meson build system), \
	GPL-2.0 with Linux-syscall-note or BSD-3-Clause (linux kernel headers)
NZ_LIBCAMERA_LICENSE_FILES = \
	LICENSES/BSD-2-Clause.txt \
	LICENSES/BSD-3-Clause.txt \
	LICENSES/CC0-1.0.txt \
	LICENSES/GPL-2.0-only.txt \
	LICENSES/GPL-2.0-or-later.txt \
	LICENSES/LGPL-2.1-or-later.txt \
	LICENSES/Linux-syscall-note.txt
NZ_LIBCAMERA_CXXFLAGS = -faligned-new

ifeq ($(BR2_PACKAGE_HAS_UDEV),y)
NZ_LIBCAMERA_CONF_OPTS += -Dudev=enabled
NZ_LIBCAMERA_DEPENDENCIES += udev
endif

# The IPA module is signed at install time so that it runs inside the app's
# process; Buildroot strips the target later, so strip it before it is signed
# (as Buildroot's libcamera package does).
define NZ_LIBCAMERA_BUILD_STRIP_IPA_SO
	find $(@D)/buildroot-build/src/ipa -type f -name 'ipa_*.so' -print0 | \
		xargs --no-run-if-empty -0 $(STRIPCMD)
endef
NZ_LIBCAMERA_POST_BUILD_HOOKS += NZ_LIBCAMERA_BUILD_STRIP_IPA_SO

$(eval $(meson-package))
