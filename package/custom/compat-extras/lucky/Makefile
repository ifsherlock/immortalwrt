# SPDX-License-Identifier: GPL-3.0-only
include $(TOPDIR)/rules.mk

PKG_NAME:=lucky
PKG_VERSION:=3.5.0
PKG_RELEASE:=1

PKG_SOURCE:=lucky_$(PKG_VERSION)_Linux_x86_64.tar.gz
PKG_SOURCE_URL:=https://github.com/gdy666/lucky/releases/download/v$(PKG_VERSION)
PKG_HASH:=51de79d5ccac4f22fc0b3b311f7f6641b92d6469066dc135e73bb717f843b816
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
PKG_LICENSE:=MIT Apache-2.0
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

RSTRIP:=:

define Package/lucky
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Lucky network service (official x86_64 release)
  DEPENDS:=@x86_64
  URL:=https://github.com/gdy666/lucky
endef

define Build/Prepare
	$(INSTALL_DIR) $(PKG_BUILD_DIR)
	$(TAR) -C $(PKG_BUILD_DIR) -xzf $(DL_DIR)/$(PKG_SOURCE)
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/lucky/conffiles
/etc/config/lucky
/etc/config/lucky.daji/
endef

define Package/lucky/install
	$(INSTALL_DIR) $(1)/usr/bin $(1)/usr/libexec $(1)/etc/init.d $(1)/etc/config
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/lucky $(1)/usr/bin/lucky
	$(INSTALL_BIN) ./files/lucky-runner $(1)/usr/libexec/lucky-runner
	$(INSTALL_BIN) ./files/lucky.init $(1)/etc/init.d/lucky
	$(INSTALL_CONF) ./files/luckyuci $(1)/etc/config/lucky
	$(INSTALL_DIR) $(1)/usr/share/licenses/lucky
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/LICENSE $(1)/usr/share/licenses/lucky/LICENSE
endef

$(eval $(call BuildPackage,lucky))
