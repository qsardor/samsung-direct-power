#!/system/bin/sh
# directpower.sh - Pure Zero-Bloat Standalone Samsung Direct Power CLI
# Created by Antigravity & Q.S@RDOR
# Direct bare-metal hardware register control with 0 dependencies.

NODE_FULLCAP="/sys/class/power_supply/battery/batt_full_capacity"
NODE_SLATE="/sys/class/power_supply/battery/batt_slate_mode"
NODE_CUR="/sys/class/power_supply/battery/current_now"
NODE_VOLT="/sys/class/power_supply/battery/voltage_now"
NODE_TEMP="/sys/class/power_supply/battery/temp"
NODE_STATUS="/sys/class/power_supply/battery/status"
NODE_CAP="/sys/class/power_supply/battery/capacity"

# Root & Hardware Verification
if [ "$(id -u)" != "0" ]; then
    echo "Error: Root access required. Run with 'su -c directpower'" >&2
    exit 1
fi

if [ ! -f "$NODE_FULLCAP" ]; then
    echo "Error: Samsung battery hardware node not found ($NODE_FULLCAP)." >&2
    exit 1
fi

# Ensure MAX77705 buck converter is stable
[ "$(cat $NODE_SLATE 2>/dev/null)" != "0" ] && echo 0 > "$NODE_SLATE" 2>/dev/null

is_plugged() {
    [ -d "/sys/class/typec/port0-partner" ] && echo 1 && return
    for s in usb ac wireless max77705-charger; do
        val=$(cat /sys/class/power_supply/$s/online 2>/dev/null)
        [ "$val" = "1" ] || [ "$val" = "3" ] && echo 1 && return
    done
    echo 0
}

case "$1" in
    on|1|enable)
        if [ "$(is_plugged)" = "0" ]; then
            echo "Error: No charger connected. Direct Power requires external power." >&2
            exit 1
        fi
        echo 50 > "$NODE_FULLCAP"
        echo "[+] Direct Power ENGAGED (0W battery draw, powering motherboard directly)"
        ;;
    off|0|disable)
        echo 100 > "$NODE_FULLCAP"
        echo "[+] Direct Power DISENGAGED (Normal fast charging restored)"
        ;;
    toggle|t)
        cur=$(cat "$NODE_FULLCAP" 2>/dev/null || echo 100)
        if [ "$cur" -lt 100 ]; then
            echo 100 > "$NODE_FULLCAP"
            echo "[+] Direct Power DISENGAGED (Normal fast charging restored)"
        else
            if [ "$(is_plugged)" = "0" ]; then
                echo "Error: No charger connected. Connect charger first." >&2
                exit 1
            fi
            echo 50 > "$NODE_FULLCAP"
            echo "[+] Direct Power ENGAGED (0W battery draw, powering motherboard directly)"
        fi
        ;;
    status|s|"")
        cur_fc=$(cat "$NODE_FULLCAP" 2>/dev/null || echo 100)
        cur_ma=$(cat "$NODE_CUR" 2>/dev/null || echo 0)
        volt_raw=$(cat "$NODE_VOLT" 2>/dev/null || echo 0)
        temp_raw=$(cat "$NODE_TEMP" 2>/dev/null || echo 0)
        cap=$(cat "$NODE_CAP" 2>/dev/null || echo 0)
        st=$(cat "$NODE_STATUS" 2>/dev/null || echo "Unknown")
        plugged=$(is_plugged)
        
        volt_mv=$((volt_raw / 1000))
        [ "$volt_raw" -lt 10000 ] && volt_mv=$volt_raw
        temp_c=$((temp_raw / 10))

        # Human-readable power routing
        if [ "$cur_fc" -lt 100 ] && [ "$plugged" = "1" ]; then
            ROUTE="Direct to SoC (Battery Isolated 0W)"
            STATE="DIRECT_POWER (ACTIVE)"
        else
            ROUTE="Normal Charging (Battery Active)"
            STATE="NORMAL_CHARGING"
        fi

        echo "================================================="
        echo "              Samsung Direct Power               "
        echo "        Created by Antigravity & Q.S@RDOR        "
        echo "================================================="
        echo "  Power Routing:  $ROUTE"
        echo "  Engine State:   $STATE"
        echo "  Hardware State: $st"
        echo "  Battery Level:  $cap %"
        echo "  Current Flow:   $cur_ma mA"
        echo "  Voltage:        $volt_mv mV"
        echo "  Temperature:    $temp_c °C"
        echo "  Charger:        $([ "$plugged" = "1" ] && echo 'Connected' || echo 'Disconnected')"
        echo "================================================="
        ;;
    json|j)
        cur_fc=$(cat "$NODE_FULLCAP" 2>/dev/null || echo 100)
        cur_ma=$(cat "$NODE_CUR" 2>/dev/null || echo 0)
        volt_raw=$(cat "$NODE_VOLT" 2>/dev/null || echo 0)
        temp_raw=$(cat "$NODE_TEMP" 2>/dev/null || echo 0)
        cap=$(cat "$NODE_CAP" 2>/dev/null || echo 0)
        st=$(cat "$NODE_STATUS" 2>/dev/null || echo "Unknown")
        plugged=$(is_plugged)
        volt_mv=$((volt_raw / 1000))
        [ "$volt_raw" -lt 10000 ] && volt_mv=$volt_raw
        temp_c=$((temp_raw / 10))

        [ "$cur_fc" -lt 100 ] && [ "$plugged" = "1" ] && hw_direct="ON" || hw_direct="OFF"

        echo "{\"direct_power\":\"$hw_direct\",\"status\":\"$st\",\"battery_pct\":$cap,\"current_ma\":$cur_ma,\"voltage_mv\":$volt_mv,\"temp_c\":$temp_c,\"plugged\":$plugged}"
        ;;
    *)
        echo "Usage: directpower {on|off|toggle|status|json}"
        exit 1
        ;;
esac
