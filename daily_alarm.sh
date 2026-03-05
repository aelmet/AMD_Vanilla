#!/data/data/com.termux/files/usr/bin/bash
# daily_alarm.sh — Progressive early alarm for Termux (Android)
#
# Starts at 4:30 AM, moves 3 minutes earlier each day.
# Requires: Termux + Termux:API (for termux-notification and termux-media-player)
#
# Setup:
#   1. Install Termux from F-Droid
#   2. Install Termux:API from F-Droid
#   3. In Termux: pkg install termux-api cronie
#   4. Run: bash daily_alarm.sh install
#   5. Allow Termux:API permissions when prompted
#
# The alarm fires via cron. Each time it fires, it:
#   - Plays an alarm sound + sends a notification
#   - Recalculates the next day's alarm (3 min earlier)
#   - Updates the crontab

STATE_FILE="$HOME/.daily_alarm_state"
ALARM_SOUND="/data/data/com.termux/files/usr/share/sounds/alarm.ogg"
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

update_cron() {
    # Remove any existing daily_alarm entry, then add the new one
    crontab -l 2>/dev/null | grep -v 'daily_alarm.sh fire' > /tmp/crontab_tmp || true
    echo "$ALARM_MIN $ALARM_HOUR * * * bash $SCRIPT_PATH fire" >> /tmp/crontab_tmp
    crontab /tmp/crontab_tmp
    rm -f /tmp/crontab_tmp
}

# ── commands ─────────────────────────────────────────────────────────────────

cmd_install() {
    echo "Installing daily alarm — starting at 04:30 AM"
    ALARM_HOUR=4
    ALARM_MIN=30
    DAY_NUMBER=1
    save_state
    update_cron

    # Start crond if not running
    crond 2>/dev/null || true

    echo "Done! Alarm set for $(printf '%02d:%02d' $ALARM_HOUR $ALARM_MIN)"
    echo "Each day it will ring 3 minutes earlier."
    echo ""
    echo "Commands:"
    echo "  bash $0 status   — show current alarm time"
    echo "  bash $0 skip     — skip to next day's time"
    echo "  bash $0 reset    — reset back to 04:30"
    echo "  bash $0 remove   — remove the alarm entirely"
}

cmd_fire() {
    read_state

    # Send notification
    termux-notification \
        --title "Wake up!" \
        --content "Day $DAY_NUMBER — Alarm: $(printf '%02d:%02d' $ALARM_HOUR $ALARM_MIN)" \
        --priority high \
        --sound \
        --vibrate 1000,500,1000,500,1000 \
        --id daily_alarm 2>/dev/null

    # Play alarm sound (falls back to vibration if no file)
    if [ -f "$ALARM_SOUND" ]; then
        termux-media-player play "$ALARM_SOUND" 2>/dev/null
    fi

    # Advance to next day: subtract 3 minutes
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
    update_cron

    echo "Alarm fired! Next alarm: $(printf '%02d:%02d' $ALARM_HOUR $ALARM_MIN) (Day $DAY_NUMBER)"
}

cmd_status() {
    read_state
    echo "Day $DAY_NUMBER — Next alarm at $(printf '%02d:%02d' $ALARM_HOUR $ALARM_MIN)"
    echo ""
    echo "Schedule preview (next 10 days):"
    h=$ALARM_HOUR
    m=$ALARM_MIN
    d=$DAY_NUMBER
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
    update_cron
    echo "Skipped! Next alarm: $(printf '%02d:%02d' $ALARM_HOUR $ALARM_MIN) (Day $DAY_NUMBER)"
}

cmd_reset() {
    ALARM_HOUR=4
    ALARM_MIN=30
    DAY_NUMBER=1
    save_state
    update_cron
    echo "Reset! Alarm set back to 04:30 (Day 1)"
}

cmd_remove() {
    crontab -l 2>/dev/null | grep -v 'daily_alarm.sh' | crontab - 2>/dev/null
    rm -f "$STATE_FILE"
    echo "Alarm removed."
}

# ── main ─────────────────────────────────────────────────────────────────────

case "${1:-}" in
    install) cmd_install ;;
    fire)    cmd_fire ;;
    status)  cmd_status ;;
    skip)    cmd_skip ;;
    reset)   cmd_reset ;;
    remove)  cmd_remove ;;
    *)
        echo "Usage: bash $0 {install|status|skip|reset|remove}"
        echo ""
        echo "Progressive alarm: starts 04:30, rings 3 min earlier each day."
        echo "Requires Termux + Termux:API on Android."
        ;;
esac
