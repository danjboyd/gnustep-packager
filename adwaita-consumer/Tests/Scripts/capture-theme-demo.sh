#!/usr/bin/env bash
# Copyright (C) 2025-2026 Daniel Boyd
#
# This file is part of the GNUstep Adwaita theme.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; see the file COPYING.LIB.
# If not, see <http://www.gnu.org/licenses/>.

set -eu

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
# The theme bundle built in this checkout, by absolute path. `-GSTheme Adwaita`
# would load the installed copy (~/GNUstep/Library/Themes), which can be older.
THEME="${ADWAITA_THEME:-$REPO_DIR/Adwaita.theme}"
OUTPUT=""
PAGE="controls"
OPEN_MENU=""
SCALE=""
TITLE="Adwaita Theme Demo"
TMP_ROOT=""
CAPTURE_ID="ThemeDemoCapture$$"
MENU_WINDOW_MIN_AREA=10000

find_window_for_title() {
  local candidate=""

  while read -r candidate; do
    printf '%s\n' "$candidate"
    return 0
  done < <(xwininfo -root -tree | awk -v title="$TITLE" '
    (index($0, "\"" title "\":") && (index($0, "(\"ThemeDemo\" \"GNUstep\")") || index($0, "(\"ThemeDemo\" \"ThemeDemo\")"))) {
        print $1
      }')

  return 1
}

list_theme_demo_menu_windows() {
  xwininfo -root -tree | awk '
    (index($0, "\"Window\":") && (index($0, "(\"ThemeDemo\" \"GNUstep\")") || index($0, "(\"ThemeDemo\" \"ThemeDemo\")"))) {
      id = $1
      if (match($0, /[[:space:]]([0-9]+)x([0-9]+)\+[0-9-]+\+[0-9-]+/, dims)) {
        width = dims[1] + 0
        height = dims[2] + 0
        area = width * height
        printf "%s %d %d %d\n", id, area, width, height
      }
    }'
}

find_popup_window_for_menu() {
  local existing_ids="$1"
  local line=""
  local id=""
  local area=0
  local best_id=""
  local best_area=0

  while read -r line; do
    [ -n "$line" ] || continue
    set -- $line
    id="$1"
    area="$2"

    if [ -n "$existing_ids" ] && printf '%s\n' "$existing_ids" | grep -Fxq "$id"; then
      continue
    fi

    if [ "$area" -gt "$best_area" ]; then
      best_id="$id"
      best_area="$area"
    fi
  done < <(list_theme_demo_menu_windows)

  if [ -n "$best_id" ] && [ "$best_area" -ge "$MENU_WINDOW_MIN_AREA" ]; then
    normalize_window_id "$best_id"
    return 0
  fi

  return 1
}

normalize_window_id() {
  local raw_id="$1"

  if [[ "$raw_id" == 0x* ]]; then
    printf '%s\n' "$raw_id"
  else
    printf '0x%x\n' "$raw_id"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --page)
      PAGE="$2"
      shift 2
      ;;
    --open-menu)
      OPEN_MENU="$2"
      shift 2
      ;;
    --output)
      OUTPUT="$2"
      shift 2
      ;;
    --scale)
      SCALE="$2"
      shift 2
      ;;
    --theme)
      THEME="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$OUTPUT" ]; then
  echo "--output is required" >&2
  exit 2
fi

mkdir -p "$(dirname "$OUTPUT")"

set +u
. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

# A defaults domain of the capture's own, empty: what the desktop's user set
# for ThemeDemo doesn't change the capture, and the capture writes nothing
# into the user's defaults (theme and scale go on the command line).
CAPTURE_DEFAULTS="$(mktemp -d --suffix=.theme-demo-defaults)"
trap 'rm -rf --one-file-system "$CAPTURE_DEFAULTS"' EXIT
grep -v '^GNUSTEP_USER_DEFAULTS_DIR=' "${GNUSTEP_CONFIG_FILE:-/etc/GNUstep/GNUstep.conf}" \
  >"$CAPTURE_DEFAULTS/GNUstep.conf"
