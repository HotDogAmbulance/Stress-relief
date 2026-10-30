#!/bin/bash
# comfort-watcher.sh — launches / quits /Applications/Stress-relief.app
# following the macOS "Background Sounds" accessibility toggle
# (domain com.apple.ComfortSounds, key comfortSoundsEnabled).
#
# Invariant enforced each cycle:  app running  <=>  comfortSoundsEnabled == 1

APP_PATH="/Applications/Stress-relief.app"
APP_ID="devplaceholder.QC6GJDLD.Stress-relief"
PREF_DOMAIN="com.apple.ComfortSounds"
PREF_KEY="comfortSoundsEnabled"
POLL_SECONDS=2
LOG_FILE="$HOME/Library/Logs/stress-relief-watcher.log"

# Test hook: override the state source with a file (MOCK=1 MOCK_FILE=/tmp/state)
MOCK="${MOCK:-0}"
MOCK_FILE="${MOCK_FILE:-/tmp/comfort-sounds-state}"

log() {
  # truncate log if it grows past 200 KB
  if [ -f "$LOG_FILE" ] && [ "$(stat -f %z "$LOG_FILE")" -gt 204800 ]; then
    : > "$LOG_FILE"
  fi
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
}

read_state() {
  if [ "$MOCK" = "1" ]; then
    cat "$MOCK_FILE" 2>/dev/null || echo 0
    return
  fi
  # defaults read prints a numeric value; missing key -> treat as OFF
  v=$(defaults read "$PREF_DOMAIN" "$PREF_KEY" 2>/dev/null)
  if [ "$v" = "1" ]; then echo 1; else echo 0; fi
}

app_running() {
  pgrep -f "$APP_PATH/Contents/MacOS/Stress-relief" > /dev/null 2>&1
}

quit_app() {
  # graceful first, SIGTERM fallback
  osascript -e "tell application id \"$APP_ID\" to quit" > /dev/null 2>&1
  for _ in 1 2 3 4 5; do
    app_running || return 0
    sleep 0.4
  done
  log "WARN graceful quit failed, sending SIGTERM"
  pkill -f "$APP_PATH/Contents/MacOS/Stress-relief" 2>/dev/null
}

launch_app() {
  open -g "$APP_PATH" 2>&1 | while read -r err; do log "open error: $err"; done
}

log "watcher started (pid $$)"
trap 'log "watcher stopped"; exit 0' TERM INT

prev="init"
while true; do
  state=$(read_state)

  if [ "$state" != "$prev" ]; then
    log "state $prev -> $state"
    if [ "$state" = "1" ]; then
      if app_running; then
        log "background-sounds ON: app already running"
      else
        launch_app
        log "background-sounds ON: launched app"
      fi
    else
      if app_running; then
        quit_app
        log "background-sounds OFF: quit app"
      else
        log "background-sounds OFF: app already not running"
      fi
    fi
    prev="$state"
  fi

  sleep "$POLL_SECONDS"
done
