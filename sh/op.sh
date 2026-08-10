#!/bin/bash

set -e

echo "================================================="
echo " OpenWrt 25.12 / MT7981 / Aigo AGS21 eMMC"
echo " CMCC XR30 -> Aigo AGS21"
echo "================================================="

SOURCE_DIR="$(pwd)"

DTS_DIR="target/linux/mediatek/dts"
IMAGE_DIR="target/linux/mediatek/image"

EMMC_DTS="$DTS_DIR/mt7981b-cmcc-xr30-emmc.dts"
XR30_DTSI="$DTS_DIR/mt7981b-cmcc-xr30.dtsi"
FILOGIC_MK="$IMAGE_DIR/filogic.mk"

###############################################################################
# 检查源码
###############################################################################

echo
echo "==== Check source tree ===="

if [ ! -d "target/linux/mediatek" ]; then
    echo "ERROR: target/linux/mediatek not found"
    exit 1
fi

if [ ! -f "$EMMC_DTS" ]; then
    echo "ERROR: $EMMC_DTS not found"
    exit 1
fi

if [ ! -f "$XR30_DTSI" ]; then
    echo "ERROR: $XR30_DTSI not found"
    exit 1
fi

if [ ! -f "$FILOGIC_MK" ]; then
    echo "ERROR: $FILOGIC_MK not found"
    exit 1
fi

echo "Found DTS:"
echo "  $EMMC_DTS"

echo "Found DTSI:"
echo "  $XR30_DTSI"

echo "Found image definition:"
echo "  $FILOGIC_MK"


###############################################################################
# 1. 修改 eMMC DTS
###############################################################################

echo
echo "================================================="
echo " Patch eMMC DTS"
echo "================================================="

python3 - "$EMMC_DTS" <<'PY'
import sys
import re

file = sys.argv[1]

with open(file, "r", encoding="utf-8") as f:
    d = f.read()

# 只修改根节点 model
d = re.sub(
    r'(^\s*model\s*=\s*)"[^"]*"\s*;',
    r'\1"Aigo AGS21";',
    d,
    count=1,
    flags=re.M
)

# 只修改根节点 compatible
d = re.sub(
    r'(^\s*compatible\s*=\s*)"cmcc,xr30-emmc"[^;]*;',
    r'\1"aigo,ags21", "mediatek,mt7981";',
    d,
    count=1,
    flags=re.M
)

# 防止出现 XR30 名称
d = d.replace(
    'model = "CMCC XR30 (eMMC version)";',
    'model = "Aigo AGS21";'
)

d = d.replace(
    'compatible = "cmcc,xr30-emmc", "mediatek,mt7981";',
    'compatible = "aigo,ags21", "mediatek,mt7981";'
)

with open(file, "w", encoding="utf-8") as f:
    f.write(d)

print("eMMC DTS patched successfully")
PY


###############################################################################
# 2. 修改 XR30 DTSI
###############################################################################

echo
echo "================================================="
echo " Patch XR30 DTSI"
echo "================================================="

python3 - "$XR30_DTSI" <<'PY'
import sys
import re

file = sys.argv[1]

with open(file, "r", encoding="utf-8") as f:
    d = f.read()


###############################################################################
# aliases
###############################################################################

aliases = '''aliases {
    led-boot = &status_red_led;
    led-failsafe = &status_red_led;
    led-running = &status_blue_led;
    led-upgrade = &status_blue_led;
    serial0 = &uart0;
};'''

d = re.sub(
    r'aliases\s*\{.*?\n\};',
    aliases,
    d,
    count=1,
    flags=re.S
)


###############################################################################
# LED
###############################################################################

