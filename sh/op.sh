#!/bin/bash

function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
  repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
  cd $repodir && git sparse-checkout set $@
  mv -f $@ ../
  cd .. && rm -rf $repodir
}

set -e

echo "================================================="
echo "  CMCC XR30 eMMC -> Aigo AGS21"
echo "  OpenWrt 25.12 / MT7981 / eMMC"
echo "================================================="

DTS_DIR="target/linux/mediatek/dts"

EMMC_DTS="$DTS_DIR/mt7981b-cmcc-xr30-emmc.dts"
XR30_DTSI="$DTS_DIR/mt7981b-cmcc-xr30.dtsi"
FILOGIC_MK="target/linux/mediatek/image/filogic.mk"

# =================================================
# 检查源码
# =================================================

if [ ! -f "$EMMC_DTS" ]; then
	echo "ERROR: $EMMC_DTS not found!"
	exit 1
fi

if [ ! -f "$XR30_DTSI" ]; then
	echo "ERROR: $XR30_DTSI not found!"
	exit 1
fi

if [ ! -f "$FILOGIC_MK" ]; then
	echo "ERROR: $FILOGIC_MK not found!"
	exit 1
fi

echo
echo "Found DTS:"
echo "  $EMMC_DTS"
echo
echo "Found DTSI:"
echo "  $XR30_DTSI"
echo
echo "Found image definition:"
echo "  $FILOGIC_MK"


# =================================================
# 1. 修改 eMMC DTS
# =================================================

echo
echo "================================================="
echo "  [1/4] Patch eMMC DTS"
echo "================================================="

python3 - "$EMMC_DTS" <<'PY'
import sys
import re

file = sys.argv[1]

with open(file, "r", encoding="utf-8") as f:
    d = f.read()

# -------------------------------------------------
# model
# -------------------------------------------------

d = re.sub(
    r'(\bmodel\s*=\s*)"[^"]*";',
    r'\1"Aigo AGS21";',
    d,
    count=1
)

# -------------------------------------------------
# compatible
# 只修改根节点 compatible
# 不碰 mmc-card / block-device / fixed-layout
# -------------------------------------------------

d = re.sub(
    r'(\bcompatible\s*=\s*)"cmcc,xr30-emmc"\s*,\s*"mediatek,mt7981";',
    r'\1"aigo,ags21", "mediatek,mt7981";',
    d,
    count=1
)

# 如果原文件没有 cmcc,xr30-emmc，则根据根节点位置处理
if 'compatible = "cmcc,xr30-emmc"' in d:
    raise RuntimeError("Root compatible replacement failed")

with open(file, "w", encoding="utf-8") as f:
    f.write(d)

print("eMMC DTS patched successfully")
PY


# =================================================
# 2. 修改 XR30 DTSI
# =================================================

echo
echo "================================================="
echo "  [2/4] Patch XR30 DTSI"
echo "================================================="

python3 - "$XR30_DTSI" <<'PY'
import sys
import re

file = sys.argv[1]

with open(file, "r", encoding="utf-8") as f:
    d = f.read()


# =================================================
# aliases
# =================================================

aliases = r'''aliases {
	led-boot = &status_red_led;
	led-failsafe = &status_red_led;
	led-running = &status_blue_led;
	led-upgrade = &status_blue_led;
	serial0 = &uart0;
};'''

d, n = re.subn(
    r'aliases\s*\{.*?\n\s*\};',
    aliases,
    d,
    count=1,
    flags=re.S
)

if n == 0:
    print("WARNING: aliases block not found")


# =================================================
# LED
#
# AGS21:
# GPIO6  = 红灯
# GPIO4  = 蓝灯
# GPIO29 = 绿灯
# GPIO30 = 白灯
# =================================================

leds = r'''leds {
	compatible = "gpio-leds";

	status_red_led: red {
		label = "red:status";
		gpios = <&pio 6 GPIO_ACTIVE_LOW>;
	};

	status_blue_led: blue {
		label = "blue:status";
		gpios = <&pio 4 GPIO_ACTIVE_LOW>;
	};

	internet_led: green {
		label = "green:status";
		gpios = <&pio 29 GPIO_ACTIVE_LOW>;
	};

	wifi_led: white {
		label = "white:status";
		gpios = <&pio 30 GPIO_ACTIVE_LOW>;
	};
};'''

