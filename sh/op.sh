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


echo "==== Convert CMCC XR30 DTS to Aigo AGS21 ===="


DTS_DIR="target/linux/mediatek/dts"


XR30_DTS=$(find "$DTS_DIR" -name "mt7981b-cmcc-xr30-emmc.dts" | head -n1)


if [ -z "$XR30_DTS" ]; then
    echo "XR30 DTS not found"
    exit 1
fi


echo "Using:"
echo "$XR30_DTS"



python3 - "$XR30_DTS" <<'EOF'

import sys
import re


file=sys.argv[1]


with open(file) as f:
    dts=f.read()



# ======================
# MODEL
# ======================


dts=re.sub(
r'model = ".*?";',
'model = "Aigo AGS21";',
dts
)



dts=re.sub(
r'compatible = .*?;',
'compatible = "aigo,ags21", "mediatek,mt7981";',
dts,
count=1
)



# ======================
# LED
# ======================


led=r'''
leds {
	compatible = "gpio-leds";

	status_red_led: led-0 {
		label = "red:status";
		gpios = <&pio 6 GPIO_ACTIVE_LOW>;
	};

	status_blue_led: led-1 {
		label = "blue:status";
		gpios = <&pio 4 GPIO_ACTIVE_LOW>;
	};

	internet_led: led-2 {
		label = "green:status";
		gpios = <&pio 29 GPIO_ACTIVE_LOW>;
	};

	wifi_led: led-3 {
		label = "white:status";
		gpios = <&pio 30 GPIO_ACTIVE_LOW>;
	};
};
'''


dts=re.sub(
r'leds\s*\{.*?\n\};',
led,
dts,
flags=re.S
)



# ======================
# WATCHDOG
# ======================


dts=dts.replace(
'''&watchdog {
status = "disabled";
};''',
'''&watchdog {
status = "okay";
};'''
)



# ======================
# ETH
# ======================


eth=r'''
&eth {
status = "okay";

gmac0: mac@0 {
	compatible = "mediatek,eth-mac";
	reg = <0>;
	phy-mode = "2500base-x";

	fixed-link {
		speed = <2500>;
		full-duplex;
		pause;
	};
};

gmac1: mac@1 {
	compatible = "mediatek,eth-mac";
	reg = <1>;
	phy-mode = "gmii";
	phy-handle = <&int_gbe_phy>;
};
};
'''


dts=re.sub(
r'&eth\s*\{.*?\n\};',
eth,
dts,
flags=re.S
)



# ======================
# MDIO SWITCH
# ======================


switch=r'''
&mdio_bus {
switch: switch@1f {
	compatible = "mediatek,mt7531";
	reg = <31>;
	reset-gpios = <&pio 39 GPIO_ACTIVE_HIGH>;
	interrupt-controller;
	#interrupt-cells = <1>;
	interrupt-parent = <&pio>;
	interrupts = <38 IRQ_TYPE_LEVEL_HIGH>;
};
};
'''


dts=re.sub(
r'&mdio_bus\s*\{.*?\n\};',
switch,
dts,
flags=re.S
)



# ======================
# PORT
# ======================


ports=r'''
&switch {
ports {
	#address-cells = <1>;
	#size-cells = <0>;

	port@1 {
		reg = <1>;
		label = "lan1";
	};

	port@2 {
		reg = <2>;
		label = "lan2";
	};

	port@6 {
		reg = <6>;
		ethernet = <&gmac0>;
		phy-mode = "2500base-x";

		fixed-link {
			speed = <2500>;
			full-duplex;
			pause;
		};
	};
};
};
'''


dts=re.sub(
r'&switch\s*\{.*?\n\};',
ports,
dts,
flags=re.S
)

with open(file,'w') as f:
    f.write(dts)

print("AGS21 conversion finished")

EOF

echo "===== CHECK MODEL ====="

grep -n "model =" "$XR30_DTS"

echo "===== CHECK LED ====="

grep -A20 "leds {" "$XR30_DTS"

echo "===== CHECK ETH ====="

grep -A25 "&eth" "$XR30_DTS"

echo "===== CHECK PORT ====="

grep -A30 "&switch" "$XR30_DTS"

echo "==== DONE ===="

# kenrel Vermagic
sed -ie 's/^\(.\).*vermagic$/\1cp $(TOPDIR)\/.vermagic $(LINUX_DIR)\/.vermagic/' include/kernel-defaults.mk
grep HASH target/linux/generic/kernel-6.12 | awk -F'HASH-' '{print $2}' | awk '{print $1}' | md5sum | awk '{print $1}' > .vermagic

git clone -b packages --depth 1 --single-branch https://github.com/shiyu1314/openwrt-feeds package/xd
git clone -b porxy --depth 1 --single-branch https://github.com/shiyu1314/openwrt-feeds package/porxy