mkdir -p "$CAPTURE_DEFAULTS/defaults"
echo "GNUSTEP_USER_DEFAULTS_DIR=$CAPTURE_DEFAULTS/defaults" >>"$CAPTURE_DEFAULTS/GNUstep.conf"
chmod 600 "$CAPTURE_DEFAULTS/GNUstep.conf"
export GNUSTEP_CONFIG_FILE="$CAPTURE_DEFAULTS/GNUstep.conf"
if [ ! -d "$THEME" ]; then
  echo "theme bundle not found: $THEME (run make first)" >&2
  exit 1
fi
DEFAULT_ARGS=(-GSTheme "$THEME")
if [ -n "$SCALE" ]; then
  DEFAULT_ARGS+=(-GSScaleFactor "$SCALE")
fi

# The demo built in this checkout, built now if it isn't yet. The installed
# copy (~/GNUstep/Applications) can be months older, with another layout:
# a capture from it once looked like a scaling bug. THEME_DEMO_APP names
# another build on purpose.
APP="${THEME_DEMO_APP:-$REPO_DIR/Examples/ThemeDemo/ThemeDemo.app/ThemeDemo}"
if [ -z "${THEME_DEMO_APP:-}" ] && [ ! -x "$APP" ]; then
  echo "building ThemeDemo in $REPO_DIR/Examples/ThemeDemo" >&2
  make -s -C "$REPO_DIR/Examples/ThemeDemo" >&2 || { echo "could not build ThemeDemo" >&2; exit 1; }
fi
if [ ! -x "$APP" ]; then
  echo "ThemeDemo not found: $APP" >&2
  exit 1
fi

MENU_IDS_BEFORE=""
if [ -n "$OPEN_MENU" ]; then
  MENU_IDS_BEFORE="$(list_theme_demo_menu_windows | awk '{print $1}')"
fi

TITLE="$TITLE [$CAPTURE_ID]"
APP_ARGS=(--page "$PAGE" --quit-after 20 --window-title "$TITLE")
if [ -n "$OPEN_MENU" ]; then
  APP_ARGS+=(--open-menu "$OPEN_MENU")
fi

"$APP" "${APP_ARGS[@]}" "${DEFAULT_ARGS[@]}" >/tmp/theme-demo-capture.log 2>&1 &
APP_PID=$!

WIN_ID=""
for _ in $(seq 1 40); do
  sleep 0.5
  WIN_ID="$(find_window_for_title || true)"
  if [ -n "$WIN_ID" ]; then
    WIN_ID="$(normalize_window_id "$WIN_ID")"
    break
  fi
done

if [ -z "$WIN_ID" ]; then
  kill "$APP_PID" || true
  wait "$APP_PID" || true
  echo "could not find ThemeDemo window" >&2
  exit 1
fi

sleep 1

if [ -n "$OPEN_MENU" ]; then
  MENU_WIN_ID=""

  for _ in $(seq 1 12); do
    MENU_WIN_ID="$(find_popup_window_for_menu "$MENU_IDS_BEFORE" || true)"
    if [ -n "$MENU_WIN_ID" ]; then
      break
    fi
    sleep 0.25
  done

  if [ -n "$MENU_WIN_ID" ]; then
    import -window "$MENU_WIN_ID" "$OUTPUT"
  else
    TMP_ROOT="$(mktemp --suffix=.png)"
    if import -window root "$TMP_ROOT" 2>/dev/null; then
      eval "$(xwininfo -id "$WIN_ID" | awk '
        /Absolute upper-left X:/ {print "X="$4}
        /Absolute upper-left Y:/ {print "Y="$4}
        /Width:/ {print "W="$2}
        /Height:/ {print "H="$2}
      ')"
      CROP_W=$((W + 160))
      CROP_H=$((H + 260))
      convert "$TMP_ROOT" -crop "${CROP_W}x${CROP_H}+${X}+${Y}" +repage "$OUTPUT"
      rm -f "$TMP_ROOT"
    else
      rm -f "$TMP_ROOT"
      import -window "$WIN_ID" "$OUTPUT"
    fi
  fi
else
  import -window "$WIN_ID" "$OUTPUT"
fi

kill "$APP_PID" || true
for _ in $(seq 1 8); do
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    break
  fi
  sleep 0.25
done
if kill -0 "$APP_PID" 2>/dev/null; then
  kill -9 "$APP_PID" || true
fi
wait "$APP_PID" || true
