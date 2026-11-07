# NeoBird by 2smile, adapted for the LuCI 25.12 ucode and JavaScript APIs.
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-theme-neobird
PKG_VERSION:=2.0
PKG_RELEASE:=20261107
PKG_LICENSE:=Apache-2.0

LUCI_TITLE:=NeoBird theme
# Material supplies maintained styles for LuCI's current form widgets.
LUCI_DEPENDS:=+luci-base +luci-theme-material
LUCI_MINIFY_CSS:=0

define Package/luci-theme-neobird/postrm
#!/bin/sh
[ "$${1:-}" != upgrade ] && [ "$${PKG_UPGRADE:-}" != 1 ] || exit 0
[ -n "$${IPKG_INSTROOT}" ] || {
	if [ "$$(uci -q get luci.main.mediaurlbase)" = /luci-static/neobird ]; then
		uci set luci.main.mediaurlbase=/luci-static/material
	fi
	uci -q delete luci.themes.Neobird
	uci commit luci
}
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