# The smartdns feed can reference a rust-bindgen/host helper that is not present
# in this source tree. It is only a stale build dependency here, but removing it
# keeps compile logs clean and avoids confusing warnings.
[ -f package/xd/smartdns/Makefile ] && sed -i -E \
  -e 's/[[:space:]]*PACKAGE_smartdns-ui:rust-bindgen\/host//g' \
  -e 's/[[:space:]]*rust-bindgen\/host//g' \
  -e 's/[[:space:]]*PACKAGE_smartdns-ui://g' \
  package/xd/smartdns/Makefile

# daed 1.28.x pulls a large pnpm/turbo frontend and has repeatedly failed in
# GitHub Actions. Install the official OpenWrt 25.12 runfiles at first boot
# instead of compiling the source packages during firmware build.
rm -rf package/porxy/daed package/porxy/luci-app-daed

rm -rf feeds/luci/applications/{luci-app-dockerman,luci-app-samba4,luci-app-aria2,luci-app-diskman}
rm -rf feeds/packages/net/{samba4,sing-box,aria2,ariang,adguardhome}

# drop attendedsysupgrade
sed -i '/luci-app-attendedsysupgrade/d' \
    feeds/luci/collections/luci-nginx/Makefile \
    feeds/luci/collections/luci-ssl-openssl/Makefile \
    feeds/luci/collections/luci-ssl/Makefile \
    feeds/luci/collections/luci/Makefile
    
sed -i 's/+uhttpd /+luci-nginx /g' feeds/luci/collections/luci/Makefile
sed -i 's/+uhttpd-mod-ubus //' feeds/luci/collections/luci/Makefile
sed -i 's/+uhttpd /+luci-nginx /g' feeds/luci/collections/luci-light/Makefile
sed -i "s/+luci /+luci-nginx /g" feeds/luci/collections/luci-ssl-openssl/Makefile
sed -i "s/+luci /+luci-nginx /g" feeds/luci/collections/luci-ssl/Makefile
sed -i 's/+uhttpd +uhttpd-mod-ubus /+luci-nginx /g' feeds/packages/net/wg-installer/Makefile
sed -i '/uhttpd-mod-ubus/d' feeds/luci/collections/luci-light/Makefile
sed -i 's/+luci-nginx \\$/+luci-nginx/' feeds/luci/collections/luci-light/Makefile

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

filogic_mk="target/linux/mediatek/image/filogic.mk"
if ! grep -q "Device/jcg_q30-pro" "$filogic_mk"; then
    awk '
        /define Device\/openwrt_one/ && !inserted {
            print ""
            print "define Build/jcg-q30-pro-sysupgrade-bin"
            print "\tsh $(TOPDIR)/scripts/sysupgrade-tar.sh \\"
            print "\t\t--board $(if $(BOARD_NAME),$(BOARD_NAME),$(DEVICE_NAME)) \\"
            print "\t\t--kernel $@ \\"
            print "\t\t--rootfs $(IMAGE_ROOTFS) \\"
            print "\t\t$@.tar"
            print "\tmv $@.tar $@"
            print "endef"
            print ""
            print "define Device/jcg_q30-pro"
            print "  DEVICE_VENDOR := JCG"
            print "  DEVICE_MODEL := Q30 PRO"
            print "  DEVICE_DTS := mt7981b-jcg-q30-pro"
            print "  DEVICE_DTS_DIR := ../dts"
            print "  UBINIZE_OPTS := -E 5"
            print "  BLOCKSIZE := 128k"
            print "  PAGESIZE := 2048"
            print "  KERNEL_IN_UBI := 1"
            print "  UBOOTENV_IN_UBI := 1"
            print "  IMAGES := sysupgrade.bin sysupgrade.itb"
            print "  KERNEL := kernel-bin | gzip | \\"
            print "\tpad-to 64k"
            print "  IMAGE/sysupgrade.bin := append-kernel | \\"
            print "\tfit gzip $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb | \\"
            print "\tjcg-q30-pro-sysupgrade-bin | append-metadata"
            print "  IMAGE/sysupgrade.itb := append-kernel | \\"
            print "\tfit gzip $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb external-static-with-rootfs | append-metadata"
            print "  DEVICE_PACKAGES :="
            print "  ARTIFACTS := preloader.bin bl31-uboot.fip"
            print "  ARTIFACT/preloader.bin := mt7981-bl2 spim-nand-ddr3"
            print "  ARTIFACT/bl31-uboot.fip := mt7981-bl31-uboot jcg_q30-pro"
            print "endef"
            print "TARGET_DEVICES += jcg_q30-pro"
            print ""
            inserted = 1
        }
        { print }
    ' "$filogic_mk" > "$filogic_mk.tmp"
    mv "$filogic_mk.tmp" "$filogic_mk"
fi

for patch in *.patch; do
    [ -f "$patch" ] || continue

    if [ "$patch" = "005-mediatek-filogic-add-jcg-q30-pro.patch" ]; then
        echo "Skipping $patch: JCG Q30 PRO profile is managed by sh/op.sh"
        continue
    fi
    
    echo "Applying $patch ..."
    patch -p1 --no-backup-if-mismatch < "$patch" || {
        echo "ERROR: Failed to apply $patch"
        exit 1
    }
