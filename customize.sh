#!/system/bin/sh
# customize.sh - KernelSU module installer script
# Created by Antigravity & Q.S@RDOR

ui_print "*************************************************"
ui_print "           Samsung Direct Power v1.0            "
ui_print "       Created by Antigravity & Q.S@RDOR        "
ui_print "*************************************************"

# 1. Bootloop Protection & Hardware Node Check
NODE="/sys/class/power_supply/battery/batt_full_capacity"
if [ ! -f "$NODE" ]; then
    ui_print "! Error: Hardware node batt_full_capacity not found!"
    abort "! Installation aborted to prevent misconfiguration."
fi

ui_print "- Verified hardware node: $NODE"

# 2. Check Type-C Controller
if [ -d "/sys/class/typec/port0" ]; then
    ui_print "- Verified Type-C controller: /sys/class/typec/port0"
fi

# 3. Create persistent runtime directory
BASE_DIR="/data/adb/samsung_direct_power"
mkdir -p "$BASE_DIR"
chmod 755 "$BASE_DIR"

# 4. Install default configuration if not present
if [ ! -f "$BASE_DIR/direct_power.conf" ]; then
    ui_print "- Initializing configuration: $BASE_DIR/direct_power.conf"
    cat << 'EOF' > "$BASE_DIR/direct_power.conf"
# Samsung Direct Power Configuration
# Created by Antigravity & Q.S@RDOR
TARGET_SOC=80
TEMP_TRIGGER=38
MIN_BATT_GUARD=20
POLL_INTERVAL=10
GAMING_INTERVAL=3
EOF
    chmod 644 "$BASE_DIR/direct_power.conf"
fi

# 5. Clean legacy files & initialize whitelist.json
rm -f "$BASE_DIR/games.txt" 2>/dev/null
if [ ! -f "$BASE_DIR/whitelist.json" ]; then
    ui_print "- Initializing clean whitelist: $BASE_DIR/whitelist.json"
    echo "[]" > "$BASE_DIR/whitelist.json"
    chmod 644 "$BASE_DIR/whitelist.json"
fi

# 6. Set executable permissions
set_perm $MODPATH/service.sh 0 0 0755
set_perm $MODPATH/action.sh 0 0 0755
set_perm $MODPATH/direct_power_daemon.sh 0 0 0755
[ -f "$MODPATH/directpower.sh" ] && set_perm $MODPATH/directpower.sh 0 0 0755
set_perm $MODPATH/system/bin/directpower 0 0 0755
[ -d "$MODPATH/webroot" ] && set_perm_recursive $MODPATH/webroot 0 0 0755 0644

# Install binary to KernelSU/APatch bin paths for instant terminal & WebUI access
if [ -d "/data/adb/ksu/bin" ]; then
    cp -f "$MODPATH/system/bin/directpower" /data/adb/ksu/bin/directpower 2>/dev/null
    chmod 755 /data/adb/ksu/bin/directpower 2>/dev/null
fi
if [ -d "/data/adb/ap/bin" ]; then
    cp -f "$MODPATH/system/bin/directpower" /data/adb/ap/bin/directpower 2>/dev/null
    chmod 755 /data/adb/ap/bin/directpower 2>/dev/null
fi

# Clean legacy binaries and terminate old processes
killall -9 bypass_daemon.sh 2>/dev/null
killall -9 direct_power_daemon.sh 2>/dev/null
pkill -9 -f bypass_daemon 2>/dev/null
pkill -9 -f direct_power_daemon 2>/dev/null
rm -f /data/adb/ksu/bin/bypass /data/adb/ap/bin/bypass 2>/dev/null
rm -rf /data/adb/modules/samsung_bypass_charging 2>/dev/null

# Reset hardware registers to normal charging state
echo 100 > /sys/class/power_supply/battery/batt_full_capacity 2>/dev/null
echo 0 > /sys/class/power_supply/battery/batt_slate_mode 2>/dev/null

# Launch clean daemon immediately
if [ -f "$MODPATH/direct_power_daemon.sh" ]; then
    nohup sh "$MODPATH/direct_power_daemon.sh" > /data/adb/samsung_direct_power/daemon.log 2>&1 &
    echo $! > /data/adb/samsung_direct_power/daemon.pid
fi

# Pre-index installed games and extract icons for WebUI
if [ -f "$MODPATH/apphelper.dex" ]; then
    ui_print "- Indexing installed games for WebUI..."
    mkdir -p "$MODPATH/webroot/icons"
    CLASSPATH="$MODPATH/apphelper.dex" app_process "$MODPATH" AppHelper "$MODPATH/webroot" > /dev/null 2>&1
    cmd package list packages -3 2>/dev/null | sort > "$BASE_DIR/.pkg_cache" 2>/dev/null

    # Symlink webroot/whitelist.json to BASE_DIR/whitelist.json
    ln -sf "$BASE_DIR/whitelist.json" "$MODPATH/webroot/whitelist.json" 2>/dev/null
    set_perm_recursive "$MODPATH/webroot" 0 0 0755 0644
fi

ui_print "- Module files extracted."
ui_print "- Daemon started: /data/adb/samsung_direct_power"
ui_print "- WebUI Dashboard enabled in KernelSU-Next Manager."
ui_print "- Action button enabled in KernelSU-Next Manager."
ui_print "- Global CLI tool ready: 'directpower' in terminal."
ui_print "*************************************************"
