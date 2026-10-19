#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/package.sh"

ZIP="$SCRIPT_DIR/dist/app-dpi-bypass.zip"
echo "Deploying to phone..."
scp "$ZIP" phone:/sdcard/Download/app-dpi-bypass.zip

ssh phone "
mkdir -p /data/adb/modules/app-dpi-bypass /data/adb/app-dpi-bypass
cd /data/adb/modules/app-dpi-bypass
unzip -o /sdcard/Download/app-dpi-bypass.zip
chmod 755 dpi_ctl.sh action.sh service.sh uninstall.sh bin/nfqws
chmod -R 755 webroot
chmod 644 module.prop apps.list webroot/*
[ -f /data/adb/app-dpi-bypass/apps.list ] || cp apps.list /data/adb/app-dpi-bypass/apps.list
sh /data/adb/modules/app-dpi-bypass/dpi_ctl.sh reload
sh /data/adb/modules/app-dpi-bypass/dpi_ctl.sh status
"

echo "Deploy complete!"