done


# rust
RUST_VERSION=1.95.0
RUST_HASH=62b67230754da642a264ca0cb9fc08820c54e2ed7b3baba0289876d4cdb48c08
sed -ri "s/(PKG_VERSION:=)[^\"]*/\1$RUST_VERSION/;s/(PKG_HASH:=)[^\"]*/\1$RUST_HASH/" feeds/packages/lang/rust/Makefile

# MosDNS v5
rm -rf package/mosdns
git clone https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns

# GeoData
rm -rf package/v2ray-geodata
git clone https://github.com/sbwml/v2ray-geodata package/v2ray-geodata

# Aurora Theme
rm -rf package/luci-theme-aurora
git clone --depth=1 \
https://github.com/eamonxg/luci-theme-aurora \
package/luci-theme-aurora

# Aurora Config App
rm -rf package/luci-app-aurora-config
git clone --depth=1 \
-b v1.2.0 \
https://github.com/eamonxg/luci-app-aurora-config \
package/luci-app-aurora-config

# fstools
rm -rf package/system/fstools
git clone https://github.com/sbwml/package_system_fstools -b openwrt-25.12 package/system/fstools
# util-linux
rm -rf package/utils/util-linux
git clone https://github.com/sbwml/package_utils_util-linux -b openwrt-25.12 package/utils/util-linux

# nghttp3
rm -rf feeds/packages/libs/nghttp3
git clone https://github.com/sbwml/package_libs_nghttp3 package/libs/nghttp3

# ngtcp2
rm -rf feeds/packages/libs/ngtcp2
git clone https://github.com/sbwml/package_libs_ngtcp2 package/libs/ngtcp2

# curl - fix passwall `time_pretransfer` check
rm -rf feeds/packages/net/curl
git clone https://github.com/sbwml/feeds_packages_net_curl feeds/packages/net/curl

# nginx - latest version
rm -rf feeds/packages/net/nginx
git clone https://github.com/sbwml/feeds_packages_net_nginx feeds/packages/net/nginx -b openwrt-25.12
sed -i 's/procd_set_param stdout 1/procd_set_param stdout 0/g;s/procd_set_param stderr 1/procd_set_param stderr 0/g' feeds/packages/net/nginx/files/nginx.init

# nginx - ubus
sed -i 's/ubus_parallel_req 2/ubus_parallel_req 6/g' feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support
sed -i '/ubus_parallel_req/a\        ubus_script_timeout 300;' feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support

# nginx-util
sed -i '/\/etc\/nginx\/uci.conf.template/d' feeds/packages/net/nginx-util/Makefile

# uwsgi - fix timeout
sed -i '$a cgi-timeout = 600' feeds/packages/net/uwsgi/files-luci-support/luci-*.ini
sed -i '/limit-as/c\limit-as = 5000' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
# disable error log
sed -i "s/procd_set_param stderr 1/procd_set_param stderr 0/g" feeds/packages/net/uwsgi/files/uwsgi.init

# uwsgi - performance
sed -i 's/threads = 1/threads = 2/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i 's/processes = 3/processes = 4/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i 's/cheaper = 1/cheaper = 2/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini

# rpcd - fix timeout
sed -i 's/option timeout 30/option timeout 60/g' package/system/rpcd/files/rpcd.config
sed -i 's#20) \* 1000#60) \* 1000#g' feeds/luci/modules/luci-base/htdocs/luci-static/resources/rpc.js

# luci-compat - remove extra line breaks from description
sed -i '/<br \/>/d' feeds/luci/modules/luci-compat/luasrc/view/cbi/full_valuefooter.htm


#golang 26.x
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang

./scripts/feeds update -a
./scripts/feeds install -a

sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config


sudo rm -rf package/base-files/files/etc/banner

sed -i "s/%D %V %C/%D %V $(TZ=UTC-8 date +%Y.%m.%d)/" package/base-files/files/etc/openwrt_release

sed -i "s/%R/by $OP_author/" package/base-files/files/etc/openwrt_release

date=$(date +"%Y-%m-%d")


echo "                                                    " >> package/base-files/files/etc/banner
echo "  _______                     ________        __" >> package/base-files/files/etc/banner
echo " |       |.-----.-----.-----.|  |  |  |.----.|  |_" >> package/base-files/files/etc/banner
echo " |   -   ||  _  |  -__|     ||  |  |  ||   _||   _|" >> package/base-files/files/etc/banner
echo " |_______||   __|_____|__|__||________||__|  |____|" >> package/base-files/files/etc/banner
echo "          |__|" >> package/base-files/files/etc/banner
echo " -----------------------------------------------------" >> package/base-files/files/etc/banner
echo "         %D ${date} by $OP_author                     " >> package/base-files/files/etc/banner
echo " -----------------------------------------------------" >> package/base-files/files/etc/banner
