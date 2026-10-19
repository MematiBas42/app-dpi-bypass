#!/system/bin/sh
MODDIR="${0%/*}"
sh "$MODDIR/dpi_ctl.sh" stop 2>/dev/null
# apps.list kullanıcının isteği için /data/adb/app-dpi-bypass altında saklanabilir,
# ancak temizlik amacıyla modül kaldırıldığında kuralların kalktığından emin olunur.