# 只匹配 DTSI 中的 leds 节点
d, n = re.subn(
    r'\bleds\s*\{.*?\n\s*\};',
    leds,
    d,
    count=1,
    flags=re.S
)

if n == 0:
    print("WARNING: LED block not found")


# =================================================
# 删除 LAN3
#
# 原来:
# port@0 -> lan3
# port@1 -> lan2
# port@2 -> lan1
#
# 改成:
# port@1 -> lan1
# port@2 -> lan2
# port@6 -> 2.5G WAN
# =================================================

# 删除 port@0
d, n = re.subn(
    r'\n\s*port@0\s*\{.*?\n\s*\};',
    '',
    d,
    count=1,
    flags=re.S
)

if n == 0:
    print("WARNING: port@0 not found")
else:
    print("LAN3 port@0 removed")


# port@1 -> lan1
d = re.sub(
    r'(port@1\s*\{\s*'
    r'reg\s*=\s*<1>;\s*'
    r'label\s*=\s*)"lan2"',
    r'\1"lan1"',
    d,
    count=1,
    flags=re.S
)

# port@2 -> lan2
d = re.sub(
    r'(port@2\s*\{\s*'
    r'reg\s*=\s*<2>;\s*'
    r'label\s*=\s*)"lan1"',
    r'\1"lan2"',
    d,
    count=1,
    flags=re.S
)


# =================================================
# 最终检查：不允许存在 lan3
# =================================================

if re.search(r'label\s*=\s*"lan3"', d):
    raise RuntimeError("ERROR: lan3 still exists in XR30 DTSI")

with open(file, "w", encoding="utf-8") as f:
    f.write(d)

print("XR30 DTSI patched successfully")
PY


# =================================================
# 3. 修改 filogic.mk
#
# 不创建新的 target。
#
# 直接修改已有:
#
# define Device/cmcc_xr30-emmc
#
# 这样你原来的:
#
# CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_cmcc_xr30-emmc=y
#
# 继续有效。
# =================================================

echo
echo "================================================="
echo "  [3/4] Patch filogic.mk"
echo "================================================="

python3 - "$FILOGIC_MK" <<'PY'
import sys
import re

file = sys.argv[1]

with open(file, "r", encoding="utf-8") as f:
    d = f.read()

pattern = (
    r'(define Device/cmcc_xr30-emmc\s*\n)'
    r'(.*?)(?=\nendef)'
)

m = re.search(pattern, d, flags=re.S)

if not m:
    raise RuntimeError(
        "ERROR: Device/cmcc_xr30-emmc not found in filogic.mk"
    )

old = m.group(0)

new = r'''define Device/cmcc_xr30-emmc
  DEVICE_VENDOR := Aigo
  DEVICE_MODEL := AGS21
  DEVICE_VARIANT := (eMMC)
  DEVICE_DTS := mt7981b-cmcc-xr30-emmc
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := f2fsck mkf2fs
  KERNEL := kernel-bin | lzma | fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef'''

d = d[:m.start()] + new + d[m.end():]

with open(file, "w", encoding="utf-8") as f:
    f.write(d)

print("filogic.mk: cmcc_xr30-emmc -> Aigo AGS21")
PY


# =================================================
# 4. 检查结果
# =================================================

echo
echo "================================================="
echo "  [4/4] FINAL CHECK"
echo "================================================="

echo
echo "===== MODEL ====="
grep -n "model =" "$EMMC_DTS" || true

echo
echo "===== ROOT COMPATIBLE ====="
grep -n 'compatible = "aigo,ags21"' "$EMMC_DTS" || true

echo
echo "===== LED ====="
grep -nE \
'status_red_led|status_blue_led|internet_led|wifi_led|GPIO_ACTIVE' \
"$XR30_DTSI" || true

echo
echo "===== PORT ====="
grep -A35 -B2 "ports {" "$XR30_DTSI" || true

echo
echo "===== LAN3 CHECK ====="

if grep -q 'label = "lan3"' "$XR30_DTSI"; then
	echo "ERROR: LAN3 STILL EXISTS!"
	exit 1
else
	echo "OK: LAN3 removed"
fi

echo
echo "===== LAN1 CHECK ====="

