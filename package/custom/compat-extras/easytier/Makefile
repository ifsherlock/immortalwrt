# SPDX-License-Identifier: Apache-2.0
include $(TOPDIR)/rules.mk

PKG_NAME:=easytier
PKG_VERSION:=2.6.4
PKG_RELEASE:=1

PKG_SOURCE:=easytier-linux-x86_64-v$(PKG_VERSION).zip
PKG_SOURCE_URL:=https://github.com/EasyTier/EasyTier/releases/download/v$(PKG_VERSION)
PKG_HASH:=61b659eaedba658fa66fe47d17e1426cdd77e5d02fa15fed447bb4357c09dfd6
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_CONFIG_DEPENDS:=CONFIG_EASYTIER_INCLUDE_WEBCONSOLE

include $(INCLUDE_DIR)/package.mk

# The upstream release is a statically linked executable; preserve its format.
RSTRIP:=:

define Package/easytier
  SECTION:=net
  CATEGORY:=Network
  TITLE:=EasyTier mesh VPN (official x86_64 release)
  DEPENDS:=@x86_64 +kmod-tun
  URL:=https://github.com/EasyTier/EasyTier
endef

define Package/easytier/config
  config EASYTIER_INCLUDE_WEBCONSOLE
    bool "Include EasyTier web console"
    depends on PACKAGE_easytier
    default n
endef

define Build/Prepare
	$(INSTALL_DIR) $(PKG_BUILD_DIR)
	unzip -q -j $(DL_DIR)/$(PKG_SOURCE) -d $(PKG_BUILD_DIR)
	$(CP) ./LICENSE $(PKG_BUILD_DIR)/LICENSE
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/easytier/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/easytier-core $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/easytier-cli $(1)/usr/bin/
ifdef CONFIG_EASYTIER_INCLUDE_WEBCONSOLE
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/easytier-web-embed $(1)/usr/bin/easytier-web
endif
endef

$(eval $(call BuildPackage,easytier))
