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

# Where a context menu opens, GTK 4's and the theme's, in pixels from the
# pointer (plugins-themes-Adwaita#20). GNOME Shell runs as the X11 window
# manager of a private Xvfb display, with its own D-Bus session, scratch
# settings and no gvfs, so the desktop session isn't touched; xdotool
# clicks on that display only. A dark window fills the screen's top left,
# a right click at (300, 200) opens its menu, and the first light pixels
# right of and below the pointer give where each menu's body starts.
#
#   bash Tests/Scripts/measure-context-menu.sh
#
# On 2026-10-06 (GNOME Shell 48.7) both started at (+1, +2): GTK 4's
# GtkTextView menu and, with the theme, QuirkProbe's.

set -u

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROBE="$REPO_DIR/Examples/QuirkProbe/QuirkProbe.app/QuirkProbe"
WORK="$(mktemp -d --suffix=.context-menu)"
PIDS=()

session_pids() {
  local pid
  for pid in $(pgrep -u "$(id -u)"); do
    if { tr '\0' '\n' <"/proc/$pid/environ"; } 2>/dev/null | grep -qxF "XDG_RUNTIME_DIR=$WORK/run"; then
      echo "$pid"
    fi
  done
}
cleanup() {
  for pid in "${PIDS[@]}" $(session_pids); do
    kill "$pid" >/dev/null 2>&1 || true
  done
  sleep 1
  rm -rf --one-file-system "$WORK"
}
trap cleanup EXIT

cat >"$WORK/gtk.py" <<'PY'
import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, Gdk
css = Gtk.CssProvider()
css.load_from_data(b"textview, textview text { background: #202020; color: #202020; }")
def on_activate(app):
    Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), css, 800)
    w = Gtk.ApplicationWindow(application=app, title="ctx")
    w.set_default_size(700, 500)
    w.set_decorated(False)
    w.set_child(Gtk.TextView())
    w.present()
app = Gtk.Application(application_id="org.example.ContextMenuMeasure")
app.connect("activate", on_activate)
app.run([])
PY

for n in $(seq 80 99); do
  [ -e "/tmp/.X$n-lock" ] || break
done
export DISPLAY=":$n"
Xvfb "$DISPLAY" -screen 0 1280x800x24 -nolisten tcp +extension GLX +extension RANDR >/dev/null 2>&1 &
PIDS+=($!)
sleep 1
mkdir -p "$WORK"/{config/glib-2.0/settings,data,cache,state,run,gsdefaults,dbus/services}
# The session's bus can start only the accessibility bus: with the standard
# service directories any client could start gvfs (which mounts the phone,
# this machine's network), Evolution's data servers or the document portal.
[ -e /usr/share/dbus-1/services/org.a11y.Bus.service ] \
  && ln -sf /usr/share/dbus-1/services/org.a11y.Bus.service "$WORK/dbus/services/"
sed "s|<standard_session_servicedirs */>|<servicedir>$WORK/dbus/services</servicedir>|" \
  /usr/share/dbus-1/session.conf >"$WORK/dbus/session.conf"
# GNUstep user defaults of the measurement's own, empty.
grep -v '^GNUSTEP_USER_DEFAULTS_DIR=' "${GNUSTEP_CONFIG_FILE:-/etc/GNUstep/GNUstep.conf}" \
  >"$WORK/GNUstep.conf"
echo "GNUSTEP_USER_DEFAULTS_DIR=$WORK/gsdefaults" >>"$WORK/GNUstep.conf"
chmod 600 "$WORK/GNUstep.conf"
chmod 700 "$WORK/run"
printf "[org/gnome/desktop/background]\npicture-uri=''\ncolor-shading-type='solid'\nprimary-color='#777777'\n" \
  >"$WORK/config/glib-2.0/settings/keyfile"
session() { # command...
  env -i HOME="$HOME" PATH="$PATH" DISPLAY="$DISPLAY" LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}" \
    GNUSTEP_CONFIG_FILE="$WORK/GNUstep.conf" GDK_BACKEND=x11 \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$WORK/no-session-bus" \
    XDG_CONFIG_HOME="$WORK/config" XDG_DATA_HOME="$WORK/data" XDG_CACHE_HOME="$WORK/cache" \
    XDG_STATE_HOME="$WORK/state" XDG_RUNTIME_DIR="$WORK/run" GSETTINGS_BACKEND=keyfile LIBGL_ALWAYS_SOFTWARE=1 \
    GIO_USE_VFS=local GVFS_DISABLE_FUSE=1 GIO_USE_VOLUME_MONITOR=unix "$@"
}
session dbus-run-session --config-file="$WORK/dbus/session.conf" -- gnome-shell --x11 >"$WORK/wm.log" 2>&1 &
PIDS+=($!)
for _ in $(seq 1 60); do
  xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q "window id" && break
  sleep 0.5
done
# GNOME Shell starts in the overview, and a first run shows a welcome
# dialog: close both.
sleep 4; xdotool key Escape; sleep 1; xdotool key Escape; sleep 1

# measure NAME COMMAND...: the menu body's offset from the pointer.
measure() {
  local name=$1 pid
  shift
  session "$@" >"$WORK/$name.log" 2>&1 &
  pid=$!
  sleep 5
  xdotool mousemove 300 200; sleep 0.5; xdotool click 3; sleep 1.5
  import -window root "$WORK/$name.png"
  xdotool key Escape; sleep 0.5
  kill "$pid" >/dev/null 2>&1
  sleep 1
  python3 - "$WORK/$name.png" "$name" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
light = lambda p: min(p) > 200
x = next((x for x in range(300, 400) if light(im.getpixel((x, 260)))), None)
y = next((y for y in range(200, 300) if light(im.getpixel((340, y)))), None)
print("%s: menu body at %s" % (sys.argv[2], "(+%d, +%d) from the pointer" % (x - 300, y - 200) if x and y else "not found"))
PY
}

measure gtk env GDK_BACKEND=x11 python3 "$WORK/gtk.py"
if [ -x "$PROBE" ]; then
  measure gnustep "$PROBE" -GSTheme "$REPO_DIR/Adwaita.theme" -NSMenuInterfaceStyle NSWindows95InterfaceStyle \
    -ProbeOnly context-menu-demo
else
  echo "QuirkProbe not built (make probe)"
fi