if grep -q 'label = "lan1"' "$XR30_DTSI"; then
	echo "OK: LAN1 exists"
else
	echo "ERROR: LAN1 missing!"
	exit 1
fi

echo
echo "===== LAN2 CHECK ====="

if grep -q 'label = "lan2"' "$XR30_DTSI"; then
	echo "OK: LAN2 exists"
else
	echo "ERROR: LAN2 missing!"
	exit 1
fi

echo
echo "===== 2.5G WAN CHECK ====="

if grep -q 'port@6' "$XR30_DTSI" && \
   grep -q 'speed = <2500>' "$XR30_DTSI"; then
	echo "OK: 2.5G port@6 exists"
else
	echo "ERROR: 2.5G port@6 missing!"
	exit 1
fi

echo
echo "===== FILOGIC DEVICE ====="

grep -A15 \
'define Device/cmcc_xr30-emmc' \
"$FILOGIC_MK" || true

echo
echo "================================================="
echo "  DTS CONVERSION COMPLETE"
echo "================================================="


# =================================================
# 以下为你原来的其它编译环境修改
# =================================================

echo
echo "==== Kernel Vermagic ===="

if [ -f include/kernel-defaults.mk ]; then
	sed -ie \
		's/^(.).*vermagic$/\1cp $(TOPDIR)\/.vermagic $(LINUX_DIR)\/.vermagic/' \
		include/kernel-defaults.mk
fi

if [ -f target/linux/generic/kernel-6.12 ]; then
	grep HASH target/linux/generic/kernel-6.12 \
		| awk -F'HASH-' '{print $2}' \
		| awk '{print $1}' \
		| md5sum \
		| awk '{print $1}' > .vermagic
fi


# =================================================
# openwrt-feeds
# =================================================

echo
echo "==== Clone custom feeds ===="

rm -rf package/xd
rm -rf package/porxy

git clone \
	-b packages \
	--depth 1 \
	--single-branch \
	https://github.com/shiyu1314/openwrt-feeds \
	package/xd

git clone \
	-b porxy \
	--depth 1 \
	--single-branch \
	https://github.com/shiyu1314/openwrt-feeds \
	package/porxy


# =================================================
# smartdns dependency cleanup
# =================================================

if [ -f package/xd/smartdns/Makefile ]; then
	sed -i -E \
		-e 's/[[:space:]]*PACKAGE_smartdns-ui:rust-bindgen/host/g' \
		-e 's/[[:space:]]*rust-bindgen/host/g' \
		-e 's/[[:space:]]*PACKAGE_smartdns-ui://g' \
		package/xd/smartdns/Makefile
fi


# =================================================
# daed
# =================================================

rm -rf package/porxy/daed
rm -rf package/porxy/luci-app-daed


# =================================================
# 删除不需要的软件包
# =================================================

rm -rf \
	feeds/luci/applications/luci-app-dockerman \
	feeds/luci/applications/luci-app-samba4 \
	feeds/luci/applications/luci-app-aria2 \
	feeds/luci/applications/luci-app-diskman

rm -rf \
	feeds/packages/net/samba4 \
	feeds/packages/net/sing-box \
	feeds/packages/net/aria2 \
	feeds/packages/net/ariang \
	feeds/packages/net/adguardhome


# =================================================
# 删除 attendedsysupgrade
# =================================================

sed -i '/luci-app-attendedsysupgrade/d' \
	feeds/luci/collections/luci-nginx/Makefile \
	feeds/luci/collections/luci-ssl-openssl/Makefile \
	feeds/luci/collections/luci-ssl/Makefile \
	feeds/luci/collections/luci/Makefile


# =================================================
# LuCI nginx
# =================================================

sed -i 's/+uhttpd /+luci-nginx /g' \
	feeds/luci/collections/luci/Makefile

sed -i 's/+uhttpd-mod-ubus //' \
	feeds/luci/collections/luci/Makefile

sed -i 's/+uhttpd /+luci-nginx /g' \
	feeds/luci/collections/luci-light/Makefile

sed -i 's/+uhttpd-mod-ubus //' \
	feeds/luci/collections/luci-light/Makefile

sed -i 's/+luci /+luci-nginx /g' \
	feeds/luci/collections/luci-ssl-openssl/Makefile

