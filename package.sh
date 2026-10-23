#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"
mkdir -p "$DIST_DIR"

VERSION=$(grep -m1 '^version=' "$SCRIPT_DIR/module.prop" | cut -d= -f2 | tr -d ' \r\n')
ZIP_NAME="app-dpi-bypass-${VERSION}.zip"
TARGET_ZIP="$DIST_DIR/$ZIP_NAME"

rm -f "$DIST_DIR"/*.zip

cd "$SCRIPT_DIR"
zip -r9 "$TARGET_ZIP" \
    META-INF \
    module.prop \
    customize.sh \
    service.sh \
    action.sh \
    uninstall.sh \
    dpi_ctl.sh \
    apps.list \
    config.conf \
    bin \
    zygisk \
    webroot

echo "Packed: $TARGET_ZIP ($(du -h "$TARGET_ZIP" | cut -f1))"
