#!/usr/bin/env bash
# build.sh - Build and package Samsung Direct Power flashable module
# Created by Antigravity & Q.S@RDOR

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$MODULE_DIR"

OUTPUT_NAME="Samsung_Direct_Power.zip"
rm -f "$OUTPUT_NAME" "${OUTPUT_NAME}.sha256"

echo "================================================="
echo "       Building Samsung Direct Power Module      "
echo "        Created by Antigravity & Q.S@RDOR        "
echo "================================================="

# 1. Attempt compiling AppHelper from source if Android SDK + D8 is present
ANDROID_JAR=""
if [ -n "${ANDROID_SDK_ROOT:-}" ] && [ -d "$ANDROID_SDK_ROOT" ]; then
    ANDROID_JAR=$(find "$ANDROID_SDK_ROOT/platforms" -name "android.jar" 2>/dev/null | sort -V | tail -n 1 || true)
elif [ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME" ]; then
    ANDROID_JAR=$(find "$ANDROID_HOME/platforms" -name "android.jar" 2>/dev/null | sort -V | tail -n 1 || true)
fi

D8_BIN=""
if [ -n "${ANDROID_SDK_ROOT:-}" ] && [ -d "$ANDROID_SDK_ROOT" ]; then
    D8_BIN=$(find "$ANDROID_SDK_ROOT/build-tools" -name "d8" 2>/dev/null | sort -V | tail -n 1 || true)
elif [ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME" ]; then
    D8_BIN=$(find "$ANDROID_HOME/build-tools" -name "d8" 2>/dev/null | sort -V | tail -n 1 || true)
fi

if [ -n "$ANDROID_JAR" ] && [ -f "$ANDROID_JAR" ] && [ -n "$D8_BIN" ] && [ -x "$D8_BIN" ] && command -v javac >/dev/null 2>&1; then
    echo "[*] Found Android SDK: compiling src/AppHelper.java -> apphelper.dex..."
    BUILD_TMP=$(mktemp -d)
    if javac -cp "$ANDROID_JAR" -source 8 -target 8 -d "$BUILD_TMP" src/AppHelper.java 2>/dev/null || javac -cp "$ANDROID_JAR" --release 8 -d "$BUILD_TMP" src/AppHelper.java 2>/dev/null; then
        "$D8_BIN" --min-api 26 --output "$BUILD_TMP" "$BUILD_TMP"/*.class
        if [ -f "$BUILD_TMP/classes.dex" ]; then
            cp -f "$BUILD_TMP/classes.dex" apphelper.dex
            echo "[+] apphelper.dex compiled successfully from source."
        fi
    else
        echo "[!] Compilation failed; falling back to precompiled apphelper.dex."
    fi
    rm -rf "$BUILD_TMP"
else
    echo "[*] Android SDK not detected; using precompiled apphelper.dex."
fi

# 2. Enforce standard POSIX execution permissions on scripts
chmod 755 service.sh action.sh customize.sh direct_power_daemon.sh directpower.sh system/bin/directpower META-INF/com/google/android/update-binary 2>/dev/null || true

# 3. Package flashable ZIP
echo "[*] Packaging module files into $OUTPUT_NAME..."
if command -v zip >/dev/null 2>&1; then
    zip -r9 "$OUTPUT_NAME" \
        META-INF \
        action.sh \
        apphelper.dex \
        customize.sh \
        direct_power_daemon.sh \
        directpower.sh \
        module.prop \
        service.sh \
        system \
        webroot \
        LICENSE \
        README.md \
        -x "*.DS_Store*" "*Thumbs.db*" "webroot/icons/*.png"
else
    # Fallback to python zipfile if native zip utility is absent
    PYTHON_BIN="python3"
    if ! command -v python3 >/dev/null 2>&1 || ! python3 -c "import sys" 2>/dev/null; then
        if command -v python >/dev/null 2>&1 && python -c "import sys" 2>/dev/null; then
            PYTHON_BIN="python"
        fi
    fi
    "$PYTHON_BIN" - << 'PYEOF'
import zipfile
import os

output_name = "Samsung_Direct_Power.zip"
include_paths = [
    "META-INF",
    "action.sh",
    "apphelper.dex",
    "customize.sh",
    "direct_power_daemon.sh",
    "directpower.sh",
    "module.prop",
    "service.sh",
    "system",
    "webroot",
    "LICENSE",
    "README.md",
]

with zipfile.ZipFile(output_name, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
    for item in include_paths:
        if os.path.isfile(item):
            zf.write(item, item)
        elif os.path.isdir(item):
            for root, dirs, files in os.walk(item):
                for f in files:
                    if f in [".DS_Store", "Thumbs.db"]:
                        continue
                    full_p = os.path.join(root, f)
                    rel_p = os.path.relpath(full_p, ".").replace("\\", "/")
                    if rel_p.startswith("webroot/icons/") and not rel_p.endswith(".gitkeep"):
                        continue
                    zf.write(full_p, rel_p)

print(f"[+] Fallback python packaging complete: {output_name}")
PYEOF
fi

# 4. Generate SHA256 checksum
if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$OUTPUT_NAME" > "${OUTPUT_NAME}.sha256"
elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$OUTPUT_NAME" > "${OUTPUT_NAME}.sha256"
fi

echo "================================================="
echo "[+] Build complete: $OUTPUT_NAME"
if [ -f "${OUTPUT_NAME}.sha256" ]; then
    cat "${OUTPUT_NAME}.sha256"
fi
echo "================================================="
