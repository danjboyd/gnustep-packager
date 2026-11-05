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

# QuirkProbe's print dialog checks (-ProbeOnly print-dialog,
# plugins-themes-Adwaita#52) on a private Xvfb display and a private
# session bus: against the stand-in portal (fake-print-portal.py), then
# with no portal, when the panel must be GNUstep's.
#
# The bus has no service directories, so nothing on it can start the real
# xdg-desktop-portal (whose dialog would open on the desktop), and the
# probe prints with GNUstep's LPR bundle (-GSPrinting GSLPR), so nothing
# asks CUPS; the portal path never spools. GNUstep's user defaults are an
# empty scratch directory, and GNOME's settings a scratch keyfile.
#
#   PRINT_CHECK_DISPLAYS="first last" sets the displays to try (220 229);
#   PRINT_CHECK_KEEP=1 keeps the scratch directory (the portal's log and
#   the documents it was given).

set -eu

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_ARG=""
if [ "${1:-}" = "--no-build" ]; then
  BUILD_ARG="--no-build"
fi

WORK="$(mktemp -d --suffix=.print-dialog)"
XVFB=""
cleanup() {
  [ -n "$XVFB" ] && kill "$XVFB" 2>/dev/null || true
  if awk -v w="$WORK" 'index($2, w) == 1 {found = 1} END {exit !found}' /proc/mounts; then
    echo "not deleting $WORK: something is still mounted in it" >&2
    return
  fi
  if [ -n "${PRINT_CHECK_KEEP:-}" ]; then
    echo "kept $WORK" >&2
    return
  fi
  rm -rf --one-file-system "$WORK"
}
trap cleanup EXIT

mkdir -p "$WORK/jobs" "$WORK/defaults" "$WORK/config"
grep -v '^GNUSTEP_USER_DEFAULTS_DIR=' "${GNUSTEP_CONFIG_FILE:-/etc/GNUstep/GNUstep.conf}" >"$WORK/GNUstep.conf"
echo "GNUSTEP_USER_DEFAULTS_DIR=$WORK/defaults" >>"$WORK/GNUstep.conf"
chmod 600 "$WORK/GNUstep.conf"
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

read -r FIRST_DISPLAY LAST_DISPLAY <<<"${PRINT_CHECK_DISPLAYS:-220 229}"
for n in $(seq "$FIRST_DISPLAY" "$LAST_DISPLAY"); do
  [ ! -e "/tmp/.X11-unix/X$n" ] && [ ! -e "/tmp/.X$n-lock" ] && break
done
Xvfb ":$n" -screen 0 1280x800x24 -nolisten tcp >"$WORK/xvfb.log" 2>&1 &
XVFB=$!
for _ in $(seq 1 50); do
  [ -e "/tmp/.X11-unix/X$n" ] && break
  sleep 0.1
done

# Nothing from the desktop's session: its portal, its Wayland display, gvfs.
run_on_private_bus() {
  env -u WAYLAND_DISPLAY -u DBUS_SESSION_BUS_ADDRESS QUIRK_PROBE_PRIVATE_BUS=1 GDK_BACKEND=x11 DISPLAY=":$n" \
    GNUSTEP_CONFIG_FILE="$WORK/GNUstep.conf" \
    GSETTINGS_BACKEND=keyfile XDG_CONFIG_HOME="$WORK/config" \
    GIO_USE_VFS=local GVFS_DISABLE_FUSE=1 GIO_USE_VOLUME_MONITOR=unix GTK_USE_PORTAL=0 \
    dbus-run-session --config-file="$WORK/bus.conf" -- "$@"
}

status=0

# shellcheck disable=SC2016
run_on_private_bus bash -c '
  set -eu
  python3 "$1/Tests/Scripts/fake-print-portal.py" "$2/requests.log" "$2/jobs" >"$2/portal.out" 2>&1 &
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
  QUIRK_PROBE_ARGS="-ProbeOnly print-dialog -ProbePrintLog $2/requests.log -GSPrinting GSLPR" \
    bash "$1/Tests/Scripts/run-quirk-probe.sh" --display "$DISPLAY" $3
' _ "$REPO_DIR" "$WORK" "$BUILD_ARG" || status=1

run_on_private_bus env \
  QUIRK_PROBE_ARGS="-ProbeOnly print-dialog -ProbePrintNoPortal YES -GSPrinting GSLPR" \
  bash "$REPO_DIR/Tests/Scripts/run-quirk-probe.sh" --display ":$n" --no-build || status=1

exit $status
