# SPDX-License-Identifier: GPL-2.0-only
# Adapted from the OpenWrt and kiddin9 Netdata packages.

include $(TOPDIR)/rules.mk

PKG_NAME:=netdata
PKG_VERSION:=2.11.0
PKG_RELEASE:=2

PKG_LICENSE:=GPL-3.0-or-later NCUL1
PKG_LICENSE_FILES:=COPYING
PKG_CPE_ID:=cpe:/a:netdata:netdata

PKG_SOURCE:=$(PKG_NAME)-v$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/netdata/netdata/releases/download/v$(PKG_VERSION)
PKG_HASH:=3e21070e084045757df8281a8de4213458a59a2d35a295c7d692370071797c86
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-v$(PKG_VERSION)
PKG_BUILD_DEPENDS:=protobuf/host tcl/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16 gc-sections

NETDATA_DASHBOARD_FILE:=netdata-dashboard-20261105-f73c2b904dca.tar.gz
NETDATA_SQLITE_FILE:=sqlite-src-3530300.zip

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/netdata
  SECTION:=admin
  CATEGORY:=Administration
  TITLE:=Real-time performance monitoring tool
  URL:=https://www.netdata.cloud/
  DEPENDS:=+zlib +libuuid +libuv +libmnl +liblz4 +libjson-c +libyaml \
    +libopenssl +libcurl +protobuf +libzstd +libatomic +libstdcpp +libcap +libpcre2
  PROVIDES:=netdata-ssl
endef

define Package/netdata/description
  Netdata 2.11 monitoring agent with the unmodified, checksum-pinned
  official local dashboard. Includes CPU, memory, disk and network charts.
endef

define Package/netdata/conffiles
/etc/netdata/
endef

# Retain the unmodified upstream dashboard at an immutable build-input URL.
# Its digest is also checked by the OpenWrt download machinery.
define Download/netdata-dashboard
  URL:=https://github.com/ifsherlock/immortalwrt/releases/download/build-inputs-20261107
  FILE:=$(NETDATA_DASHBOARD_FILE)
  HASH:=f73c2b904dca844efe51c5eb879c0d58b6ddd5276bf96674c631d48a754098d1
endef

define Download/netdata-sqlite
  URL:=https://www.sqlite.org/2026
  FILE:=$(NETDATA_SQLITE_FILE)
  HASH:=bb80bf8a3bffc19241ce8aba5a4bc74e9c3980013cb0b5f0f0976a99516942af
endef

CMAKE_OPTIONS += \
	-DCMAKE_INSTALL_PREFIX=/ \
	-DProtobuf_PROTOC_EXECUTABLE=$(STAGING_DIR_HOSTPKG)/bin/protoc \
	-DDASHBOARD_URL=file://$(DL_DIR)/$(NETDATA_DASHBOARD_FILE) \
	-DNETDATA_SQLITE_ARCHIVE=$(DL_DIR)/$(NETDATA_SQLITE_FILE) \
	-DSQLITE_USE_GIT=OFF \
	-DUSE_MOLD=OFF \
	-DENABLE_DBENGINE=ON \
	-DENABLE_DASHBOARD=ON \
	-DENABLE_ML=OFF \
	-DENABLE_LIBBACKTRACE=OFF \
	-DENABLE_LIBUNWIND=OFF \
	-DENABLE_SENTRY=OFF \
	-DENABLE_MIMALLOC=OFF \
	-DENABLE_JEMALLOC=OFF \
	-DENABLE_WEBRTC=OFF \
	-DENABLE_BUNDLED_JSONC=OFF \
	-DENABLE_BUNDLED_YAML=OFF \
	-DENABLE_BUNDLED_PROTOBUF=OFF \
	-DENABLE_EXPORTER_PROMETHEUS_REMOTE_WRITE=OFF \
	-DENABLE_EXPORTER_MONGODB=OFF \
	-DENABLE_PLUGIN_GO=OFF \
	-DENABLE_PLUGIN_SCRIPTS=OFF \
	-DENABLE_PLUGIN_OTEL=OFF \
	-DENABLE_PLUGIN_NETFLOW=OFF \
	-DENABLE_PLUGIN_PYTHON=OFF \
	-DENABLE_PLUGIN_CHARTS=OFF \
	-DENABLE_PLUGIN_APPS=OFF \
	-DENABLE_PLUGIN_CGROUP_NETWORK=OFF \
	-DENABLE_CGROUP_NAME=OFF \
	-DENABLE_PLUGIN_CUPS=OFF \
	-DENABLE_PLUGIN_DEBUGFS=OFF \
	-DENABLE_PLUGIN_EBPF=OFF \
	-DENABLE_LEGACY_EBPF_PROGRAMS=OFF \
	-DENABLE_PLUGIN_FREEIPMI=OFF \
	-DENABLE_PLUGIN_LOCAL_LISTENERS=OFF \
	-DENABLE_PLUGIN_NETWORK_VIEWER=OFF \
	-DENABLE_PLUGIN_NFACCT=OFF \
	-DENABLE_PLUGIN_PERF=OFF \
	-DENABLE_PLUGIN_SLABINFO=OFF \
	-DENABLE_PLUGIN_SYSTEMD_JOURNAL=OFF \
	-DENABLE_PLUGIN_SYSTEMD_UNITS=OFF \
	-DENABLE_NETDATA_JOURNAL_FILE_READER=OFF \
	-DENABLE_PLUGIN_XENSTAT=OFF \
	-DENABLE_PLUGIN_IBM=OFF

define Package/netdata/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/sbin/netdata $(1)/usr/sbin/
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/sbin/netdatacli $(1)/usr/sbin/
	$(INSTALL_DIR) $(1)/usr/lib/netdata
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/netdata/conf.d $(1)/usr/lib/netdata/
	$(INSTALL_DIR) $(1)/usr/libexec/netdata
	$(CP) $(PKG_INSTALL_DIR)/usr/libexec/netdata/plugins.d $(1)/usr/libexec/netdata/
	$(INSTALL_DIR) $(1)/etc/netdata
	$(CP) $(PKG_INSTALL_DIR)/etc/netdata/. $(1)/etc/netdata/
	$(INSTALL_CONF) ./files/netdata.conf $(1)/etc/netdata/netdata.conf
	touch $(1)/etc/netdata/.opt-out-from-anonymous-statistics
	$(INSTALL_DIR) $(1)/usr/share/netdata
	$(CP) $(PKG_INSTALL_DIR)/usr/share/netdata/. $(1)/usr/share/netdata/
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/netdata.init $(1)/etc/init.d/netdata
endef

$(eval $(call Download,netdata-dashboard))
$(eval $(call Download,netdata-sqlite))
$(eval $(call BuildPackage,netdata))
