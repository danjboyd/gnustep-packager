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

# QuirkProbe's file chooser checks (-ProbeOnly file-chooser,
# plugins-themes-Adwaita#40) on a private Xvfb display and a private
# session bus: against the stand-in portal (fake-file-chooser-portal.py)
# with the window manager's title bar and with the header bar, then with
# no portal, when the panels must be GNUstep's.
#
# The bus has no service directories, so nothing on it can start the real
# xdg-desktop-portal (whose dialogs would open on the desktop).
#
#   bash Tests/Scripts/run-file-chooser-check.sh [--no-build]

set -eu

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_ARG=""
if [ "${1:-}" = "--no-build" ]; then
  BUILD_ARG="--no-build"
fi

WORK="$(mktemp -d --suffix=.file-chooser)"
cleanup() {
  rm -rf --one-file-system "$WORK"
}
trap cleanup EXIT

mkdir -p "$WORK/files/folder"
touch "$WORK/files/a.txt" "$WORK/files/b.txt"
cat >"$WORK/bus.conf" <<CONF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:dir=$WORK</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
CONF

# Nothing from the desktop's session: its portal, its Wayland display, gvfs.
run_on_private_bus() {
  env -u WAYLAND_DISPLAY -u DBUS_SESSION_BUS_ADDRESS QUIRK_PROBE_PRIVATE_BUS=1 \
    GIO_USE_VFS=local GVFS_DISABLE_FUSE=1 GIO_USE_VOLUME_MONITOR=unix GTK_USE_PORTAL=0 \
    dbus-run-session --config-file="$WORK/bus.conf" -- "$@"
}

status=0

# shellcheck disable=SC2016
# With the window manager's title bar, then with the theme's header bar.
for decorations in YES NO; do
run_on_private_bus bash -c '
  set -eu
  python3 "$1/Tests/Scripts/fake-file-chooser-portal.py" "$2/requests.log" "$2/files" >"$2/portal.out" 2>&1 &
  portal=$!
  trap "kill $portal 2>/dev/null || true" EXIT
  for _ in $(seq 1 50); do
    grep -q ready "$2/portal.out" && break
    sleep 0.1
  done
  if ! grep -q ready "$2/portal.out"; then
    echo "stand-in portal did not start:" >&2
    cat "$2/portal.out" >&2
    exit 1
  fi
  QUIRK_PROBE_ARGS="-ProbeOnly file-chooser -ProbeFileChooserLog $2/requests.log -ProbeFileChooserDir $2/files -GSX11HandlesWindowDecorations $4" \
    bash "$1/Tests/Scripts/run-quirk-probe.sh" $3
' _ "$REPO_DIR" "$WORK" "$BUILD_ARG" "$decorations" || status=1
BUILD_ARG="--no-build"
done

run_on_private_bus env \
  QUIRK_PROBE_ARGS="-ProbeOnly file-chooser -ProbeFileChooserNoPortal YES" \
  bash "$REPO_DIR/Tests/Scripts/run-quirk-probe.sh" --no-build || status=1

exit $status
