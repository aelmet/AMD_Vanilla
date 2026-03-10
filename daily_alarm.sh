#!/data/data/com.termux/files/usr/bin/bash
# daily_alarm.sh — Progressive early alarm for Termux (Android)
#
# Starts at 4:30 AM, moves 3 minutes earlier each day.
# Uses termux-wake-lock + a simple sleep loop (most reliable on Android).
#
# Setup:
#   1. Install Termux from F-Droid (NOT Play Store)
#   2. Install Termux:API from F-Droid
#   3. In Termux: pkg install termux-api
#   4. Run: bash daily_alarm.sh install
#   5. Keep Termux running (it acquires a wake lock)

STATE_FILE="$HOME/.daily_alarm_state"
PID_FILE="$HOME/.daily_alarm_pid"
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# ── helpers ──────────────────────────────────────────────────────────────────

read_state() {
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE"
    else
        ALARM_HOUR=4
        ALARM_MIN=30
        DAY_NUMBER=1
    fi
}

save_state() {
    cat > "$STATE_FILE" <<EOF
ALARM_HOUR=$ALARM_HOUR
ALARM_MIN=$ALARM_MIN
DAY_NUMBER=$DAY_NUMBER
EOF
}

seconds_until_alarm() {
    local now target diff
    now=$(date +%s)
    target=$(date -d "$(printf '%02d:%02d' "$ALARM_HOUR" "$ALARM_MIN")" +%s 2>/dev/null)
    # If that time already passed today, schedule for tomorrow
    if [ "$target" -le "$now" ]; then
        target=$((target + 86400))
    fi
    diff=$((target - now))
    echo "$diff"
}

stop_background() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        kill "$pid" 2>/dev/null
        rm -f "$PID_FILE"
    fi
}

# ── commands ─────────────────────────────────────────────────────────────────

cmd_install() {
    echo "=== Daily Alarm Installer ==="
    echo ""

    # Stop any existing alarm loop
    stop_background

    # Set initial state
    ALARM_HOUR=4
    ALARM_MIN=30
    DAY_NUMBER=1
    save_state

    # Acquire wake lock so Android doesn't kill Termux
    termux-wake-lock 2>/dev/null

    # Start the background loop
    nohup bash "$SCRIPT_PATH" _loop > "$HOME/.daily_alarm.log" 2>&1 &
    echo $! > "$PID_FILE"

    local wait_secs
    wait_secs=$(seconds_until_alarm)
    local wait_hours=$((wait_secs / 3600))
    local wait_mins=$(( (wait_secs % 3600) / 60 ))

    echo "Alarm set for $(printf '%02d:%02d' $ALARM_HOUR $ALARM_MIN)"
    echo "First alarm in about ${wait_hours}h ${wait_mins}m"
    echo "Each day it will ring 3 minutes earlier."
    echo ""
    echo "IMPORTANT: Keep Termux open (you can switch apps, just don't swipe it away)."
    echo "Also disable battery optimization for Termux in Android Settings."
    echo ""
    echo "Commands:"
    echo "  bash $SCRIPT_PATH status   — show current alarm time"
    echo "  bash $SCRIPT_PATH test     — test alarm sound now"
    echo "  bash $SCRIPT_PATH skip     — skip to next day's time"
    echo "  bash $SCRIPT_PATH reset    — reset back to 04:30"
    echo "  bash $SCRIPT_PATH remove   — remove the alarm"
}

cmd_loop() {
    # Internal: runs in background, sleeps until alarm time, fires, repeats
    while true; do
        read_state
        local wait_secs
        wait_secs=$(seconds_until_alarm)

        echo "[$(date)] Sleeping ${wait_secs}s until $(printf '%02d:%02d' $ALARM_HOUR $ALARM_MIN) (Day $DAY_NUMBER)"

        sleep "$wait_secs"

        # Fire the alarm
        cmd_fire

        # Small delay to avoid double-firing
        sleep 60
    done
}

cmd_fire() {
    read_state

    echo "[$(date)] ALARM! Day $DAY_NUMBER — $(printf '%02d:%02d' $ALARM_HOUR $ALARM_MIN)"

    # Send notification with sound + vibration
    termux-notification \
        --title "WAKE UP!" \
        --content "Day $DAY_NUMBER — It's $(printf '%02d:%02d' $ALARM_HOUR $ALARM_MIN). Time to get up!" \
        --priority max \
        --sound \
        --vibrate 1000,500,1000,500,1000,500,1000 \
        --ongoing \
        --alert-once \
        --id daily_alarm 2>/dev/null

    # Also vibrate separately to be extra annoying
    termux-vibrate -d 2000 2>/dev/null

    # Try to play alarm sound via media player
    termux-media-player play "/data/data/com.termux/files/usr/share/sounds/alarm.ogg" 2>/dev/null

    # Toast popup
    termux-toast -g middle "WAKE UP! Day $DAY_NUMBER" 2>/dev/null

    # Advance: subtract 3 minutes for tomorrow
    ALARM_MIN=$((ALARM_MIN - 3))
    if [ $ALARM_MIN -lt 0 ]; then
        ALARM_MIN=$((ALARM_MIN + 60))
        ALARM_HOUR=$((ALARM_HOUR - 1))
        if [ $ALARM_HOUR -lt 0 ]; then
            ALARM_HOUR=23
        fi
    fi
    DAY_NUMBER=$((DAY_NUMBER + 1))

    save_state
    echo "Next alarm: $(printf '%02d:%02d' $ALARM_HOUR $ALARM_MIN) (Day $DAY_NUMBER)"
}

