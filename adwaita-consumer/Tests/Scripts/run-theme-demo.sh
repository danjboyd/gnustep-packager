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
GNUSTEP_SH="/usr/GNUstep/System/Library/Makefiles/GNUstep.sh"

if [ -f "$GNUSTEP_SH" ]; then
  set +u
  # shellcheck disable=SC1090
  . "$GNUSTEP_SH"
  set -u
fi

cd "$REPO_DIR"

make
make demo

# The theme on the command line, for this run only; the user's own
# ThemeDemo defaults are left as they are.
openapp Examples/ThemeDemo/ThemeDemo.app -GSTheme "$THEME" "$@"
