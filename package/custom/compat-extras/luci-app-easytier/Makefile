#
# Copyright (C) 2008-2014 The LuCI Team <luci@lists.subsignal.org>
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

PKG_VERSION:=2.6.4
PKG_RELEASE:=1

LUCI_TITLE:=LuCI support for EasyTier
LUCI_DEPENDS:=+kmod-tun +easytier +luci-compat
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-easytier

define Package/$(PKG_NAME)/conffiles
/etc/config/easytier
/etc/easytier/
endef



include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
