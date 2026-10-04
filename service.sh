#!/system/bin/sh
# service.sh - KernelSU late-start service entrypoint
# Created by Antigravity & Q.S@RDOR

MODDIR="${0%/*}"
DAEMON="$MODDIR/direct_power_daemon.sh"
PIDFILE="/data/adb/samsung_direct_power/daemon.pid"

# Safe wait for Android boot completion
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 2
done

# Extra guard sleep for subsystem settling
sleep 3

# Aggressively terminate any legacy or duplicate daemons
pkill -9 -f bypass_daemon 2>/dev/null
pkill -9 -f direct_power_daemon 2>/dev/null
if [ -f "$PIDFILE" ]; then
    OLD_PID=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && [ -d "/proc/$OLD_PID" ]; then
        kill -9 "$OLD_PID" 2>/dev/null
    fi
    rm -f "$PIDFILE"
fi

# Reset hardware registers to normal charging state on boot
echo 100 > /sys/class/power_supply/battery/batt_full_capacity 2>/dev/null
echo 0 > /sys/class/power_supply/battery/batt_slate_mode 2>/dev/null

# Launch daemon in background
if [ -f "$DAEMON" ]; then
    nohup sh "$DAEMON" > /data/adb/samsung_direct_power/daemon.log 2>&1 &
    echo $! > "$PIDFILE"
fi

# Auto-index games in background on boot
BIN="$MODDIR/system/bin/directpower"
if [ -f "$MODDIR/apphelper.dex" ] && [ -x "$BIN" ]; then
    nohup "$BIN" refreshapps >/dev/null 2>&1 &
fi
