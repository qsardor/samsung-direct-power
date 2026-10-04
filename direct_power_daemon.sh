#!/system/bin/sh
# direct_power_daemon.sh - Intelligent Samsung Direct Power Governor
# Created by Antigravity & Q.S@RDOR

BASE_DIR="/data/adb/samsung_direct_power"
LOG="$BASE_DIR/direct_power.log"
CONF="$BASE_DIR/direct_power.conf"

MODE_FILE="$BASE_DIR/governor.mode"
WHITELIST_FILE="$BASE_DIR/whitelist.json"
PIDFILE="$BASE_DIR/daemon.pid"

NODE_FULLCAP="/sys/class/power_supply/battery/batt_full_capacity"
NODE_SLATE="/sys/class/power_supply/battery/batt_slate_mode"
NODE_STATUS="/sys/class/power_supply/battery/status"
NODE_CUR="/sys/class/power_supply/battery/current_now"
NODE_TEMP="/sys/class/power_supply/battery/temp"
NODE_CAP="/sys/class/power_supply/battery/capacity"

mkdir -p "$BASE_DIR"
echo $$ > "$PIDFILE"

# Max out priority so Android OOM-killer never terminates the governor
echo -1000 > /proc/self/oom_score_adj 2>/dev/null

# Safety: ensure slate mode is ALWAYS 0 so buck converter stays powered
echo 0 > "$NODE_SLATE" 2>/dev/null

# Default configuration
: "${TARGET_SOC:=80}"
: "${TEMP_TRIGGER:=38}"
: "${MIN_BATT_GUARD:=20}"
: "${POLL_INTERVAL:=10}"
: "${GAMING_INTERVAL:=3}"

get_timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

is_physically_plugged() {
    if [ -d "/sys/class/typec/port0-partner" ]; then
        echo 1
        return
    fi
    for s in usb ac wireless max77705-charger; do
        val=$(cat /sys/class/power_supply/$s/online 2>/dev/null)
        if [ "$val" = "1" ] || [ "$val" = "3" ]; then
            echo 1
            return
        fi
    done
    echo 0
}

is_screen_on() {
    # 1. Zero-Binder Fast Path: Linux DRM / KMS DPMS (0.5ms kernel read)
    if [ -f "/sys/class/drm/card0-DSI-1/dpms" ]; then
        if [ "$(cat /sys/class/drm/card0-DSI-1/dpms 2>/dev/null)" = "On" ]; then
            echo 1
            return
        else
            echo 0
            return
        fi
    fi
    # 2. Fallback Path: Android PowerManager dumpsys
    if dumpsys power 2>/dev/null | grep -q 'mWakefulness=Awake'; then
        echo 1
    else
        echo 0
    fi
}

get_focused_package() {
    dumpsys window 2>/dev/null | grep -m1 "mCurrentFocus=" | grep -oE '[a-zA-Z0-9_.]+/[a-zA-Z0-9_.]+' | head -n1 | cut -d'/' -f1
}

is_whitelisted() {
    local cur_pkg="$1"
    [ -z "$cur_pkg" ] && return 1
    [ ! -f "$WHITELIST_FILE" ] && return 1

    # Check if cur_pkg exists in whitelist.json
    grep -q "\"$cur_pkg\"" "$WHITELIST_FILE" 2>/dev/null
}

LAST_LOGGED_STATE=""
log_state_change() {
    local key="$1"
    local msg="$2"
    if [ "$LAST_LOGGED_STATE" != "$key" ]; then
        echo "[$(get_timestamp)] $msg" >> "$LOG"
        LAST_LOGGED_STATE="$key"
        
        # 500-line circular rotation to prevent flash storage bloat
        local lcnt=$(wc -l < "$LOG" 2>/dev/null || echo 0)
        if [ "$lcnt" -gt 500 ]; then
            tail -n 250 "$LOG" > "$BASE_DIR/.log_rotate_tmp" 2>/dev/null && mv -f "$BASE_DIR/.log_rotate_tmp" "$LOG" 2>/dev/null
        fi
    fi
}

set_hardware_direct_power() {
    local target_state="$1" # 1 = ON (Direct Power), 0 = OFF (Normal Charging)
    local cur_fullcap=$(cat "$NODE_FULLCAP" 2>/dev/null || echo 100)

    # Ensure slate mode remains 0 so buck converter never drops out
    [ "$(cat $NODE_SLATE 2>/dev/null)" != "0" ] && echo 0 > "$NODE_SLATE"

    if [ "$target_state" = "1" ]; then
        if [ "$cur_fullcap" -ge 100 ]; then
            echo 50 > "$NODE_FULLCAP"
        fi
    else
        if [ "$cur_fullcap" -lt 100 ]; then
            echo 100 > "$NODE_FULLCAP"
        fi
    fi
}

NOTIFIED_FAST_DISABLED=0

