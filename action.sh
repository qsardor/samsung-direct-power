#!/system/bin/sh
# action.sh - KernelSU-Next Manager Action Script
# Created by Antigravity & Q.S@RDOR

BASE_DIR="/data/adb/samsung_direct_power"

MODE_FILE="$BASE_DIR/governor.mode"
NODE_FULLCAP="/sys/class/power_supply/battery/batt_full_capacity"
NODE_SLATE="/sys/class/power_supply/battery/batt_slate_mode"
NODE_CUR="/sys/class/power_supply/battery/current_now"
NODE_TEMP="/sys/class/power_supply/battery/temp"
NODE_STATUS="/sys/class/power_supply/battery/status"
NODE_CAP="/sys/class/power_supply/battery/capacity"

echo "================================================="
echo "              Samsung Direct Power               "
echo "        Created by Antigravity & Q.S@RDOR        "
echo "================================================="

# Ensure slate mode is 0
[ "$(cat $NODE_SLATE 2>/dev/null)" != "0" ] && echo 0 > "$NODE_SLATE"

CUR_MODE=$(cat "$MODE_FILE" 2>/dev/null || echo "AUTO")

MODDIR="${0%/*}"
DIRECTPOWER="$MODDIR/system/bin/directpower"
[ ! -x "$DIRECTPOWER" ] && DIRECTPOWER="directpower"

if [ "$CUR_MODE" = "DIRECT_POWER" ]; then
    echo "[*] Action: Switching to Normal Charging..."
    $DIRECTPOWER off
else
    echo "[*] Action: Switching to Direct Power Mode (0W)..."
    $DIRECTPOWER on
fi

sleep 1
CUR=$(cat "$NODE_CUR" 2>/dev/null || echo 0)
TEMP=$(cat "$NODE_TEMP" 2>/dev/null || echo 0)
STATUS=$(cat "$NODE_STATUS" 2>/dev/null || echo "Unknown")
CAP=$(cat "$NODE_CAP" 2>/dev/null || echo "0")
TEMP_C=$((TEMP / 10))
NEW_MODE=$(cat "$MODE_FILE" 2>/dev/null || echo "AUTO")

echo ""
echo "  Governor Mode:  $NEW_MODE"
echo "  Hardware State: $STATUS"
echo "  Battery Level:  $CAP %"
echo "  Current Flow:   $CUR mA"
echo "  Battery Temp:   $TEMP_C °C"
echo "================================================="
