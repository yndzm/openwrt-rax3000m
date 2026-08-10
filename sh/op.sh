#!/bin/bash

set -e

echo "=================================================="
echo " Aigo AGS21 / MT7981 / eMMC"
echo " Based on CMCC XR30 eMMC DTS"
echo "=================================================="


##################################################
# Source paths
##################################################

DTS_DIR="target/linux/mediatek/dts"

EMMC_DTS="$DTS_DIR/mt7981b-cmcc-xr30-emmc.dts"
XR30_DTSI="$DTS_DIR/mt7981b-cmcc-xr30.dtsi"

FILOGIC_MK="target/linux/mediatek/image/filogic.mk"


##################################################
# Check source tree
##################################################

echo
echo "===== CHECK SOURCE TREE ====="

if [ ! -f "$EMMC_DTS" ]; then
	echo "ERROR: eMMC DTS not found:"
	echo "$EMMC_DTS"
	exit 1
fi

if [ ! -f "$XR30_DTSI" ]; then
	echo "ERROR: XR30 DTSI not found:"
	echo "$XR30_DTSI"
	exit 1
fi

if [ ! -f "$FILOGIC_MK" ]; then
	echo "ERROR: filogic.mk not found:"
	echo "$FILOGIC_MK"
	exit 1
fi

echo "Found DTS:"
echo "$EMMC_DTS"

echo "Found DTSI:"
echo "$XR30_DTSI"

echo "Found image definition:"
echo "$FILOGIC_MK"



##################################################
# Patch eMMC DTS
##################################################

echo
echo "===== PATCH eMMC DTS ====="


python3 - "$EMMC_DTS" <<'PY'
import sys
import re

p = sys.argv[1]

with open(p, "r", encoding="utf-8") as f:
    d = f.read()

# Model
d = re.sub(
    r'model\s*=\s*"[^"]*";',
    'model = "Aigo AGS21";',
    d,
    count=1
)

# Compatible
d = re.sub(
    r'compatible\s*=\s*"cmcc,xr30-emmc"\s*,\s*"mediatek,mt7981"\s*;',
    'compatible = "aigo,ags21", "mediatek,mt7981";',
    d,
    count=1
)

with open(p, "w", encoding="utf-8") as f:
    f.write(d)

print("eMMC DTS patched successfully")
PY



##################################################
# Patch XR30 DTSI
##################################################

echo
echo "===== PATCH XR30 DTSI ====="


python3 - "$XR30_DTSI" <<'PY'
import sys
import re

p = sys.argv[1]

with open(p, "r", encoding="utf-8") as f:
    d = f.read()


##################################################
# aliases
##################################################

d = re.sub(
    r'aliases\s*\{.*?\n\s*\};',
    '''aliases {
	led-boot = &status_red_led;
	led-failsafe = &status_red_led;
	led-running = &status_blue_led;
	led-upgrade = &status_blue_led;
	serial0 = &uart0;
};''',
    d,
    count=1,
    flags=re.S
)


##################################################
# LED
##################################################

