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
MENU="demo"
HIGHLIGHT="-1"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --menu)
      MENU="$2"
      shift 2
      ;;
    --highlight)
      HIGHLIGHT="$2"
      shift 2
      ;;
    --output)
      OUTPUT="$2"
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

if [ ! -d "$THEME" ]; then
  echo "theme bundle not found: $THEME (run make first)" >&2
  exit 1
fi
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

APP="$REPO_DIR/Examples/ThemeDemo/ThemeDemo.app/ThemeDemo"
if [ ! -x "$APP" ]; then
  APP="$HOME/GNUstep/Applications/ThemeDemo.app/ThemeDemo"
fi

"$APP" -GSTheme "$THEME" --capture-menu "$MENU" \
       --capture-menu-output "$OUTPUT" \
       --capture-menu-highlight "$HIGHLIGHT"
