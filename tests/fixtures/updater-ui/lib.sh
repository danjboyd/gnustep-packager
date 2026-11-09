# Driver helpers for the updater dialog cases. Sourced by run-cases.sh, which
# runs inside scripts/run-gui-isolated.sh: DISPLAY is private and ~ is scratch.
# GPUI_ROOT is the work directory run-local.sh made (outside the home directory).
U=${GPUI_ROOT:?GPUI_ROOT is not set}
# The GNUstep environment of the shell that started run-local.sh.
[ -n "${GNUSTEP_MAKEFILES:-}" ] && . "$GNUSTEP_MAKEFILES/GNUstep.sh"
OUT=$U/out; mkdir -p $OUT
export GPUI_HELPER=$U/updater/objc/gp-update-helper/gp-update-helper
APP=$U/fixture/UpdaterFixture
alerts() { grep -c '^ALERT' "$GPUI_MARKER" 2>/dev/null || echo 0; }
# wait_alert N: wait until the marker has N alerts, then print the window id of the newest alert panel.
wait_alert() {
  local n=$1 i
  for i in $(seq 1 100); do
    [ "$(alerts)" -ge "$n" ] && break
    sleep 0.2
  done
  [ "$(alerts)" -ge "$n" ] || { echo "TIMEOUT waiting for alert $n" >> "$GPUI_MARKER"; return 1; }
  sleep 0.8
  xwininfo -root -tree > "$OUT/tree-$(basename "$GPUI_MARKER" .marker)-$n.txt"
  xwininfo -root -tree | grep -E '^\s*0x[0-9a-f]+ ' | grep '"Alert": ("UpdaterFixture"' | awk '{print $1}' | tail -1
}
press() { # press WINDOW KEY...
  local w=$1; shift
  local geo; geo=$(xwininfo -id "$w" | awk '/Absolute upper-left X/{x=$NF} /Absolute upper-left Y/{y=$NF} END{print x, y}')
  set -- $geo "$@"; local x=$1 y=$2; shift 2
  xdotool mousemove $((x + 150)) $((y + 30)) click 1; sleep 0.3
  for k in "$@"; do
    case "$k" in
      click:*) local cx=${k#click:}; xdotool mousemove $((x + ${cx%,*})) $((y + ${cx#*,})) click 1 ;;
      *) xdotool key "$k" ;;
    esac
    sleep 0.3
  done
  sleep 0.5
}
shot() { import -window root "$OUT/$1.png" 2>/dev/null; }
launch() { # launch CASE FEED MODE [ENV...]
  local name=$1 feed=$2 mode=$3; shift 3
  export GPUI_MARKER=$OUT/$name.marker GPUI_STATE=$OUT/$name.state
  rm -f "$GPUI_MARKER"
  mkdir -p "$GPUI_STATE"
  env GPUI_CONFIG="$U/feeds/config-$feed.json" GPUI_MODE=$mode "$@" "$APP" > "$OUT/$name.log" 2>&1 &
  APP_PID=$!
}
stop() { kill $APP_PID 2>/dev/null; sleep 0.5; kill -9 $APP_PID 2>/dev/null; wait $APP_PID 2>/dev/null; }
