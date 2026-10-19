#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"
mkdir -p "$DIST_DIR"

ZIP_NAME="app-dpi-bypass-v2.0.0.zip"
TARGET_ZIP="$DIST_DIR/$ZIP_NAME"

rm -f "$TARGET_ZIP"

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
    bin \
    webroot

ln -sf "$ZIP_NAME" "$DIST_DIR/app-dpi-bypass.zip"

echo "Packed: $TARGET_ZIP ($(du -h "$TARGET_ZIP" | cut -f1))"