led_block = '''leds {
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


# 精确寻找 leds { 节点
start = d.find("leds {")

if start == -1:
    raise SystemExit("ERROR: leds node not found")

depth = 0
end = None

for i in range(start, len(d)):
    if d[i] == "{":
        depth += 1
    elif d[i] == "}":
        depth -= 1
        if depth == 0:
            end = i + 1
            break

if end is None:
    raise SystemExit("ERROR: leds node parse failed")

d = d[:start] + led_block + d[end:]


##################################################
# Remove LAN3
##################################################

lan3_pattern = r'''
\s*port@0\s*\{
\s*reg\s*=\s*<0>\s*;
\s*label\s*=\s*"lan3"\s*;
\s*\}\s*;
'''

d, removed = re.subn(
    lan3_pattern,
    '',
    d,
    count=1,
    flags=re.S | re.X
)

if removed != 1:
    raise SystemExit("ERROR: LAN3 port@0 not found")


##################################################
# LAN1 / LAN2
##################################################

# port@1 -> lan1
d = re.sub(
    r'(port@1\s*\{\s*reg\s*=\s*<1>\s*;\s*label\s*=\s*)"lan2"',
    r'\1"lan1"',
    d,
    count=1,
    flags=re.S
)

# port@2 -> lan2
d = re.sub(
    r'(port@2\s*\{\s*reg\s*=\s*<2>\s*;\s*label\s*=\s*)"lan1"',
    r'\1"lan2"',
    d,
    count=1,
    flags=re.S
)


with open(p, "w", encoding="utf-8") as f:
    f.write(d)

print("XR30 DTSI patched successfully")
PY



##################################################
# Patch filogic.mk
##################################################

echo
echo "===== PATCH FILOGIC.MK ====="


python3 - "$FILOGIC_MK" <<'PY'
import sys
import re

p = sys.argv[1]

with open(p, "r", encoding="utf-8") as f:
    d = f.read()


# 只修改 cmcc_xr30-emmc 这个设备
pattern = r'(define Device/cmcc_xr30-emmc\b.*?endef)'

m = re.search(pattern, d, flags=re.S)

if not m:
    raise SystemExit(
        "ERROR: Device/cmcc_xr30-emmc definition not found"
    )

block = m.group(1)

# Vendor
block = re.sub(
    r'^\s*DEVICE_VENDOR\s*:=.*$',
    '  DEVICE_VENDOR := Aigo',
    block,
    flags=re.M
)

# Model
block = re.sub(
    r'^\s*DEVICE_MODEL\s*:=.*$',
    '  DEVICE_MODEL := AGS21',
    block,
    flags=re.M
)

# Variant
if re.search(r'^\s*DEVICE_VARIANT\s*:=', block, flags=re.M):
    block = re.sub(
        r'^\s*DEVICE_VARIANT\s*:=.*$',
        '  DEVICE_VARIANT := eMMC',
        block,
        flags=re.M
    )
else:
    block = block.replace(
        '  DEVICE_MODEL := AGS21',
        '  DEVICE_MODEL := AGS21\n'
        '  DEVICE_VARIANT := eMMC'
    )

d = d[:m.start()] + block + d[m.end():]


with open(p, "w", encoding="utf-8") as f:
    f.write(d)

print("filogic.mk patched successfully")
PY



##################################################
# Verify DTS
##################################################

echo
echo "===== DTS ====="

grep -nE 'model =|compatible = "aigo,ags21"' \
"$EMMC_DTS"



##################################################
# Verify LED
##################################################

echo
echo "===== LED GPIO ====="

grep -nE \
'led-boot|led-failsafe|led-running|led-upgrade|status_red_led|status_blue_led|internet_led|wifi_led|gpios' \
"$XR30_DTSI"



##################################################
# Verify PORT
##################################################

echo
echo "===== PORT ====="

grep -A35 'ports {' \
"$XR30_DTSI"



##################################################
# LAN3 check
##################################################

echo
echo "===== LAN3 ====="

if grep -q 'label = "lan3"' "$XR30_DTSI"; then
	echo "ERROR: LAN3 exists"
	exit 1
else
	echo "OK: LAN3 removed"
fi



##################################################
# LAN1 check
##################################################

echo
echo "===== LAN1 ====="

if grep -A4 'port@1 {' "$XR30_DTSI" | grep -q 'label = "lan1"'; then
	echo "OK: port@1 = LAN1"
else
	echo "ERROR: port@1 is not LAN1"
	exit 1
fi



##################################################
# LAN2 check
##################################################

echo
echo "===== LAN2 ====="

if grep -A4 'port@2 {' "$XR30_DTSI" | grep -q 'label = "lan2"'; then
	echo "OK: port@2 = LAN2"
else
	echo "ERROR: port@2 is not LAN2"
	exit 1
fi



##################################################
# 2.5G check
##################################################

echo
echo "===== 2.5G WAN ====="

if grep -A12 'port@6 {' "$XR30_DTSI" | grep -q '2500base-x'; then
	echo "OK: port@6 = 2.5G"
else
	echo "ERROR: 2.5G port@6 not found"
	exit 1
fi



##################################################
# eMMC check
##################################################

echo
echo "===== eMMC ====="

if grep -q '&mmc0' "$EMMC_DTS"; then
	echo "OK: eMMC mmc0 exists"
else
	echo "ERROR: eMMC mmc0 missing"
	exit 1
fi



##################################################
# WiFi check
##################################################

echo
echo "===== WIFI ====="

if grep -q '&wifi' "$EMMC_DTS"; then
	echo "OK: WiFi node exists"
else
	echo "ERROR: WiFi node missing"
	exit 1
fi



##################################################
# filogic device
##################################################

echo
echo "===== FILOGIC DEVICE ====="

grep -A16 \
'define Device/cmcc_xr30-emmc' \
"$FILOGIC_MK"



##################################################
# final
##################################################

echo
echo "=================================================="
echo " AGS21 DTS CONVERSION SUCCESS"
echo "=================================================="

echo
echo "DTS      : Aigo AGS21"
echo "Storage  : eMMC"
echo "LAN1     : port@1"
echo "LAN2     : port@2"
echo "WAN      : port@6 / 2.5G"
echo "LAN3     : removed"
echo "LED      : AGS21 GPIO"
echo "WiFi     : enabled"
echo
echo "==== AGS21 DTS DONE ===="

###############################################################################
# 8. OpenWrt custom feeds
###############################################################################

echo
echo "================================================="
echo " Clone custom feeds"
echo "================================================="

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


###############################################################################
# 9. smartdns dependency cleanup
###############################################################################

if [ -f package/xd/smartdns/Makefile ]; then

    sed -i -E \
        -e 's/[[:space:]]*\*PACKAGE_smartdns-ui:rust-bindgen/host/g' \
        -e 's/[[:space:]]*\*rust-bindgen/host/g' \
        -e 's/[[:space:]]*\*PACKAGE_smartdns-ui://g' \
        package/xd/smartdns/Makefile

fi


###############################################################################
# 10. 删除 daed
###############################################################################

echo
echo "==== Remove source daed ===="

rm -rf package/porxy/daed
rm -rf package/porxy/luci-app-daed


###############################################################################
# 11. 删除冲突/不需要的软件包
###############################################################################

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


###############################################################################
# 12. 删除 attendedsysupgrade
###############################################################################

for file in \
    feeds/luci/collections/luci-nginx/Makefile \
    feeds/luci/collections/luci-ssl-openssl/Makefile \
    feeds/luci/collections/luci-ssl/Makefile \
    feeds/luci/collections/luci/Makefile
do
    [ -f "$file" ] && sed -i '/luci-app-attendedsysupgrade/d' "$file"
done


###############################################################################
# 13. nginx 替代 uhttpd
###############################################################################

[ -f feeds/luci/collections/luci/Makefile ] && \
sed -i 's/+uhttpd /+luci-nginx /g' \
feeds/luci/collections/luci/Makefile

[ -f feeds/luci/collections/luci/Makefile ] && \
sed -i 's/+uhttpd-mod-ubus //' \
feeds/luci/collections/luci/Makefile

[ -f feeds/luci/collections/luci-light/Makefile ] && \
sed -i 's/+uhttpd /+luci-nginx /g' \
feeds/luci/collections/luci-light/Makefile

[ -f feeds/luci/collections/luci-light/Makefile ] && \
sed -i '/uhttpd-mod-ubus/d' \
feeds/luci/collections/luci-light/Makefile

[ -f feeds/luci/collections/luci-ssl-openssl/Makefile ] && \
sed -i 's/+luci /+luci-nginx /g' \
feeds/luci/collections/luci-ssl-openssl/Makefile

[ -f feeds/luci/collections/luci-ssl/Makefile ] && \
sed -i 's/+luci /+luci-nginx /g' \
feeds/luci/collections/luci-ssl/Makefile

[ -f feeds/packages/net/wg-installer/Makefile ] && \
sed -i \
's/+uhttpd +uhttpd-mod-ubus /+luci-nginx /g' \
feeds/packages/net/wg-installer/Makefile

[ -f feeds/luci/collections/luci-light/Makefile ] && \
sed -i 's/+luci-nginx \\$/+luci-nginx/' \
feeds/luci/collections/luci-light/Makefile


###############################################################################
# 14. Luci patches
###############################################################################

if [ -d feeds/luci ]; then

    pushd feeds/luci >/dev/null

    for patch in *.patch; do

        [ -f "$patch" ] || continue

        echo "Applying $patch ..."

        patch \
            -p1 \
            --no-backup-if-mismatch \
            < "$patch" || {

            echo "ERROR: Failed to apply $patch"

            popd >/dev/null

            exit 1
        }

    done

    popd >/dev/null
fi


###############################################################################
# 15. Rust
###############################################################################

echo
echo "==== Rust ===="

RUST_VERSION="1.95.0"
RUST_HASH="62b67230754da642a264ca0cb9fc08820c54e2ed7b3baba0289876d4cdb48c08"

if [ -f feeds/packages/lang/rust/Makefile ]; then

    sed -ri \
        "s/(PKG_VERSION:=)[^\"]*/\1$RUST_VERSION/;
         s/(PKG_HASH:=)[^\"]*/\1$RUST_HASH/" \
        feeds/packages/lang/rust/Makefile

fi


###############################################################################
# 16. MosDNS v5
###############################################################################

echo
echo "==== MosDNS v5 ===="

rm -rf package/mosdns

git clone \
    https://github.com/sbwml/luci-app-mosdns \
    -b v5 \
    package/mosdns


###############################################################################
# 17. GeoData
###############################################################################

rm -rf package/v2ray-geodata

git clone \
    https://github.com/sbwml/v2ray-geodata \
    package/v2ray-geodata


###############################################################################
# 18. Aurora Theme
###############################################################################

rm -rf package/luci-theme-aurora

git clone \
    --depth=1 \
    https://github.com/eamonxg/luci-theme-aurora \
    package/luci-theme-aurora


###############################################################################
# 19. Aurora Config
###############################################################################

rm -rf package/luci-app-aurora-config

git clone \
    --depth=1 \
    -b v1.2.0 \
    https://github.com/eamonxg/luci-app-aurora-config \
    package/luci-app-aurora-config


###############################################################################
# 20. fstools
###############################################################################

rm -rf package/system/fstools

git clone \
    https://github.com/sbwml/package_system_fstools \
    -b openwrt-25.12 \
    package/system/fstools


###############################################################################
# 21. util-linux
###############################################################################

rm -rf package/utils/util-linux

git clone \
    https://github.com/sbwml/package_utils_util-linux \
    -b openwrt-25.12 \
    package/utils/util-linux


###############################################################################
# 22. nghttp3
###############################################################################

rm -rf feeds/packages/libs/nghttp3

git clone \
    https://github.com/sbwml/package_libs_nghttp3 \
    feeds/packages/libs/nghttp3


###############################################################################
# 23. ngtcp2
###############################################################################

rm -rf feeds/packages/libs/ngtcp2

git clone \
    https://github.com/sbwml/package_libs_ngtcp2 \
    feeds/packages/libs/ngtcp2


###############################################################################
# 24. curl
###############################################################################

rm -rf feeds/packages/net/curl

git clone \
    https://github.com/sbwml/feeds_packages_net_curl \
    feeds/packages/net/curl


###############################################################################
# 25. nginx
###############################################################################

rm -rf feeds/packages/net/nginx

git clone \
    -b openwrt-25.12 \
    https://github.com/sbwml/feeds_packages_net_nginx \
    feeds/packages/net/nginx

if [ -f feeds/packages/net/nginx/files/nginx.init ]; then

    sed -i \
        's/procd_set_param stdout 1/procd_set_param stdout 0/g;
         s/procd_set_param stderr 1/procd_set_param stderr 0/g' \
        feeds/packages/net/nginx/files/nginx.init

fi


###############################################################################
# 26. nginx ubus
###############################################################################

if [ -f feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support ]; then

    sed -i \
        's/ubus_parallel_req 2/ubus_parallel_req 6/g' \
        feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support

    sed -i \
        '/ubus_parallel_req/a\        ubus_script_timeout 300;' \
        feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support

fi


###############################################################################
# 27. nginx-util
###############################################################################

if [ -f feeds/packages/net/nginx-util/Makefile ]; then

    sed -i \
        '/etc\/nginx\/uci.conf.template/d' \
        feeds/packages/net/nginx-util/Makefile

fi


###############################################################################
# 28. uwsgi
###############################################################################

if [ -d feeds/packages/net/uwsgi/files-luci-support ]; then

    for file in feeds/packages/net/uwsgi/files-luci-support/luci-*.ini; do

        [ -f "$file" ] || continue

        echo "cgi-timeout = 600" >> "$file"

    done

fi

if [ -f feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini ]; then

    sed -i 's/limit-as = .*/limit-as = 5000/' \
        feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini

    sed -i 's/threads = 1/threads = 2/g' \
        feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini

    sed -i 's/processes = 3/processes = 4/g' \
        feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini

    sed -i 's/cheaper = 1/cheaper = 2/g' \
        feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini

fi

if [ -f feeds/packages/net/uwsgi/files/uwsgi.init ]; then

    sed -i \
        's/procd_set_param stderr 1/procd_set_param stderr 0/g' \
        feeds/packages/net/uwsgi/files/uwsgi.init

fi


###############################################################################
# 29. rpcd timeout
###############################################################################

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


###############################################################################
# 30. luci-compat
###############################################################################

if [ -f feeds/luci/modules/luci-compat/luasrc/view/cbi/full_valuefooter.htm ]; then

    sed -i '/<br \/>/d' \
        feeds/luci/modules/luci-compat/luasrc/view/cbi/full_valuefooter.htm

fi


###############################################################################
# 31. Golang 26.x
###############################################################################

rm -rf feeds/packages/lang/golang

git clone \
    https://github.com/sbwml/packages_lang_golang \
    -b 26.x \
    feeds/packages/lang/golang


###############################################################################
# 32. 更新 feeds
###############################################################################

echo
echo "================================================="
echo " Update feeds"
echo "================================================="

./scripts/feeds update -a
./scripts/feeds install -a


###############################################################################
# 33. ttyd root login
###############################################################################

if [ -f feeds/packages/utils/ttyd/files/ttyd.config ]; then

    sed -i \
        's|/bin/login|/bin/login -f root|g' \
        feeds/packages/utils/ttyd/files/ttyd.config

fi


###############################################################################
# 34. Banner
###############################################################################

rm -rf package/base-files/files/etc/banner

mkdir -p package/base-files/files/etc

date_now=$(TZ=UTC-8 date +"%Y.%m.%d")

cat > package/base-files/files/etc/banner <<EOF

  ______                     ________        __
 |      |.-----.-----.-----.|  |  |  |.----.|  |_
 |   -  ||  _  |  -__|     ||  |  |  ||   _||   _|
 |______||_____|_____|__|__||________||__|  |____|
 -----------------------------------------------------
        Aigo AGS21
 -----------------------------------------------------
        $date_now by ${OP_author:-masaaki}
 -----------------------------------------------------

EOF


###############################################################################
# 35. OpenWrt release
###############################################################################

if [ -f package/base-files/files/etc/openwrt_release ]; then

    sed -i \
        "s/%D %V %C/%D %V $(TZ=UTC-8 date +%Y.%m.%d)/" \
        package/base-files/files/etc/openwrt_release

    if [ -n "${OP_author:-}" ]; then

        sed -i \
            "s/%R/by $OP_author/" \
            package/base-files/files/etc/openwrt_release

    fi

fi


###############################################################################
# 36. 最终检查
###############################################################################

echo
echo "================================================="
echo " FINAL AGS21 CHECK"
echo "================================================="

echo
echo "===== DTS ====="

grep -n 'model = "Aigo AGS21"' "$EMMC_DTS"

grep -n \
'compatible = "aigo,ags21", "mediatek,mt7981"' \
"$EMMC_DTS"


echo
echo "===== LED GPIO ====="

grep -nE \
'status_red_led|status_blue_led|internet_led|wifi_led' \
"$XR30_DTSI"


echo
echo "===== PORT ====="

grep -A30 "ports {" "$XR30_DTSI"


echo
echo "===== LAN3 ====="

if grep -q 'label = "lan3"' "$XR30_DTSI"; then
    echo "ERROR: LAN3 exists"
    exit 1
else
    echo "OK: LAN3 removed"
fi


echo
echo "===== LAN1 ====="

grep -q 'label = "lan1"' "$XR30_DTSI" && \
echo "OK: LAN1"


echo
echo "===== LAN2 ====="

grep -q 'label = "lan2"' "$XR30_DTSI" && \
echo "OK: LAN2"


echo
echo "===== 2.5G ====="

grep -q 'speed = <2500>' "$XR30_DTSI" && \
echo "OK: 2.5G WAN"


echo
echo "===== FILOGIC ====="

sed -n \
'/define Device\/cmcc_xr30-emmc/,/endef/p' \
"$FILOGIC_MK"


echo
echo "===== TARGET ====="

grep -n \
'TARGET_DEVICES += cmcc_xr30-emmc' \
"$FILOGIC_MK"


echo
echo "===== VERMAGIC ====="

cat .vermagic


echo
echo "================================================="
echo " AGS21 PATCH COMPLETE"
echo "================================================="
