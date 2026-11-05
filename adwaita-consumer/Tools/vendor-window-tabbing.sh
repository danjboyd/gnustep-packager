#!/usr/bin/env bash
# Copyright (C) 2026 Daniel Boyd
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

# Copies the shared window tabbing code (danjboyd/gnustep-window-tabbing)
# into Source/WindowTabbing at a given commit, and records the commit in
# Source/WindowTabbing/VERSION.
#
#   bash Tools/vendor-window-tabbing.sh [CHECKOUT] [COMMIT]
#
# CHECKOUT is a clone of the repository (default ../gnustep-window-tabbing),
# COMMIT what to copy (default its HEAD). The theme builds from the copy,
# so a release (a shallow clone of a tag, or GitHub's tarball) needs
# nothing else; refresh the copy, rebuild and run the checks to move to a
# newer commit.

set -eu

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECKOUT="${1:-$REPO_DIR/../gnustep-window-tabbing}"
COMMIT="${2:-HEAD}"
DEST="$REPO_DIR/Source/WindowTabbing"

COMMIT="$(git -C "$CHECKOUT" rev-parse --verify "$COMMIT^{commit}")"
rm -rf --one-file-system "$DEST"
mkdir -p "$DEST"
git -C "$CHECKOUT" archive "$COMMIT" Headers Source GSWindowTabbing.make LICENSE \
  | tar -x -C "$DEST"
{
  echo "danjboyd/gnustep-window-tabbing $COMMIT"
  echo "Copied by Tools/vendor-window-tabbing.sh; don't edit here: change the"
  echo "shared repository and copy it again."
} >"$DEST/VERSION"
echo "Source/WindowTabbing is gnustep-window-tabbing $COMMIT"
