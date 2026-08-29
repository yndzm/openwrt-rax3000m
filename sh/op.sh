#!/bin/bash

function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
  repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
  cd $repodir && git sparse-checkout set $@
  mv -f $@ ../
  cd .. && rm -rf $repodir
}

set -x

# kenrel Vermagic
sed -ie 's/^\(.\).*vermagic$/\1cp $(TOPDIR)\/.vermagic $(LINUX_DIR)\/.vermagic/' include/kernel-defaults.mk
grep HASH target/linux/generic/kernel-6.12 | awk -F'HASH-' '{print $2}' | awk '{print $1}' | md5sum | awk '{print $1}' > .vermagic

# 拉取第三方综合包源
git clone -b packages --depth 1 --single-branch https://github.com/shiyu1314/openwrt-feeds package/xd
git clone -b porxy --depth 1 --single-branch https://github.com/shiyu1314/openwrt-feeds package/porxy

# 清理 package/xd 和 package/porxy 中的潜在冲突包
rm -rf package/porxy/daed package/porxy/luci-app-daed
rm -rf package/xd/{mosdns,luci-app-mosdns,v2ray-geodata,adguardhome,luci-app-adguardhome,lucky,luci-app-lucky}
rm -rf package/porxy/{mosdns,luci-app-mosdns,v2ray-geodata,adguardhome,luci-app-adguardhome,lucky,luci-app-lucky}

# The smartdns feed can reference a rust-bindgen/host helper that is not present
[ -f package/xd/smartdns/Makefile ] && sed -i -E \
  -e 's/[[:space:]]*PACKAGE_smartdns-ui:rust-bindgen\/host//g' \
  -e 's/[[:space:]]*rust-bindgen\/host//g' \
  -e 's/[[:space:]]*PACKAGE_smartdns-ui://g' \
  package/xd/smartdns/Makefile

# 彻底清理 feeds/luci 与 feeds/packages 内的原生冲突包
rm -rf feeds/luci/applications/{luci-app-dockerman,luci-app-samba4,luci-app-aria2,luci-app-diskman}
rm -rf feeds/packages/net/{samba4,v2ray-geodata,mosdns,sing-box,aria2,ariang,adguardhome}

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

# 彻底清理所有旧版 mosdns 和 v2ray-geodata 软链接及目录（防止旧版本占用）
find feeds/ -type d -name "mosdns" -prune -exec rm -rf {} +
find feeds/ -type d -name "v2ray-geodata" -prune -exec rm -rf {} +
rm -rf package/mosdns package/v2ray-geodata

# MosDNS v5 + GeoData
git clone https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns
git clone https://github.com/sbwml/v2ray-geodata package/v2ray-geodata

# Lucky (只拉取指定分支)
rm -rf package/luci-app-lucky
git clone https://github.com/sirpdboy/luci-app-lucky.git package/luci-app-lucky

# stevenjoezhang 的 AdGuardHome LuCI 界面（清理旧冲突后再拉取）
rm -rf package/luci-app-adguardhome
git clone https://github.com/stevenjoezhang/luci-app-adguardhome.git package/luci-app-adguardhome

# Aurora Theme & Config
rm -rf package/luci-theme-aurora package/luci-app-aurora-config
git clone --depth=1 https://github.com/eamonxg/luci-theme-aurora package/luci-theme-aurora
git clone --depth=1 -b v1.2.0 https://github.com/eamonxg/luci-app-aurora-config package/luci-app-aurora-config

# fstools
rm -rf package/system/fstools
git clone https://github.com/sbwml/package_system_fstools -b openwrt-25.12 package/system/fstools

# util-linux
rm -rf package/utils/util-linux
git clone https://github.com/sbwml/package_utils_util-linux -b openwrt-25.12 package/utils/util-linux

# nghttp3 & ngtcp2
rm -rf feeds/packages/libs/nghttp3 package/libs/nghttp3
git clone https://github.com/sbwml/package_libs_nghttp3 package/libs/nghttp3
rm -rf feeds/packages/libs/ngtcp2 package/libs/ngtcp2
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

# uwsgi - fix timeout & performance
sed -i '$a cgi-timeout = 600' feeds/packages/net/uwsgi/files-luci-support/luci-*.ini
sed -i '/limit-as/c\limit-as = 5000' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i "s/procd_set_param stderr 1/procd_set_param stderr 0/g" feeds/packages/net/uwsgi/files/uwsgi.init
sed -i 's/threads = 1/threads = 2/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i 's/processes = 3/processes = 4/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i 's/cheaper = 1/cheaper = 2/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini

# rpcd - fix timeout
sed -i 's/option timeout 30/option timeout 60/g' package/system/rpcd/files/rpcd.config
sed -i 's#20) \* 1000#60) \* 1000#g' feeds/luci/modules/luci-base/htdocs/luci-static/resources/rpc.js

# luci-compat - remove extra line breaks
sed -i '/<br \/>/d' feeds/luci/modules/luci-compat/luasrc/view/cbi/full_valuefooter.htm

# golang 26.x
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang

# 重载 feeds 索引（关键：先删旧的软链接再安装）
./scripts/feeds update -i
./scripts/feeds install -a

# 确保在安装完 feeds 之后，再次清除非 v5 的残留引用
rm -rf feeds/packages/net/mosdns feeds/packages/net/v2ray-geodata

sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config

# 强制将 WireGuard、MosDNS v5、Lucky 和 ADG LuCI 编译选项注入 .config
cat << 'EOF' >> .config
CONFIG_PACKAGE_luci-app-mosdns=y
CONFIG_PACKAGE_mosdns=y
CONFIG_PACKAGE_v2ray-geodata=y
CONFIG_PACKAGE_luci-app-lucky=y
CONFIG_PACKAGE_lucky=y
CONFIG_PACKAGE_luci-app-adguardhome=y
# CONFIG_PACKAGE_adguardhome is not set
CONFIG_PACKAGE_kmod-wireguard=y
CONFIG_PACKAGE_wireguard-tools=y
CONFIG_PACKAGE_luci-proto-wireguard=y
CONFIG_PACKAGE_luci-app-wireguard=y
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_ca-bundle=y
CONFIG_PACKAGE_ca-certificates=y
CONFIG_PACKAGE_tar=y
CONFIG_PACKAGE_unzip=y
EOF

# Banner and Release branding
rm -rf package/base-files/files/etc/banner
sed -i "s/%D %V %C/%D %V $(TZ=UTC-8 date +%Y.%m.%d)/" package/base-files/files/etc/openwrt_release
sed -i "s/%R/by $OP_author/" package/base-files/files/etc/openwrt_release

date=$(date +"%Y-%m-%d")
cat << EOF >> package/base-files/files/etc/banner
                                                       
 _______                     _______        __        
 |       |.-----.-----.-----.|   |   |.----.|  |_      
 |   -   ||  _  |  -__|     ||   |   ||   _||   _|     
 |_______||   __|_____|__|__||_______||__|  |____|     
          |__|                                         
 ----------------------------------------------------- 
         %D ${date} by $OP_author                     
 ----------------------------------------------------- 
EOF