sed -i 's/+luci /+luci-nginx /g' \
	feeds/luci/collections/luci-ssl/Makefile

sed -i 's/+uhttpd +uhttpd-mod-ubus /+luci-nginx /g' \
	feeds/packages/net/wg-installer/Makefile

sed -i 's/+luci-nginx \\$/+luci-nginx/' \
	feeds/luci/collections/luci-light/Makefile


# =================================================
# feeds patches
# =================================================

if [ -d feeds/luci ]; then

	pushd feeds/luci || exit 1

	for patch in *.patch; do
		[ -f "$patch" ] || continue

		echo "Applying $patch ..."

		patch -p1 --no-backup-if-mismatch < "$patch" || {
			echo "ERROR: Failed to apply $patch"
			popd
			exit 1
		}
	done

	popd
fi


# =================================================
# Rust
# =================================================

RUST_VERSION=1.95.0
RUST_HASH=62b67230754da642a264ca0cb9fc08820c54e2ed7b3baba0289876d4cdb48c08

if [ -f feeds/packages/lang/rust/Makefile ]; then
	sed -ri \
		"s/(PKG_VERSION:=)[^\"]*/\1$RUST_VERSION/;
		 s/(PKG_HASH:=)[^\"]*/\1$RUST_HASH/" \
		feeds/packages/lang/rust/Makefile
fi


# =================================================
# MosDNS v5
# =================================================

rm -rf package/mosdns

git clone \
	https://github.com/sbwml/luci-app-mosdns \
	-b v5 \
	package/mosdns


# =================================================
# GeoData
# =================================================

rm -rf package/v2ray-geodata

git clone \
	https://github.com/sbwml/v2ray-geodata \
	package/v2ray-geodata


# =================================================
# Aurora Theme
# =================================================

rm -rf package/luci-theme-aurora

git clone \
	--depth=1 \
	https://github.com/eamonxg/luci-theme-aurora \
	package/luci-theme-aurora


# =================================================
# Aurora Config
# =================================================

rm -rf package/luci-app-aurora-config

git clone \
	--depth=1 \
	-b v1.2.0 \
	https://github.com/eamonxg/luci-app-aurora-config \
	package/luci-app-aurora-config


# =================================================
# fstools
# =================================================

rm -rf package/system/fstools

git clone \
	https://github.com/sbwml/package_system_fstools \
	-b openwrt-25.12 \
	package/system/fstools


# =================================================
# util-linux
# =================================================

rm -rf package/utils/util-linux

git clone \
	https://github.com/sbwml/package_utils_util-linux \
	-b openwrt-25.12 \
	package/utils/util-linux


# =================================================
# nghttp3
# =================================================

rm -rf feeds/packages/libs/nghttp3

git clone \
	https://github.com/sbwml/package_libs_nghttp3 \
	feeds/packages/libs/nghttp3


# =================================================
# ngtcp2
# =================================================

rm -rf feeds/packages/libs/ngtcp2

git clone \
	https://github.com/sbwml/package_libs_ngtcp2 \
	feeds/packages/libs/ngtcp2


# =================================================
# curl
# =================================================

rm -rf feeds/packages/net/curl

git clone \
	https://github.com/sbwml/feeds_packages_net_curl \
	feeds/packages/net/curl


# =================================================
# nginx
# =================================================

rm -rf feeds/packages/net/nginx

git clone \
	https://github.com/sbwml/feeds_packages_net_nginx \
	feeds/packages/net/nginx \
	-b openwrt-25.12

if [ -f feeds/packages/net/nginx/files/nginx.init ]; then
	sed -i \
		's/procd_set_param stdout 1/procd_set_param stdout 0/g;
		 s/procd_set_param stderr 1/procd_set_param stderr 0/g' \
		feeds/packages/net/nginx/files/nginx.init
fi


# =================================================
# nginx ubus
# =================================================

if [ -f feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support ]; then

	sed -i \
		's/ubus_parallel_req 2/ubus_parallel_req 6/g' \
		feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support

	sed -i \
		'/ubus_parallel_req/a\        ubus_script_timeout 300;' \
		feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support

fi


# =================================================
# nginx-util
# =================================================

if [ -f feeds/packages/net/nginx-util/Makefile ]; then
	sed -i '/etc\/nginx\/uci.conf.template/d' \
		feeds/packages/net/nginx-util/Makefile
fi


# =================================================
# uwsgi
# =================================================

if ls feeds/packages/net/uwsgi/files-luci-support/luci-*.ini >/dev/null 2>&1; then
	sed -i '$a cgi-timeout = 600' \
		feeds/packages/net/uwsgi/files-luci-support/luci-*.ini
fi

if [ -f feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini ]; then

	sed -i \
		'/limit-as/c\limit-as = 5000' \
		feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini

	sed -i \
		's/threads = 1/threads = 2/g' \
		feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini

	sed -i \
		's/processes = 3/processes = 4/g' \
		feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini

	sed -i \
		's/cheaper = 1/cheaper = 2/g' \
		feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini

fi

if [ -f feeds/packages/net/uwsgi/files/uwsgi.init ]; then
	sed -i \
		's/procd_set_param stderr 1/procd_set_param stderr 0/g' \
		feeds/packages/net/uwsgi/files/uwsgi.init
fi


# =================================================
# rpcd
# =================================================

if [ -f package/system/rpcd/files/rpcd.config ]; then
	sed -i \
		's/option timeout 30/option timeout 60/g' \
		package/system/rpcd/files/rpcd.config
fi

if [ -f feeds/luci/modules/luci-base/htdocs/luci-static/resources/rpc.js ]; then
	sed -i \
		's#20) \* 1000#60) * 1000#g' \
		feeds/luci/modules/luci-base/htdocs/luci-static/resources/rpc.js
fi


# =================================================
# luci-compat
# =================================================

if [ -f feeds/luci/modules/luci-compat/luasrc/view/cbi/full_valuefooter.htm ]; then
	sed -i '/<br \/>/d' \
		feeds/luci/modules/luci-compat/luasrc/view/cbi/full_valuefooter.htm
fi


# =================================================
# Golang 26.x
# =================================================

rm -rf feeds/packages/lang/golang

git clone \
	https://github.com/sbwml/packages_lang_golang \
	-b 26.x \
	feeds/packages/lang/golang


# =================================================
# 更新 feeds
# =================================================

echo
echo "==== Update feeds ===="

./scripts/feeds update -a
./scripts/feeds install -a


# =================================================
# ttyd
# =================================================

if [ -f feeds/packages/utils/ttyd/files/ttyd.config ]; then
	sed -i \
		's|/bin/login|/bin/login -f root|g' \
		feeds/packages/utils/ttyd/files/ttyd.config
fi


# =================================================
# OpenWrt banner
# =================================================

sudo rm -rf package/base-files/files/etc/banner

if [ -f package/base-files/files/etc/openwrt_release ]; then

	sed -i \
		"s/%D %V %C/%D %V $(TZ=UTC-8 date +%Y.%m.%d)/" \
		package/base-files/files/etc/openwrt_release

	sed -i \
		"s/%R/by $OP_author/" \
		package/base-files/files/etc/openwrt_release

fi


DATE_NOW=$(date +"%Y-%m-%d")

cat > package/base-files/files/etc/banner <<EOF

  ___                     ________
 |       |.-----.-----.-----.|  |  |  |.----.|  |_
 |   -   ||  _  |  -  |     ||  |  |  ||   _||   _|
 |_______||_____|_____|__|__||________||__|  |____|

 -----------------------------------------------------
        Aigo AGS21 OpenWrt
        ${DATE_NOW} by ${OP_author}
 -----------------------------------------------------

EOF


# =================================================
# 最终再次确认 DTS
# =================================================

echo
echo "================================================="
echo " FINAL DEVICE CHECK"
echo "================================================="

echo
echo "[DTS]"
grep -n 'model = ' "$EMMC_DTS"

echo
echo "[COMPATIBLE]"
grep -n 'compatible = "aigo,ags21"' "$EMMC_DTS"

echo
echo "[PORTS]"
grep -A30 "ports {" "$XR30_DTSI"

echo
echo "[FILOGIC]"
grep -A15 \
'define Device/cmcc_xr30-emmc' \
"$FILOGIC_MK"

echo
echo "================================================="
echo " Aigo AGS21 patch completed successfully!"
echo "================================================="
```
