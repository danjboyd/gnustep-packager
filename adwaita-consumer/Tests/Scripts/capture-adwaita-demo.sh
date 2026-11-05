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
OUTPUT=""
PAGE="controls"
TITLE="Adwaita Demo"
CAPTURE_ID="AdwaitaCapture$$"
APPLICATION_ID="org.gnustep.AdwaitaDemo.Capture.$$"

find_window_for_title() {
  local candidate=""

  while read -r candidate; do
    printf '%s\n' "$candidate"
    return 0
  done < <(xwininfo -root -tree | awk -v title="$TITLE" 'index($0, "\"" title "\":") {print $1}')

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
    --output)
      OUTPUT="$2"
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

TITLE="$TITLE [$CAPTURE_ID]"
GDK_BACKEND=x11 python3 "$REPO_DIR/Reference/AdwaitaDemo/adwaita_demo.py" --page "$PAGE" --application-id "$APPLICATION_ID" --window-title "$TITLE" >/tmp/adwaita-demo-capture.log 2>&1 &
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
  echo "could not find AdwaitaDemo window" >&2
  exit 1
fi

sleep 1
import -window "$WIN_ID" "$OUTPUT"

kill "$APP_PID" || true
wait "$APP_PID" || true