leds = '''leds {
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

# 精确替换 / { 里面的 leds 节点
d = re.sub(
    r'(?m)^leds\s*\{.*?\n\};',
    leds,
    d,
    count=1,
    flags=re.S
)


###############################################################################
# 删除 XR30 原来的 LAN3
###############################################################################

d = re.sub(
    r'\n\s*port@0\s*\{.*?\n\s*\};',
    '',
    d,
    count=1,
    flags=re.S
)


###############################################################################
# LAN1
###############################################################################

d = re.sub(
    r'(port@1\s*\{\s*'
    r'reg\s*=\s*<1>;\s*'
    r'label\s*=\s*)"[^"]*"',
    r'\1"lan1"',
    d,
    count=1,
    flags=re.S
)


###############################################################################
# LAN2
###############################################################################

d = re.sub(
    r'(port@2\s*\{\s*'
    r'reg\s*=\s*<2>;\s*'
    r'label\s*=\s*)"[^"]*"',
    r'\1"lan2"',
    d,
    count=1,
    flags=re.S
)


###############################################################################
# 防止残留 XR30 LED 名称
###############################################################################

d = d.replace('label = "xr30:red";', 'label = "red:status";')
d = d.replace('label = "xr30:white";', 'label = "white:status";')


with open(file, "w", encoding="utf-8") as f:
    f.write(d)

print("XR30 DTSI patched successfully")
PY


###############################################################################
# 3. 检查 DTS
###############################################################################

echo
echo "================================================="
echo " AGS21 DTS CHECK"
echo "================================================="

echo
echo "===== MODEL ====="
grep -n 'model =' "$EMMC_DTS" || true

echo
echo "===== ROOT COMPATIBLE ====="
grep -n 'compatible = "aigo,ags21"' "$EMMC_DTS" || true

echo
echo "===== LED ====="
grep -nE \
'led-boot|led-failsafe|led-running|led-upgrade|status_red_led|status_blue_led|internet_led|wifi_led|gpio' \
"$XR30_DTSI" || true


###############################################################################
# 4. 检查网口
###############################################################################

echo
echo "===== PORT ====="

grep -A40 'ports {' "$XR30_DTSI" || true

echo
echo "===== LAN3 CHECK ====="

if grep -q 'label = "lan3"' "$XR30_DTSI"; then
    echo "ERROR: LAN3 still exists"
    exit 1
else
    echo "OK: LAN3 removed"
fi

echo
echo "===== LAN1 CHECK ====="

if grep -q 'label = "lan1"' "$XR30_DTSI"; then
    echo "OK: LAN1 exists"
else
    echo "ERROR: LAN1 missing"
    exit 1
fi

echo
echo "===== LAN2 CHECK ====="

if grep -q 'label = "lan2"' "$XR30_DTSI"; then
    echo "OK: LAN2 exists"
else
    echo "ERROR: LAN2 missing"
    exit 1
fi

echo
echo "===== 2.5G WAN CHECK ====="

if grep -q 'port@6' "$XR30_DTSI" && \
   grep -q 'speed = <2500>' "$XR30_DTSI"; then
    echo "OK: 2.5G port@6 exists"
else
    echo "ERROR: 2.5G port@6 missing"
    exit 1
fi


###############################################################################
# 5. 修改 filogic.mk
###############################################################################

echo
echo "================================================="
echo " Patch filogic.mk"
echo "================================================="

python3 - "$FILOGIC_MK" <<'PY'
import sys
import re

file = sys.argv[1]

with open(file, "r", encoding="utf-8") as f:
    d = f.read()


###############################################################################
# 找 cmcc_xr30-emmc
###############################################################################

pattern = r'define Device/cmcc_xr30-emmc.*?endef'

match = re.search(pattern, d, re.S)

if not match:
    print("ERROR: Device/cmcc_xr30-emmc not found")
    sys.exit(1)


new_device = '''define Device/cmcc_xr30-emmc
  DEVICE_VENDOR := Aigo
  DEVICE_MODEL := AGS21
  DEVICE_VARIANT := (eMMC)
  DEVICE_DTS := mt7981b-cmcc-xr30-emmc
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := f2fsck mkf2fs
  KERNEL := kernel-bin | lzma | fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS := kernel-bin | lzma | \\
\tfit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef'''

d = d[:match.start()] + new_device + d[match.end():]


###############################################################################
# 确保 TARGET_DEVICES 只有一次
###############################################################################

lines = d.splitlines()

new_lines = []
target_added = False

for line in lines:

    if line.strip() == "TARGET_DEVICES += cmcc_xr30-emmc":

        if not target_added:
            new_lines.append(line)
            target_added = True

        continue

    new_lines.append(line)

d = "\n".join(new_lines) + "\n"


###############################################################################
# 如果没有 TARGET_DEVICES 就补
###############################################################################

if not target_added:

    marker = "define Device/cmcc_xr30-nand"

    if marker in d:
        d = d.replace(
            marker,
            "TARGET_DEVICES += cmcc_xr30-emmc\n\n" + marker,
            1
        )
    else:
        d += "\nTARGET_DEVICES += cmcc_xr30-emmc\n"


with open(file, "w", encoding="utf-8") as f:
    f.write(d)

print("filogic.mk: cmcc_xr30-emmc -> Aigo AGS21")
PY


###############################################################################
# 6. filogic 检查
###############################################################################

echo
echo "================================================="
echo " FILOGIC DEVICE CHECK"
echo "================================================="

sed -n \
'/define Device\/cmcc_xr30-emmc/,/endef/p' \
"$FILOGIC_MK"

echo
echo "===== TARGET DEVICE ====="

grep -n \
'TARGET_DEVICES += cmcc_xr30-emmc' \
"$FILOGIC_MK" || {
    echo "ERROR: TARGET_DEVICES entry missing"
    exit 1
}


###############################################################################
# 7. Kernel Vermagic
###############################################################################

echo
echo "================================================="
echo " Kernel Vermagic"
echo "================================================="

if [ -f "include/kernel-defaults.mk" ]; then

    # 不再使用错误的 \1 捕获组
    # 直接在 kernel build 过程中复制 .vermagic

    if grep -q '\.vermagic' include/kernel-defaults.mk; then

        sed -i \
            's|^[[:space:]]*cp .*\.vermagic.*$|	cp $(TOPDIR)/.vermagic $(LINUX_DIR)/.vermagic|' \
            include/kernel-defaults.mk

    else

        cat >> include/kernel-defaults.mk <<'EOF'

# Aigo AGS21 custom vermagic
	@cp $(TOPDIR)/.vermagic $(LINUX_DIR)/.vermagic
EOF

    fi
fi


###############################################################################
# 生成 .vermagic
###############################################################################

if [ -f "target/linux/generic/kernel-6.12" ]; then

    grep HASH target/linux/generic/kernel-6.12 \
        | awk -F'HASH-' '{print $2}' \
        | awk '{print $1}' \
        | md5sum \
        | awk '{print $1}' \
        > .vermagic

else

    echo "WARNING: kernel-6.12 hash file not found"

    echo "00000000000000000000000000000000" > .vermagic
fi

echo "Vermagic:"
cat .vermagic


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
