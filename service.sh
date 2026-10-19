#!/system/bin/sh

MODDIR="${0%/*}"

# Cihazın açılışının tamamlanmasını bekle
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 2
done

# Modül devre dışı bırakılmışsa çalıştırma
if [ -f "$MODDIR/disable" ]; then
    exit 0
fi

# Kalıcı konfigürasyon dizinini ve apps.list'i sağla
mkdir -p /data/adb/app-dpi-bypass
if [ ! -f /data/adb/app-dpi-bypass/apps.list ] && [ -f "$MODDIR/apps.list" ]; then
    cp "$MODDIR/apps.list" /data/adb/app-dpi-bypass/apps.list
fi

# DPI bypass başlat
sh "$MODDIR/dpi_ctl.sh" start
