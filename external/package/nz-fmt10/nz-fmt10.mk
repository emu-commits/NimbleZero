################################################################################
#
# nz-fmt10 - {fmt} 10 shared library only (Debian: libfmt10)
#
################################################################################

NZ_FMT10_VERSION = 10.1.1
NZ_FMT10_SOURCE = fmt-$(NZ_FMT10_VERSION).zip
NZ_FMT10_SITE = https://github.com/fmtlib/fmt/releases/download/$(NZ_FMT10_VERSION)
NZ_FMT10_LICENSE = MIT with exception
NZ_FMT10_LICENSE_FILES = LICENSE.rst
NZ_FMT10_INSTALL_STAGING = NO
NZ_FMT10_CONF_OPTS = \
	-DBUILD_SHARED_LIBS=ON \
	-DFMT_DOC=OFF \
	-DFMT_TEST=OFF \
	-DFMT_INSTALL=OFF

define NZ_FMT10_EXTRACT_CMDS
	$(UNZIP) -q -d $(@D) $(NZ_FMT10_DL_DIR)/$(NZ_FMT10_SOURCE)
	cp -a $(@D)/fmt-$(NZ_FMT10_VERSION)/. $(@D)/
	rm -rf $(@D)/fmt-$(NZ_FMT10_VERSION)
endef

define NZ_FMT10_INSTALL_TARGET_CMDS
	cp -a $(@D)/libfmt.so.10* $(TARGET_DIR)/usr/lib/
endef

$(eval $(cmake-package))