cmd_test() {
    echo "Testing alarm..."
    termux-notification \
        --title "WAKE UP! (TEST)" \
        --content "This is a test alarm" \
        --priority max \
        --sound \
        --vibrate 1000,500,1000,500,1000 \
        --id daily_alarm 2>/dev/null

    termux-vibrate -d 2000 2>/dev/null
    termux-toast -g middle "Alarm test!" 2>/dev/null
    echo "Did you hear/feel it? If not:"
    echo "  1. Make sure Termux:API is installed from F-Droid"
    echo "  2. Run: termux-setup-storage  (grant permissions)"
    echo "  3. Check notification permissions for Termux:API in Android Settings"
}

cmd_status() {
    read_state

    echo "=== Daily Alarm Status ==="
    echo ""

    # Check if running
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "Status: RUNNING"
    else
        echo "Status: NOT RUNNING (run 'bash $SCRIPT_PATH install' to start)"
    fi

    echo "Day $DAY_NUMBER — Next alarm at $(printf '%02d:%02d' $ALARM_HOUR $ALARM_MIN)"

    local wait_secs
    wait_secs=$(seconds_until_alarm)
    local wait_hours=$((wait_secs / 3600))
    local wait_mins=$(( (wait_secs % 3600) / 60 ))
    echo "Time until alarm: ${wait_hours}h ${wait_mins}m"
    echo ""
    echo "Schedule preview (next 10 days):"
    local h=$ALARM_HOUR
    local m=$ALARM_MIN
    local d=$DAY_NUMBER
    for i in $(seq 0 9); do
        printf "  Day %-3d  %02d:%02d\n" $((d + i)) $h $m
        m=$((m - 3))
        if [ $m -lt 0 ]; then
            m=$((m + 60))
            h=$((h - 1))
            [ $h -lt 0 ] && h=23
        fi
    done
}

cmd_skip() {
    read_state
    ALARM_MIN=$((ALARM_MIN - 3))
    if [ $ALARM_MIN -lt 0 ]; then
        ALARM_MIN=$((ALARM_MIN + 60))
        ALARM_HOUR=$((ALARM_HOUR - 1))
        [ $ALARM_HOUR -lt 0 ] && ALARM_HOUR=23
    fi
    DAY_NUMBER=$((DAY_NUMBER + 1))
    save_state

    # Restart the loop with new time
    stop_background
    nohup bash "$SCRIPT_PATH" _loop > "$HOME/.daily_alarm.log" 2>&1 &
    echo $! > "$PID_FILE"

    echo "Skipped! Next alarm: $(printf '%02d:%02d' $ALARM_HOUR $ALARM_MIN) (Day $DAY_NUMBER)"
}

cmd_reset() {
    ALARM_HOUR=4
    ALARM_MIN=30
    DAY_NUMBER=1
    save_state

    # Restart the loop
    stop_background
    nohup bash "$SCRIPT_PATH" _loop > "$HOME/.daily_alarm.log" 2>&1 &
    echo $! > "$PID_FILE"

    echo "Reset! Alarm set back to 04:30 (Day 1)"
}

cmd_remove() {
    stop_background
    rm -f "$STATE_FILE"
    termux-wake-unlock 2>/dev/null
    termux-notification-remove daily_alarm 2>/dev/null
    echo "Alarm removed and stopped."
}

# ── main ─────────────────────────────────────────────────────────────────────

case "${1:-}" in
    install) cmd_install ;;
    _loop)   cmd_loop ;;
    fire)    cmd_fire ;;
    test)    cmd_test ;;
    status)  cmd_status ;;
    skip)    cmd_skip ;;
    reset)   cmd_reset ;;
    remove)  cmd_remove ;;
    *)
        echo "Usage: bash $0 {install|status|test|skip|reset|remove}"
        echo ""
        echo "Progressive alarm: starts 04:30, moves 3 min earlier each day."
        echo "Requires Termux + Termux:API from F-Droid."
        ;;
esac
