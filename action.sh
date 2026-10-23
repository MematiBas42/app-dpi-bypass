#!/system/bin/sh

case "$0" in
    */*) MODDIR=$(cd "${0%/*}" 2>/dev/null && pwd) ;;
    *)   MODDIR="$PWD" ;;
esac

echo ""
echo "=========================================="
echo "          App DPI Bypass Control"
echo "=========================================="
echo ""

sh "$MODDIR/dpi_ctl.sh" toggle

echo ""
echo "------------------------------------------"
sh "$MODDIR/dpi_ctl.sh" status
echo "=========================================="
echo ""