# Governor Main Loop
while true; do
    [ -f "$CONF" ] && . "$CONF"

    MODE=$(cat "$MODE_FILE" 2>/dev/null || echo "AUTO")
    PLUGGED=$(is_physically_plugged)
    BATT_CAP=$(cat "$NODE_CAP" 2>/dev/null || echo 50)
    BATT_TEMP_RAW=$(cat "$NODE_TEMP" 2>/dev/null || echo 300)
    BATT_TEMP=$(( BATT_TEMP_RAW / 10 ))

    # 1. Unplugged State
    if [ "$PLUGGED" = "0" ]; then
        NOTIFIED_FAST_DISABLED=0
        set_hardware_direct_power 0
        if [ "$MODE" = "DIRECT_POWER" ]; then
            echo "NORMAL_CHARGING" > "$MODE_FILE"
            log_state_change "UNPLUGGED_OFF" "[CHARGER] Disconnected -> Direct Power auto-disabled"
        else
            log_state_change "UNPLUGGED" "[CHARGER] Disconnected (Operating on battery)"
        fi
        sleep "$POLL_INTERVAL"
        continue
    fi

    # Samsung Fast Charging Setting Awareness (Informational, non-blocking)
    afc=$(settings get system adaptive_fast_charging 2>/dev/null || echo 1)
    sfc=$(settings get system super_fast_charging 2>/dev/null || echo 1)
    if [ "$afc" = "0" ] || [ "$sfc" = "0" ]; then
        if [ "$NOTIFIED_FAST_DISABLED" != "1" ]; then
            cmd notification post -S bigtext -t "Samsung Direct Power" -c activity "android.intent.action.POWER_USAGE_SUMMARY" sdp_fast_warn "Fast Charging is turned OFF in Samsung Settings. Tap to open Settings and enable Fast Charging." >/dev/null 2>&1
            log_state_change "FAST_OFF" "[SETTINGS] Fast Charging is turned OFF in Samsung Settings"
            NOTIFIED_FAST_DISABLED=1
        fi
    else
        NOTIFIED_FAST_DISABLED=0
    fi

    # 2. User Explicit Modes
    if [ "$MODE" = "DIRECT_POWER" ]; then
        set_hardware_direct_power 1
        log_state_change "MANUAL_DIRECT" "[POWER] Direct Power active (AC to Motherboard)"
        sleep 5
        continue
    elif [ "$MODE" = "NORMAL_CHARGING" ]; then
        set_hardware_direct_power 0
        log_state_change "MANUAL_NORMAL" "[POWER] Normal charging active"
        sleep 5
        continue
    fi

    # 3. Intelligent AUTO Governor
    # Check Screen State: if screen is turned off or standby -> must charge normally!
    SCREEN_ON=$(is_screen_on)
    if [ "$SCREEN_ON" = "0" ]; then
        set_hardware_direct_power 0
        log_state_change "SCREEN_OFF" "[STANDBY] Screen off / locked -> Normal charging active"
        sleep 6  # Low-power standby: saves CPU cycles while ensuring snappy reaction on wakeup
        continue
    fi

    # Low Battery Safety Floor
    if [ "$BATT_CAP" -lt "$MIN_BATT_GUARD" ]; then
        set_hardware_direct_power 0
        log_state_change "SAFETY_GUARD" "[SAFETY] Battery below threshold (${BATT_CAP}% < ${MIN_BATT_GUARD}%), normal charging active"
        sleep "$POLL_INTERVAL"
        continue
    fi

    # Whitelist Pre-Check: if whitelist is empty, skip all window/process inspections completely
    if [ ! -s "$WHITELIST_FILE" ] || [ "$(cat "$WHITELIST_FILE" 2>/dev/null)" = "[]" ]; then
        set_hardware_direct_power 0
        log_state_change "AUTO_IDLE" "[STANDBY] Normal charging (${BATT_CAP}%, ${BATT_TEMP}°C)"
        sleep "$POLL_INTERVAL"
        continue
    fi

    # Process Pre-Filter: Check if ANY whitelisted package is even running in memory (~1ms)
    local any_game_running=0
    for pkg in $(grep -oE '"[^"]+"' "$WHITELIST_FILE" 2>/dev/null | tr -d '"'); do
        if pidof "$pkg" >/dev/null 2>&1; then
            any_game_running=1
            break
        fi
    done

    if [ "$any_game_running" = "0" ]; then
        # None of the whitelisted games are running in RAM -> skip dumpsys window!
        set_hardware_direct_power 0
        log_state_change "AUTO_IDLE" "[STANDBY] Normal charging (${BATT_CAP}%, ${BATT_TEMP}°C)"
        sleep "$POLL_INTERVAL"
        continue
    fi

    # A whitelisted game process is running in RAM -> verify if it is currently in foreground focus
    FOCUSED_APP=$(get_focused_package)

    # Check Whitelist Game / App (Engage Direct Power ONLY when game is actively on screen)
    if is_whitelisted "$FOCUSED_APP"; then
        set_hardware_direct_power 1
        log_state_change "APP_${FOCUSED_APP}" "[GAMING] Game active: $FOCUSED_APP -> Direct Power engaged"
        sleep "$GAMING_INTERVAL"
        continue
    fi

    # Default idle in AUTO: Whitelisted game in RAM is minimized / paused -> Normal Charging
    set_hardware_direct_power 0
    log_state_change "AUTO_IDLE" "[STANDBY] Normal charging (${BATT_CAP}%, ${BATT_TEMP}°C)"
    sleep "$POLL_INTERVAL"
done
