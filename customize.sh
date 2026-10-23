ui_print "****************************************"
ui_print "        App DPI Bypass (nfqws)          "
ui_print "      KernelSU & APatch Selective UI    "
ui_print "****************************************"

# Kalıcı veri dizini oluştur ve varsayılan listeyi kopyala
mkdir -p /data/adb/app-dpi-bypass
if [ ! -f /data/adb/app-dpi-bypass/apps.list ]; then
    ui_print "- Creating default apps.list..."
    cp "$MODPATH/apps.list" /data/adb/app-dpi-bypass/apps.list
fi
if [ ! -f /data/adb/app-dpi-bypass/config.conf ]; then
    ui_print "- Creating default config.conf..."
    cp "$MODPATH/config.conf" /data/adb/app-dpi-bypass/config.conf
else
    # Mevcut config varsa eksik DNS parametrelerini ekle
    grep -q "DNS_ENABLED" /data/adb/app-dpi-bypass/config.conf || cat << "EOF" >> /data/adb/app-dpi-bypass/config.conf

# Per-App DoH / DNS Ayarları (Zygisk Entegrasyonu)
DNS_ENABLED="1"
DNS_PRESET="cloudflare"
DNS_UPSTREAM="https://1.1.1.1/dns-query"
EOF
fi
if [ ! -f /data/adb/app-dpi-bypass/custom_profiles.json ]; then
    echo "[]" > /data/adb/app-dpi-bypass/custom_profiles.json
fi

ui_print "- Setting file permissions..."
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/dpi_ctl.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/bin/nfqws" 0 0 0755
[ -f "$MODPATH/bin/doh_forwarder" ] && set_perm "$MODPATH/bin/doh_forwarder" 0 0 0755
[ -f "$MODPATH/zygisk/arm64-v8a.so" ] && set_perm "$MODPATH/zygisk/arm64-v8a.so" 0 0 0755
[ -f "$MODPATH/zygisk/armeabi-v7a.so" ] && set_perm "$MODPATH/zygisk/armeabi-v7a.so" 0 0 0755
set_perm_recursive "$MODPATH/webroot" 0 0 0755 0644

# Eski discord-dpi-bypass kalıntısı varsa temizle
if [ -d "/data/adb/modules/discord-dpi-bypass" ] && [ "$MODPATH" != "/data/adb/modules/discord-dpi-bypass" ]; then
    ui_print "- Cleaning up legacy discord-dpi-bypass module..."
    sh /data/adb/modules/discord-dpi-bypass/dpi_ctl.sh stop 2>/dev/null
    rm -rf /data/adb/modules/discord-dpi-bypass
fi

ui_print "- Installation complete!"
ui_print "- Open WebUI from KernelSU/APatch Manager to select apps."
