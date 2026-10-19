ui_print "****************************************"
ui_print "        App DPI Bypass (nfqws)          "
ui_print "      KernelSU & APatch Selective UI    "
ui_print "****************************************"

# Kalıcı veri dizini oluştur ve varsayılan listeyi kopyala
mkdir -p /data/adb/app-dpi-bypass
if [ ! -f /data/adb/app-dpi-bypass/apps.list ]; then
    ui_print "- Varsayılan apps.list oluşturuluyor..."
    cp "$MODPATH/apps.list" /data/adb/app-dpi-bypass/apps.list
fi

ui_print "- Dosya izinleri ayarlanıyor..."
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/dpi_ctl.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/bin/nfqws" 0 0 0755
set_perm_recursive "$MODPATH/webroot" 0 0 0755 0644

# Eski discord-dpi-bypass kalıntısı varsa temizle
if [ -d "/data/adb/modules/discord-dpi-bypass" ] && [ "$MODPATH" != "/data/adb/modules/discord-dpi-bypass" ]; then
    ui_print "- Eski discord-dpi-bypass modülü temizleniyor..."
    sh /data/adb/modules/discord-dpi-bypass/dpi_ctl.sh stop 2>/dev/null
    rm -rf /data/adb/modules/discord-dpi-bypass
fi

ui_print "- Kurulum tamamlandı!"
ui_print "- KernelSU Manager içindeki WebUI ikonundan uygulamaları seçebilirsiniz."
