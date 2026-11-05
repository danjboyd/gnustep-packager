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

# Checks the header bar with Mutter as the window manager: GNOME Shell runs
# as the X11 window manager of a private Xvfb display, with its own D-Bus
# session, settings in a scratch keyfile (a solid grey background, so
# shadows can be measured) and scratch XDG directories, so the desktop
# session isn't touched. ThemeDemo runs with the header bar; xdotool clicks
# on that display only.
#
# The session runs without gvfs (GIO_USE_VFS=local, no FUSE mount, no
# volume monitors, and a bus that can't start them). With gvfs it mounts
# whatever devices are plugged in (a phone, a camera) under its runtime
# directory, and a recursive delete of the scratch directory would reach
# into them. Cleanup also stops every process of the session, unmounts
# anything left, and deletes without crossing into another file system.
#
# Checked: Mutter may move, maximise, minimise and close the window
# (_MOTIF_WM_HINTS, _NET_WM_ALLOWED_ACTIONS); a double-click on the bar has
# Mutter maximise it and a second one restore it to the same frame; a drag
# on the bar, handed to Mutter, takes the window past the screen's left
# edge (GNUstep's own move loop can't); a drag on the right edge, handed
# to Mutter, widens it. A menu bar's menu is a _DROPDOWN_MENU, and the
# window stays the active one while it's open. Last, Alt+F4 closes the
# window through the app, which then quits, rather than Mutter killing it.
#
# --shadow runs against a libs-gui and libs-back that draw GNOME's window
# shadow (phase 2b in Docs/HANDOFF_HEADER_BAR.md): MUTTER_CHECK_GUI is the
# directory holding that libgnustep-gui.so, MUTTER_CHECK_BACK that
# libgnustep-back bundle. GNUstep's user defaults are an empty scratch
# directory, so the theme alone asks for the decorations and the shadow,
# and the backend is linked into a scratch user Library. Also checked: a
# 32-bit window with GNOME's frame extents, a shadow outside the edge and
# rounded corners; a menu with rounded corners (a borderless window with an
# alpha channel); maximised, no margin and square corners; restored, the
# margin back, the shadow drawn and the same frame, the app seeing one
# resize on the maximise and two at most on the restore; the edges resize
# from the band outside the window (not from inside), and a press further
# out in the shadow goes to what is behind.
#
# --wm kwin, --wm xfwm4 or --wm openbox runs the same checks under that
# window manager instead of GNOME Shell (KWin and Xfwm4 with their own
# compositors, Openbox with picom), over a grey desktop window. Openbox
# doesn't list _GTK_FRAME_EXTENTS: its windows are expected to get no
# margin. KWin runs with its screen-corner actions off (they take presses
# near the corner, in any app). Xfwm4's compositor is also stopped and
# started again: the window drops its margin without one and gets it back.
# (plugins-themes-Adwaita#14)
#
# Under each window manager, also: half-screen tiling (Super+Left, or a
# drag to the edge under KWin; Openbox has none) fills the left half of
# the work area, with no margin where the window manager announces the
# tiling (_GTK_EDGE_CONSTRAINTS: Mutter) and with it otherwise, and
# untiling gives the size back; and the window menu, opened by a
# right-click on the bar (the window manager's, or the theme's own under
# Openbox), maximises the window from its Maximize. The screen is
# 1600x1000, so that ThemeDemo (762pt wide at least) fits half of it.
#
# MUTTER_CHECK_DISPLAYS="first last" sets the X displays tried (120 150).
#
# ThemeDemo runs with its menu bar (-GnomeThemeMenuStyle menubar), whatever
# the user's own defaults say: the checks press its titles.
#
#   bash Tests/Scripts/run-mutter-check.sh [--no-build] [--shadow]
#                                          [--wm mutter|kwin|xfwm4|openbox]

set -u

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
THEME="$REPO_DIR/Adwaita.theme"
DEMO="$REPO_DIR/Examples/ThemeDemo/ThemeDemo.app/ThemeDemo"
WORK="$(mktemp -d --suffix=.mutter-check)"
FAILED=0
PIDS=()
BUILD=YES
SHADOW=NO
NAME=mutter

WM=mutter

while [ $# -gt 0 ]; do
  case "$1" in
    --no-build) BUILD=NO ;;
    --shadow) SHADOW=YES ;;
    --wm) WM="$2"; shift ;;
  esac
  shift
done
case "$WM" in
  mutter) WM_TOOLS="gnome-shell" ;;
  kwin) WM_TOOLS="kwin_x11" ;;
  xfwm4) WM_TOOLS="xfwm4" ;;
  openbox) WM_TOOLS="openbox picom" ;;
  *) echo "unknown window manager $WM (mutter, kwin, xfwm4 or openbox)" >&2; exit 1 ;;
esac
NAME="$WM"
[ "$SHADOW" = YES ] && NAME="$WM-shadow"

# The session's processes, found by its runtime directory: dbus-run-session
# leaves the daemons it started running after GNOME Shell exits.
session_pids() {
  local pid
  for pid in $(pgrep -u "$(id -u)"); do
    if { tr '\0' '\n' <"/proc/$pid/environ"; } 2>/dev/null | grep -qxF "XDG_RUNTIME_DIR=$WORK/run"; then
      echo "$pid"
    fi
  done
}

cleanup() {
  local mount
  for pid in "${PIDS[@]}" $(session_pids); do
    kill "$pid" >/dev/null 2>&1 || true
  done
  sleep 1
  for mount in $(awk -v w="$WORK" 'index($2, w) == 1 {print $2}' /proc/mounts); do
    fusermount -u "$mount" >/dev/null 2>&1 || umount "$mount" >/dev/null 2>&1 || true
  done
  if awk -v w="$WORK" 'index($2, w) == 1 {found = 1} END {exit !found}' /proc/mounts; then
    echo "not deleting $WORK: something is still mounted in it" >&2
    return
  fi
  rm -rf --one-file-system "$WORK"
}
trap cleanup EXIT

for tool in Xvfb $WM_TOOLS dbus-run-session xdotool wmctrl xprop xwininfo import convert cc; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "SKIP  $NAME: $tool not installed"
    exit 0
  fi
done
if [ "$SHADOW" = YES ]; then
  if [ ! -e "${MUTTER_CHECK_GUI:-}/libgnustep-gui.so" ] || [ ! -d "${MUTTER_CHECK_BACK:-}" ]; then
    echo "SKIP  $NAME: set MUTTER_CHECK_GUI and MUTTER_CHECK_BACK to a shadow-drawing libs-gui and libs-back"
    exit 0
  fi
fi

set +u
. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

if [ "$BUILD" = YES ]; then
  make -C "$REPO_DIR" >/dev/null 2>&1 && make -C "$REPO_DIR/Examples/ThemeDemo" >/dev/null 2>&1 \
    || { echo "build failed" >&2; exit 1; }
fi

# MUTTER_CHECK_DISPLAYS ("first last") sets the displays to try.
read -r FIRST_DISPLAY LAST_DISPLAY <<<"${MUTTER_CHECK_DISPLAYS:-120 150}"
for n in $(seq "$FIRST_DISPLAY" "$LAST_DISPLAY"); do
  [ ! -e "/tmp/.X11-unix/X$n" ] && [ ! -e "/tmp/.X$n-lock" ] && break
done
export DISPLAY=":$n"
Xvfb "$DISPLAY" -screen 0 1600x1000x24 -nolisten tcp +extension GLX +extension RANDR >/dev/null 2>&1 &
PIDS+=($!)
sleep 1

# A solid background: shadows are measured against it.
BACKGROUND=119
mkdir -p "$WORK"/{config/glib-2.0/settings,data,cache,state,run,gs/glib-2.0/settings}
# KWin's screen corners (Plasma's default top-left one opens the overview)
# take presses near the corner: a maximized window's double-click there
# never reaches it, in any app. Off, as the other window managers have
# none (plugins-themes-Adwaita#14).
printf '[ElectricBorders]\nTopLeft=None\nTopRight=None\nBottomLeft=None\nBottomRight=None\n[Effect-overview]\nBorderActivate=9\n' \
  >"$WORK/config/kwinrc"
chmod 700 "$WORK/run"
cat >"$WORK/config/glib-2.0/settings/keyfile" <<'KEYFILE'
[org/gnome/desktop/background]
picture-uri=''
picture-uri-dark=''
picture-options='none'
color-shading-type='solid'
primary-color='#777777'

[org/gnome/mutter]
attach-modal-dialogs=true
KEYFILE
# The other window managers draw no background: a desktop window of
# the same grey.
cat >"$WORK/desktop.c" <<'DESKTOP'
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <unistd.h>

int
main(void)
{
  Display *d = XOpenDisplay(NULL);
  XSetWindowAttributes a;
  Window w;
  Atom type;
  int s;

  if (d == NULL)
    return 1;
  s = DefaultScreen(d);
  a.background_pixel = 0x777777;
  w = XCreateWindow(d, RootWindow(d, s), 0, 0, DisplayWidth(d, s), DisplayHeight(d, s), 0,
                    CopyFromParent, InputOutput, CopyFromParent, CWBackPixel, &a);
  type = XInternAtom(d, "_NET_WM_WINDOW_TYPE_DESKTOP", False);
  XChangeProperty(d, w, XInternAtom(d, "_NET_WM_WINDOW_TYPE", False), XA_ATOM, 32,
                  PropModeReplace, (unsigned char *)&type, 1);
  XMapWindow(d, w);
  XFlush(d);
  for (;;)
    pause();
}
DESKTOP
case "$WM" in
  mutter) WM_COMMAND="gnome-shell --x11" ;;
  kwin) WM_COMMAND="kwin_x11 --replace" ;;
  xfwm4) WM_COMMAND="xfwm4 --replace --compositor=on" ;;
  openbox) WM_COMMAND="openbox --replace" ;;
esac
session() { # command...
  env -i HOME="$HOME" PATH="$PATH" DISPLAY="$DISPLAY" XDG_CONFIG_HOME="$WORK/config" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$WORK/no-session-bus" \
    XDG_DATA_HOME="$WORK/data" XDG_CACHE_HOME="$WORK/cache" XDG_STATE_HOME="$WORK/state" \
    XDG_RUNTIME_DIR="$WORK/run" GSETTINGS_BACKEND=keyfile LIBGL_ALWAYS_SOFTWARE=1 \
    GIO_USE_VFS=local GVFS_DISABLE_FUSE=1 GIO_USE_VOLUME_MONITOR=unix "$@"
}
if [ "$WM" != mutter ]; then
  cc -o "$WORK/desktop" "$WORK/desktop.c" $(pkg-config --cflags --libs x11) || exit 1
  "$WORK/desktop" &
  PIDS+=($!)
fi
# The session's bus can start only these services. With the standard
# service directories any client could start gvfs and its volume monitors
# (the phone, which is this machine's network, among them), Evolution's
# data servers or the document portal's FUSE mount, and did:
# GIO_USE_VFS and friends only stop clients that read them.
mkdir -p "$WORK/dbus/services"
for svc in org.a11y.Bus org.xfce.Xfconf; do
  [ -e "/usr/share/dbus-1/services/$svc.service" ] \
    && ln -sf "/usr/share/dbus-1/services/$svc.service" "$WORK/dbus/services/"
done
sed "s|<standard_session_servicedirs */>|<servicedir>$WORK/dbus/services</servicedir>|" \
  /usr/share/dbus-1/session.conf >"$WORK/dbus/session.conf"
# shellcheck disable=SC2086
session dbus-run-session --config-file="$WORK/dbus/session.conf" -- $WM_COMMAND >"$WORK/wm.log" 2>&1 &
PIDS+=($!)
for _ in $(seq 1 60); do
  xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q "window id" && break
  sleep 0.5
done
sleep 4
if [ "$WM" = mutter ]; then
  # GNOME Shell starts in the overview, and a first run shows a welcome
  # dialog: close both.
  xdotool key Escape; sleep 1; xdotool key Escape; sleep 1
elif [ "$WM" = openbox ]; then
  # Openbox has no compositor of its own.
  session picom --backend xrender >"$WORK/picom.log" 2>&1 &
  PIDS+=($!)
  sleep 2
fi

cat >"$WORK/gs/glib-2.0/settings/keyfile" <<'KEYFILE'
[org/gnome/desktop/interface]
color-scheme='default'
font-name='Cantarell 11'

[org/gnome/desktop/wm/preferences]
button-layout='appmenu:minimize,maximize,close'
action-double-click-titlebar='toggle-maximize'
KEYFILE
# ThemeDemo reads commands from here (the alert check).
mkfifo "$WORK/commands"
# ThemeDemo gets empty GNUstep user defaults of its own, whatever the
# desktop's user set, and nothing it saves reaches the user's defaults.
# Nothing from the desktop's session either: not its Wayland display, and
# not its session bus (an address that leads nowhere, as GLib would
# otherwise find the user bus through XDG_RUNTIME_DIR).
mkdir -p "$WORK/gsdefaults" "$WORK/gsrun"
chmod 700 "$WORK/gsrun"
DEMO_ENV=(env -u WAYLAND_DISPLAY GDK_BACKEND=x11 GNUSTEP_CONFIG_FILE="$WORK/GNUstep.conf"
          XDG_RUNTIME_DIR="$WORK/gsrun" DBUS_SESSION_BUS_ADDRESS="unix:path=$WORK/no-session-bus"
          GSETTINGS_BACKEND=keyfile XDG_CONFIG_HOME="$WORK/gs")
if [ "$SHADOW" = YES ]; then
  # The theme alone asks for the decorations, and a user Library in the
  # scratch directory holds the backend.
  mkdir -p "$WORK/gslibrary/Bundles"
  ln -s "$MUTTER_CHECK_BACK" "$WORK/gslibrary/Bundles/libgnustep-backshadow-032.bundle"
  grep -v -e '^GNUSTEP_USER_DEFAULTS_DIR=' -e '^GNUSTEP_USER_DIR_LIBRARY=' \
    "${GNUSTEP_CONFIG_FILE:-/etc/GNUstep/GNUstep.conf}" >"$WORK/GNUstep.conf"
  printf 'GNUSTEP_USER_DEFAULTS_DIR=%s\nGNUSTEP_USER_DIR_LIBRARY=%s\n' \
    "$WORK/gsdefaults" "$WORK/gslibrary" >>"$WORK/GNUstep.conf"
  chmod 600 "$WORK/GNUstep.conf"
  "${DEMO_ENV[@]}" LD_LIBRARY_PATH="$MUTTER_CHECK_GUI:${LD_LIBRARY_PATH:-}" \
    "$DEMO" -GSTheme "$THEME" -GSBackend libgnustep-backshadow -ThemeDemoLogFrames YES \
    -ThemeDemoCommandFIFO "$WORK/commands" >"$WORK/demo.log" 2>&1 &
else
  grep -v '^GNUSTEP_USER_DEFAULTS_DIR=' "${GNUSTEP_CONFIG_FILE:-/etc/GNUstep/GNUstep.conf}" \
    >"$WORK/GNUstep.conf"
  echo "GNUSTEP_USER_DEFAULTS_DIR=$WORK/gsdefaults" >>"$WORK/GNUstep.conf"
  chmod 600 "$WORK/GNUstep.conf"
  # The theme's header bar and the menu bar, whatever the defaults say
  # (the checks below press its titles).
  "${DEMO_ENV[@]}" \
    "$DEMO" -GSTheme "$THEME" -GSX11HandlesWindowDecorations NO -ThemeDemoLogFrames YES \
    -GnomeThemeMenuStyle menubar -NSMenuInterfaceStyle NSWindows95InterfaceStyle \
    -ThemeDemoCommandFIFO "$WORK/commands" \
    >"$WORK/demo.log" 2>&1 &
fi
DEMO_PID=$!
PIDS+=($DEMO_PID)

WINDOW=""
for _ in $(seq 1 40); do
  WINDOW="$(xdotool search --name "Adwaita Theme Demo" 2>/dev/null | head -1)"
  [ -n "$WINDOW" ] && break
  sleep 0.5
done
if [ -z "$WINDOW" ]; then
  echo "FAIL  $NAME-setup: ThemeDemo's window didn't appear"
  exit 1
fi
sleep 2

report() { # status ident detail
  printf '%-5s %s: %s\n' "$1" "$2" "$3"
  [ "$1" = FAIL ] && FAILED=$((FAILED + 1))
  return 0
}

if [ "$SHADOW" = YES ]; then
  if ! grep -q "$MUTTER_CHECK_BACK" "/proc/$DEMO_PID/maps" 2>/dev/null \
    || ! grep -q "$MUTTER_CHECK_GUI/libgnustep-gui" "/proc/$DEMO_PID/maps" 2>/dev/null; then
    report FAIL "$NAME-setup" "ThemeDemo didn't load the libraries given"
    echo "SUMMARY $NAME failed=$FAILED"
    exit "$FAILED"
  fi
fi

# A shadow margin is expected with the shadow-drawing libraries when the
# window manager lists _GTK_FRAME_EXTENTS (Mutter, KWin, Xfwm4; not
# Openbox). Each runs a compositing manager here.
# Without --shadow it is whatever the installed libraries do (a system
# with the patched libs-back gives the window a margin too).
MARGIN=NO
if xprop -root _NET_SUPPORTED | grep -q _GTK_FRAME_EXTENTS \
  && { [ "$SHADOW" = YES ] || xprop -id "$WINDOW" _GTK_FRAME_EXTENTS 2>/dev/null | grep -q '='; }; then
  MARGIN=YES
fi

geometry() {
  xdotool getwindowgeometry "$WINDOW" | awk '/Position/ {p=$2} /Geometry/ {g=$2} END {print p, g}'
}

# The shadow margin (left right top bottom), 0 0 0 0 without one.
extents() {
  local e
  e="$(xprop -id "$WINDOW" _GTK_FRAME_EXTENTS 2>/dev/null | sed -n 's/.*= //p' | tr -d ,)"
  echo "${e:-0 0 0 0}"
}

# The visible window: the X window less the shadow margin.
visible() {
  local l r t b
  read -r l r t b <<<"$(extents)"
  eval "$(xdotool getwindowgeometry --shell "$WINDOW")"
  echo "$((X + l)) $((Y + t)) $((WIDTH - l - r)) $((HEIGHT - t - b))"
}

# A point on the header bar, clear of the title and buttons.
bar_point() {
  local vx vy vw vh
  read -r vx vy vw vh <<<"$(visible)"
  echo "$((vx + 30)) $((vy + 20))"
}

# Red + green + blue of a screen pixel.
pixel() { # x y
  import -window root "$WORK/screen.png" 2>/dev/null
  convert "$WORK/screen.png" -format "%[fx:round(255*(p{$1,$2}.r+p{$1,$2}.g+p{$1,$2}.b))]" info:
}

# The window under a screen point.
window_at() { # x y
  xdotool mousemove "$1" "$2"; sleep 0.3
  xdotool getmouselocation --shell | sed -n 's/^WINDOW=//p'
}

# Drags from a point by (dx, dy) in eight steps.
drag() { # x y dx dy
  xdotool mousemove "$1" "$2"; sleep 0.3; xdotool mousedown 1; sleep 0.2
  for _ in $(seq 1 8); do xdotool mousemove_relative -- "$3" "$4"; sleep 0.03; done
  sleep 0.3; xdotool mouseup 1; sleep 1
}

ACTIONS="$(xprop -id "$WINDOW" _NET_WM_ALLOWED_ACTIONS)"
if echo "$ACTIONS" | grep -q _NET_WM_ACTION_MOVE && echo "$ACTIONS" | grep -q _NET_WM_ACTION_MAXIMIZE_VERT \
  && echo "$ACTIONS" | grep -q _NET_WM_ACTION_CLOSE; then
  report PASS "$NAME-allowed-actions" "move, maximise and close allowed"
else
  report FAIL "$NAME-allowed-actions" "$ACTIONS"
fi

if [ "$MARGIN" = YES ]; then
  DEPTH="$(xwininfo -id "$WINDOW" | awk '/Depth:/ {print $2}')"
  EXTENTS="$(extents)"
  if [ "$DEPTH" = 32 ] && [ "$EXTENTS" = "30 30 24 36" ]; then
    report PASS "$NAME-window" "depth $DEPTH, frame extents $EXTENTS"
  else
    report FAIL "$NAME-window" "depth $DEPTH, frame extents $EXTENTS (want 32, 30 30 24 36)"
  fi

  # Darker than the background just outside the right edge, the
  # background past the margin; the top left corner rounded off, the top
  # edge further along the window's.
  read -r VX VY VW VH <<<"$(visible)"
  NEAR="$(pixel $((VX + VW + 3)) $((VY + VH / 2)))"
  FAR="$(pixel $((VX + VW + 40)) $((VY + VH / 2)))"
  CORNER="$(pixel "$VX" "$VY")"
  EDGE="$(pixel $((VX + 40)) "$VY")"
  DETAIL="r+g+b 3px out $NEAR, 40px out $FAR (background $((3 * BACKGROUND))); top left corner $CORNER, top edge $EDGE"
  if [ "$NEAR" -le $((FAR - 20)) ] && [ "$FAR" -ge $((3 * BACKGROUND - 6)) ] && [ "$FAR" -le $((3 * BACKGROUND + 6)) ] \
    && [ "$CORNER" -le 600 ] && [ "$EDGE" -ge 700 ]; then
    report PASS "$NAME-shadow-corners" "$DETAIL"
  else
    report FAIL "$NAME-shadow-corners" "$DETAIL"
  fi
elif [ "$SHADOW" = YES ]; then
  # A window manager that doesn't list _GTK_FRAME_EXTENTS: no margin, the
  # window manager's own frame rectangle.
  EXTENTS="$(extents)"
  if [ "$EXTENTS" = "0 0 0 0" ]; then
    report PASS "$NAME-window" "no shadow margin ($WM doesn't list _GTK_FRAME_EXTENTS)"
  else
    report FAIL "$NAME-window" "frame extents $EXTENTS (want none: $WM doesn't list _GTK_FRAME_EXTENTS)"
  fi
fi

# A menu bar's menu is typed as GtkMenuBar's (_DROPDOWN_MENU, by the
# theme), so the window manager doesn't focus it: the window stays
# the active one while it's open. Opened by a press held down: with
# libs-gui 0.32 a click from xdotool, released at once, closes it again.
# The app's first press (here, on an empty spot) activates it.
read -r VX VY VW VH <<<"$(visible)"
xdotool mousemove $((VX + VW - 40)) $((VY + VH - 40)) click 1
sleep 0.5
xdotool mousemove $((VX + 30)) $((VY + 64)) mousedown 1
sleep 1
MENU=""
for w in $(xdotool search --onlyvisible --class ThemeDemo 2>/dev/null); do
  if [ "$w" != "$WINDOW" ]; then
    MENU="$w"
  fi
done
TYPE="$( [ -n "$MENU" ] && xprop -id "$MENU" _NET_WM_WINDOW_TYPE | sed -n 's/.*= //p')"
ACTIVE="$(xprop -root _NET_ACTIVE_WINDOW | sed -n 's/.*# //p' | cut -d, -f1)"
xdotool mouseup 1
sleep 0.5
xdotool key Escape
sleep 0.8
# A window manager that doesn't list the type (Openbox) keeps libs-back's.
if xprop -root _NET_SUPPORTED | grep -q _NET_WM_WINDOW_TYPE_DROPDOWN_MENU; then
  WANTED=_NET_WM_WINDOW_TYPE_DROPDOWN_MENU
else
  WANTED=_NET_WM_WINDOW_TYPE_MENU
fi
DETAIL="menu window ${MENU:-none}: ${TYPE:-no type}; active window ${ACTIVE:-none}"
if [ "${TYPE%%,*}" = "$WANTED" ] && [ "$((ACTIVE))" = "$WINDOW" ]; then
  report PASS "$NAME-menu-type" "$DETAIL"
else
  report FAIL "$NAME-menu-type" "$DETAIL (want $WANTED, ThemeDemo $(printf 0x%x "$WINDOW") active)"
fi

if [ "$SHADOW" = YES ]; then
  # A menu: a borderless window with an alpha channel and, from the
  # patched libs-back (GSBackPopoverShadows), libadwaita's popover shadow
  # in a transparent margin round it (_GTK_FRAME_EXTENTS 14 14 12 16): the
  # window's content just below the menu is darker than once it has closed.
  # (plugins-themes-Adwaita#19)
  read -r VX VY VW VH <<<"$(visible)"
  xdotool mousemove $((VX + 30)) $((VY + 64)) click 1
  sleep 1
  MENU=""
  for w in $(xdotool search --onlyvisible --class ThemeDemo 2>/dev/null); do
    if [ "$w" != "$WINDOW" ] && xwininfo -id "$w" | grep -q 'Depth: 32'; then
      MENU="$w"
    fi
  done
  if [ -n "$MENU" ]; then
    MENU_EXTENTS="$(xprop -id "$MENU" _GTK_FRAME_EXTENTS 2>/dev/null | sed -n 's/.*= //p' | tr -d ,)"
    read -r ML MR MT MB <<<"${MENU_EXTENTS:-0 0 0 0}"
    eval "$(xwininfo -id "$MENU" | awk '/Absolute upper-left X/ {print "MX=" $NF} /Absolute upper-left Y/ {print "MY=" $NF} /Width:/ {print "MW=" $NF} /Height:/ {print "MH=" $NF}')"
    BOTTOM=$((MY + MH - MB))
    MID=$((MX + ML + (MW - ML - MR) / 2))
    INSIDE="$(pixel "$MID" $((BOTTOM - 8)))"
    NEAR="$(pixel "$MID" $((BOTTOM + 2)))"
  fi
  xdotool key Escape
  sleep 0.8
  [ -n "$MENU" ] && BEHIND="$(pixel "$MID" $((BOTTOM + 2)))"
  DETAIL="menu window ${MENU:-none} (32-bit), frame extents ${MENU_EXTENTS:-none}; r+g+b inside ${INSIDE:-?}, 2px below ${NEAR:-?}, there without the menu ${BEHIND:-?}"
  # A window manager without _GTK_FRAME_EXTENTS (Openbox): no margin, no
  # shadow; still rounded.
  if [ -n "$MENU" ] && [ "$INSIDE" -ge 700 ] \
    && { { [ "$MARGIN" = YES ] && [ "$MENU_EXTENTS" = "14 14 12 16" ] && [ "$NEAR" -le $((BEHIND - 15)) ]; } \
         || { [ "$MARGIN" = NO ] && [ -z "$MENU_EXTENTS" ]; }; }; then
    report PASS "$NAME-menu-shadow" "$DETAIL"
  else
    report FAIL "$NAME-menu-shadow" "$DETAIL"
  fi
fi

# A tool tip over the desktop: with an alpha channel (a 32-bit window, under
# a compositor; the installed 0.32 backend gives tool tips one too)
# libadwaita's 80% black, the grey behind it showing through; opaque
# without (#323232, which 80% black makes over the window background).
# (plugins-themes-Adwaita#21)
read -r VX VY VW VH <<<"$(visible)"
echo "tooltip $((VX + VW + 60)) $((VY + 100))" >"$WORK/commands"
sleep 1.5
TIP=""
for w in $(xdotool search --onlyvisible --class ThemeDemo 2>/dev/null); do
  if xprop -id "$w" _NET_WM_WINDOW_TYPE 2>/dev/null | grep -q _NET_WM_WINDOW_TYPE_TOOLTIP; then
    TIP="$w"
  fi
done
if [ -n "$TIP" ]; then
  eval "$(xwininfo -id "$TIP" | awk '/Absolute upper-left X/ {print "TX=" $NF} /Absolute upper-left Y/ {print "TY=" $NF} /Height:/ {print "TH=" $NF}')"
  INSIDE="$(pixel $((TX + 4)) $((TY + TH / 2)))"
  TIP_DEPTH="$(xwininfo -id "$TIP" | awk '/Depth:/ {print $2}')"
fi
echo tooltip-hide >"$WORK/commands"
sleep 0.5
DETAIL="tool tip ${TIP:-none}, depth ${TIP_DEPTH:-?}, over the desktop (r+g+b $((3 * BACKGROUND))): r+g+b ${INSIDE:-?} inside"
if [ "${TIP_DEPTH:-}" = 32 ]; then
  WANT_LOW=$((3 * BACKGROUND / 5 - 15)); WANT_HIGH=$((3 * BACKGROUND / 5 + 15))
else
  WANT_LOW=140; WANT_HIGH=160
fi
if [ -n "$TIP" ] && [ "$INSIDE" -ge "$WANT_LOW" ] && [ "$INSIDE" -le "$WANT_HIGH" ]; then
  report PASS "$NAME-tooltip" "$DETAIL"
else
  report FAIL "$NAME-tooltip" "$DETAIL (want $WANT_LOW-$WANT_HIGH)"
fi

BEFORE="$(geometry)"
RESIZES_BEFORE="$(grep -c '^ThemeDemo-resize' "$WORK/demo.log")"
read -r PX PY <<<"$(bar_point)"
xdotool mousemove "$PX" "$PY" click --repeat 2 --delay 120 1
sleep 1.5
STATE="$(xprop -id "$WINDOW" _NET_WM_STATE)"
MAXIMISED="$(geometry)"
RESIZES_MAXIMISED="$(grep -c '^ThemeDemo-resize' "$WORK/demo.log")"
if echo "$STATE" | grep -q MAXIMIZED_VERT && echo "$STATE" | grep -q MAXIMIZED_HORZ; then
  report PASS "$NAME-maximise" "$BEFORE -> $MAXIMISED, maximised by $WM"
else
  report FAIL "$NAME-maximise" "$BEFORE -> $MAXIMISED; $STATE"
fi

if [ "$MARGIN" = YES ]; then
  # No margin and square corners, as libadwaita's.
  EXTENTS="$(extents)"
  read -r VX VY VW VH <<<"$(visible)"
  CORNER="$(pixel "$VX" "$VY")"
  if [ "$EXTENTS" = "0 0 0 0" ] && [ "$CORNER" -ge 700 ]; then
    report PASS "$NAME-maximised-flat" "frame extents $EXTENTS, top left corner r+g+b $CORNER"
  else
    report FAIL "$NAME-maximised-flat" "frame extents $EXTENTS, top left corner r+g+b $CORNER"
  fi
fi

read -r PX PY <<<"$(bar_point)"
xdotool mousemove "$PX" "$PY" click --repeat 2 --delay 120 1
sleep 1.5
STATE="$(xprop -id "$WINDOW" _NET_WM_STATE)"
AFTER="$(geometry)"
EXTENTS="$(extents)"
if ! echo "$STATE" | grep -q MAXIMIZED && [ "$AFTER" = "$BEFORE" ] \
  && { [ "$MARGIN" = NO ] || [ "$EXTENTS" = "30 30 24 36" ]; }; then
  report PASS "$NAME-restore" "back to $AFTER, frame extents $EXTENTS"
else
  report FAIL "$NAME-restore" "$AFTER (was $BEFORE), frame extents $EXTENTS; $STATE"
fi

if [ "$MARGIN" = YES ]; then
  # The margin goes and comes back as Mutter fits the window, which it
  # configures for the old margin first: on a maximise the app should see
  # one resize, to the frame the window ends with, not three. On a restore
  # Mutter configures the restored size before the margin comes back, so
  # the app sees that and then the margin (its buffers follow the X
  # window): two at most.
  RESIZES_AFTER="$(grep -c '^ThemeDemo-resize' "$WORK/demo.log")"
  SEEN="$(grep '^ThemeDemo-resize' "$WORK/demo.log" | tail -n +$((RESIZES_BEFORE + 1)) | cut -d' ' -f2- | paste -sd';')"
  ON_MAXIMISE=$((RESIZES_MAXIMISED - RESIZES_BEFORE))
  ON_RESTORE=$((RESIZES_AFTER - RESIZES_MAXIMISED))
  if [ "$ON_MAXIMISE" -eq 1 ] && [ "$ON_RESTORE" -ge 1 ] && [ "$ON_RESTORE" -le 2 ]; then
    report PASS "$NAME-few-resizes" "$ON_MAXIMISE resize on maximise, $ON_RESTORE on restore: $SEEN"
  else
    report FAIL "$NAME-few-resizes" "$ON_MAXIMISE resizes on maximise (want 1), $ON_RESTORE on restore (want 1 or 2): $SEEN"
  fi

  # Restored, the shadow and rounded corners are drawn again.
  read -r VX VY VW VH <<<"$(visible)"
  NEAR="$(pixel $((VX + VW + 3)) $((VY + VH / 2)))"
  FAR="$(pixel $((VX + VW + 40)) $((VY + VH / 2)))"
  CORNER="$(pixel "$VX" "$VY")"
  EDGE="$(pixel $((VX + 40)) "$VY")"
  DETAIL="r+g+b 3px out $NEAR, 40px out $FAR; top left corner $CORNER, top edge $EDGE"
  if [ "$NEAR" -le $((FAR - 20)) ] && [ "$CORNER" -le 600 ] && [ "$EDGE" -ge 700 ]; then
    report PASS "$NAME-restored-shadow" "$DETAIL"
  else
    report FAIL "$NAME-restored-shadow" "$DETAIL"
  fi
fi

# The work area (x y width height): where the window manager tiles. KWin
# doesn't publish _NET_WORKAREA; with no panels it is the whole screen.
workarea() {
  local area
  area="$(xprop -root _NET_WORKAREA 2>/dev/null | sed -n 's/.*= //p' | tr -d , | awk 'NF >= 4 {print $1, $2, $3, $4}')"
  if [ -z "$area" ]; then
    area="$(xwininfo -root | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print 0, 0, w, h}')"
  fi
  echo "$area"
}

# Half-screen tiling: Super+Left under Mutter and Xfwm4 (its shortcut set
# in the session's own xfconf, as Xfce's settings would), a drag of the
# bar to the screen's left edge under KWin (its quick tiling: its
# shortcuts need kglobalaccel, which this session doesn't run). Tiled,
# the visible window fills the left half of the work area. Mutter
# announces the tiling (_GTK_EDGE_CONSTRAINTS), and the window then has
# no margin and square corners, as when maximised; KWin and Xfwm4 don't,
# so the margin stays and the window manager places the visible part by
# it (_GTK_FRAME_EXTENTS). Untiled, the window gets its size back (and,
# from the keyboard, its place). Openbox has no tiling.
# (plugins-themes-Adwaita#14)
tile() { # left|untile
  case "$WM" in
    mutter|xfwm4) xdotool key super+Left; sleep 2 ;;
    kwin)
      read -r PX PY <<<"$(bar_point)"
      xdotool mousemove "$PX" "$PY"; sleep 0.3; xdotool mousedown 1; sleep 0.3
      if [ "$1" = left ]; then
        for i in $(seq 1 20); do xdotool mousemove $((PX - PX * i / 20)) $((PY + (500 - PY) * i / 20)); sleep 0.03; done
        xdotool mousemove 0 500; sleep 1
      else
        for _ in $(seq 1 20); do xdotool mousemove_relative -- 15 10; sleep 0.03; done
        sleep 0.5
      fi
      xdotool mouseup 1; sleep 2 ;;
  esac
}
if [ "$WM" = openbox ]; then
  report SKIP "$NAME-tile" "Openbox has no tiling"
else
  if [ "$WM" = xfwm4 ]; then
    XFWM_PID="$(session_pids | while read -r p; do
      tr '\0' '\n' <"/proc/$p/cmdline" 2>/dev/null | head -1 | grep -qE '(^|/)xfwm4$' && echo "$p"; done | head -1)"
    DBUS_SESSION_BUS_ADDRESS="$(tr '\0' '\n' <"/proc/$XFWM_PID/environ" 2>/dev/null | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p')" \
      xfconf-query -c xfce4-keyboard-shortcuts -p '/xfwm4/custom/<Super>Left' -n -t string -s tile_left_key
    sleep 1
  fi
  UNTILED="$(visible)"
  UNTILED_EXTENTS="$(extents)"
  read -r WX WY WW WH <<<"$(workarea)"
  tile left
  TILED="$(visible)"
  TILED_EXTENTS="$(extents)"
  read -r VX VY VW VH <<<"$TILED"
  CORNER="$(pixel "$VX" "$VY")"
  DETAIL="$UNTILED -> $TILED (left half of the work area: $WX $WY $((WW / 2)) $WH), frame extents $TILED_EXTENTS, top left corner r+g+b $CORNER"
  if xprop -root _NET_SUPPORTED | grep -q _GTK_EDGE_CONSTRAINTS; then
    WANT_EXTENTS="0 0 0 0"
  else
    WANT_EXTENTS="$UNTILED_EXTENTS"
  fi
  if [ "$TILED" = "$WX $WY $((WW / 2)) $WH" ] && [ "$TILED_EXTENTS" = "$WANT_EXTENTS" ] \
    && { [ "$MARGIN" = NO ] || [ "$WANT_EXTENTS" != "0 0 0 0" ] || [ "$CORNER" -ge 700 ]; }; then
    report PASS "$NAME-tile" "$DETAIL"
  else
    report FAIL "$NAME-tile" "$DETAIL (want frame extents $WANT_EXTENTS)"
  fi

  tile untile
  AGAIN="$(visible)"
  AGAIN_EXTENTS="$(extents)"
  DETAIL="$TILED -> $AGAIN (was $UNTILED), frame extents $AGAIN_EXTENTS"
  # KWin's untiling is a drag: the window moves with it.
  if [ "$WM" = kwin ]; then
    SAME="$([ "$(echo "$AGAIN" | cut -d' ' -f3-)" = "$(echo "$UNTILED" | cut -d' ' -f3-)" ] && echo YES)"
  else
    SAME="$([ "$AGAIN" = "$UNTILED" ] && echo YES)"
  fi
  if [ "$SAME" = YES ] && [ "$AGAIN_EXTENTS" = "$UNTILED_EXTENTS" ]; then
    report PASS "$NAME-untile" "$DETAIL"
  else
    report FAIL "$NAME-untile" "$DETAIL"
  fi
fi

# The window menu: a right-click on the bar opens the window manager's
# (_GTK_SHOW_WINDOW_MENU: Mutter, KWin, Xfwm4), or the theme's own where
# the window manager has none to show (Openbox). Its Maximize maximises
# the window; a double-click on the bar restores it. The menus differ:
# where Maximize is, from the pointer, comes from screenshots of each.
# (plugins-themes-Adwaita#14)
read -r VX VY VW VH <<<"$(visible)"
xdotool mousemove $((VX + VW - 40)) $((VY + VH - 40)) click 1
sleep 0.5
read -r PX PY <<<"$(bar_point)"
xdotool mousemove "$PX" "$PY"; sleep 0.5
import -window root -crop 160x120+$((PX + 10))+$((PY + 5)) "$WORK/menu-before.png" 2>/dev/null
BEFORE_MENU="$(geometry)"
xdotool click 3
sleep 1.5
import -window root -crop 160x120+$((PX + 10))+$((PY + 5)) "$WORK/menu-after.png" 2>/dev/null
CHANGED="$(compare -metric AE -fuzz 5% "$WORK/menu-before.png" "$WORK/menu-after.png" null: 2>&1 | cut -d' ' -f1)"
if xprop -root _NET_SUPPORTED | grep -q _GTK_SHOW_WINDOW_MENU; then
  WHOSE="$WM's"
else
  WHOSE="the theme's"
fi
case "$WM" in
  mutter) MAXIMIZE_AT="66 106" ;;
  xfwm4) MAXIMIZE_AT="58 17" ;;
  openbox) MAXIMIZE_AT="59 53" ;;
esac
if [ "$WM" = kwin ]; then
  # A click from xdotool on KWin's menu item does nothing here (the menu
  # stays open); its mnemonic does: Ma&ximize.
  xdotool key x
else
  read -r MDX MDY <<<"$MAXIMIZE_AT"
  xdotool mousemove $((PX + MDX)) $((PY + MDY)); sleep 0.5; xdotool click 1
fi
sleep 1.5
STATE="$(xprop -id "$WINDOW" _NET_WM_STATE)"
MENU_MAXIMISED="$(geometry)"
DETAIL="$WHOSE menu: ${CHANGED:-?} of 19200 pixels changed by it; Maximize: $BEFORE_MENU -> $MENU_MAXIMISED"
if [ "${CHANGED:-0}" -ge 2000 ] 2>/dev/null && echo "$STATE" | grep -q MAXIMIZED_VERT && echo "$STATE" | grep -q MAXIMIZED_HORZ; then
  report PASS "$NAME-window-menu" "$DETAIL"
else
  report FAIL "$NAME-window-menu" "$DETAIL; $STATE"
fi
if echo "$STATE" | grep -q MAXIMIZED; then
  read -r PX PY <<<"$(bar_point)"
  xdotool mousemove "$PX" "$PY" click --repeat 2 --delay 120 1
  sleep 1.5
else
  xdotool key Escape; sleep 0.5
fi
AFTER="$(geometry)"

# A drag on the bar to near the screen's left edge: Mutter moves the
# window, past the edge.
read -r VX VY VW VH <<<"$(visible)"
xdotool mousemove "$((VX + 130))" "$((VY + 20))"; sleep 0.3; xdotool mousedown 1; sleep 0.2
# To 30px from the screen's edge, however far right the window starts.
for _ in $(seq 1 $(((VX + 100) / 10))); do xdotool mousemove_relative -- -10 0; sleep 0.02; done
sleep 0.3; xdotool mouseup 1; sleep 1
MOVED="$(geometry)"
read -r VX VY VW VH <<<"$(visible)"
if [ "$VX" -lt 0 ]; then
  report PASS "$NAME-move" "$AFTER -> $MOVED, past the left edge"
else
  report FAIL "$NAME-move" "$AFTER -> $MOVED (not moved past the left edge: the move wasn't handed to $WM)"
fi

# A drag on the right edge, 100px: Mutter widens the window. With a shadow
# the edge is the band outside the window, 6px out.
read -r VX VY VW VH <<<"$(visible)"
if [ "$MARGIN" = YES ]; then
  EDGE_X=$((VX + VW - 1 + 6))
else
  EDGE_X=$((VX + VW - 2))
fi
OLD_WIDTH=$VW
xdotool mousemove "$EDGE_X" "$((VY + VH / 2))"; sleep 0.3; xdotool mousedown 1; sleep 0.2
for _ in $(seq 1 20); do xdotool mousemove_relative -- 5 0; sleep 0.02; done
sleep 0.3; xdotool mouseup 1; sleep 1
read -r VX VY VW VH <<<"$(visible)"
if [ "$VW" -ge $((OLD_WIDTH + 80)) ]; then
  report PASS "$NAME-resize" "width $OLD_WIDTH -> $VW"
else
  report FAIL "$NAME-resize" "width $OLD_WIDTH -> $VW"
fi

if [ "$MARGIN" = YES ]; then
  # Inside the edge, the content's: a drag there doesn't resize.
  read -r VX VY VW VH <<<"$(visible)"
  OLD_WIDTH=$VW
  drag $((VX + VW - 3)) $((VY + VH / 2)) 5 0
  read -r VX VY VW VH <<<"$(visible)"
  if [ "$VW" = "$OLD_WIDTH" ]; then
    report PASS "$NAME-inside-edge" "width $OLD_WIDTH after a drag 3px inside the right edge"
  else
    report FAIL "$NAME-inside-edge" "width $OLD_WIDTH -> $VW after a drag 3px inside the right edge"
  fi

  # The band is the window's; further out, presses go to what is behind.
  read -r VX VY VW VH <<<"$(visible)"
  IN_BAND="$(window_at $((VX + VW - 1 + 12)) $((VY + VH / 2)))"
  BEYOND="$(window_at $((VX + VW - 1 + 13)) $((VY + VH / 2)))"
  if [ "$IN_BAND" = "$WINDOW" ] && [ "$BEYOND" != "$WINDOW" ]; then
    report PASS "$NAME-click-through" "12px out: the window; 13px out: window $BEYOND behind"
  else
    report FAIL "$NAME-click-through" "12px out: window $IN_BAND, 13px out: window $BEYOND (ThemeDemo is $WINDOW)"
  fi
fi

# An alert is a modal dialog of the window it interrupts (WM_TRANSIENT_FOR,
# _NET_WM_STATE_MODAL), as GTK's are, so the window manager can attach it:
# Mutter centres it on the window (GNOME attaches modal dialogs:
# attach-modal-dialogs, set above as GNOME Shell's override sets it); the
# other window managers leave it where GNUstep put it. Escape still closes
# it: the theme asks for the focus again once it's shown.
# (plugins-themes-Adwaita#22)
echo alert >"$WORK/commands"
sleep 2
ALERT=""
for w in $(xdotool search --onlyvisible --class ThemeDemo 2>/dev/null); do
  if [ "$w" != "$WINDOW" ] && xprop -id "$w" _NET_WM_WINDOW_TYPE 2>/dev/null | grep -q _NET_WM_WINDOW_TYPE_DIALOG; then
    ALERT="$w"
  fi
done
if [ -n "$ALERT" ]; then
  TRANSIENT="$(xprop -id "$ALERT" WM_TRANSIENT_FOR 2>/dev/null | sed -n 's/.*# //p')"
  MODAL="$(xprop -id "$ALERT" _NET_WM_STATE 2>/dev/null | grep -c _NET_WM_STATE_MODAL)"
  read -r VX VY VW VH <<<"$(visible)"
  read -r AL AR AT AB <<<"$(e="$(xprop -id "$ALERT" _GTK_FRAME_EXTENTS 2>/dev/null | sed -n 's/.*= //p' | tr -d ,)"; echo "${e:-0 0 0 0}")"
  # (In a subshell: --shell output sets WINDOW too.)
  read -r AX AW <<<"$(eval "$(xdotool getwindowgeometry --shell "$ALERT")"; echo "$X $WIDTH")"
  OFF_CENTRE=$(( (AX + AL + (AW - AL - AR) / 2) - (VX + VW / 2) ))
fi
xdotool key Escape
sleep 1
CLOSED="$(grep -c '^ThemeDemo-alert-closed' "$WORK/demo.log")"
DETAIL="alert ${ALERT:-none}: transient for ${TRANSIENT:-nothing}, modal ${MODAL:-0}, ${OFF_CENTRE:-?}px off the window's centre; Escape closed it: $CLOSED"
# Only Mutter moves an attached dialog; the others keep GNUstep's place.
CENTRED=YES
[ "$WM" = mutter ] && [ "${OFF_CENTRE#-}" -gt 3 ] && CENTRED=NO
if [ -n "$ALERT" ] && [ "$((TRANSIENT))" = "$WINDOW" ] && [ "$MODAL" = 1 ] && [ "$CENTRED" = YES ] && [ "$CLOSED" = 1 ]; then
  report PASS "$NAME-alert-attached" "$DETAIL"
else
  report FAIL "$NAME-alert-attached" "$DETAIL"
fi

# The compositing manager stops and starts again: without one the margin
# would show black, so the window drops it, and gets it back after. Xfwm4
# only: Mutter is always compositing, Openbox gives no margin, and KWin's
# can't be stopped here (below).
compositor() { # on|off
  local pid bus
  pid="$(session_pids | while read -r p; do
    tr '\0' '\n' <"/proc/$p/cmdline" 2>/dev/null | head -1 | grep -qE '(^|/)xfwm4$' && echo "$p"; done | head -1)"
  bus="$(tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p')"
  case "$WM" in
    xfwm4)
      DBUS_SESSION_BUS_ADDRESS="$bus" xfconf-query -c xfwm4 -p /general/use_compositing -s \
        "$([ "$1" = on ] && echo true || echo false)" ;;
  esac
}
if [ "$MARGIN" = YES ] && [ "$WM" = kwin ]; then
  # KWin 6 has no suspend/resume on D-Bus any more, and its shortcut
  # (Alt+Shift+F12) needs kglobalaccel, which this session doesn't run.
  report SKIP "$NAME-compositor-restart" "KWin 6's compositor can't be stopped from the test session"
elif [ "$MARGIN" = YES ] && [ "$WM" = xfwm4 ]; then
  WITH="$(extents)"
  compositor off
  sleep 2
  WITHOUT="$(extents)"
  compositor on
  sleep 2
  AGAIN="$(extents)"
  DETAIL="frame extents $WITH, without the compositor $WITHOUT, with it again $AGAIN"
  if [ "$WITH" != "0 0 0 0" ] && [ "$WITHOUT" = "0 0 0 0" ] && [ "$AGAIN" = "$WITH" ]; then
    report PASS "$NAME-compositor-restart" "$DETAIL"
  else
    report FAIL "$NAME-compositor-restart" "$DETAIL"
  fi
fi

# Last, as it closes the window: Alt+F4 asks the app to close it
# (WM_DELETE_WINDOW, then -performClose:), and ThemeDemo quits after its
# last window. Without WM_DELETE_WINDOW Mutter kills the app instead
# (XKillClient), and it never gets to quit. KWin's shortcuts need
# kglobalaccel, which this session doesn't run: it gets the request a
# task bar sends (_NET_CLOSE_WINDOW) instead.
xdotool windowactivate --sync "$WINDOW" >/dev/null 2>&1; sleep 1
if [ "$WM" = kwin ]; then
  wmctrl -i -c "$WINDOW"
else
  xdotool key alt+F4
fi
for _ in $(seq 1 10); do
  kill -0 "$DEMO_PID" 2>/dev/null || break
  sleep 0.5
done
QUIT="$(grep -c '^ThemeDemo-terminate' "$WORK/demo.log")"
BROKEN="$(grep -ciE 'connection .*broken|X IO error|Fatal IO error' "$WORK/demo.log")"
DETAIL="quit on its own: $QUIT, X connection broken: $BROKEN, still running: $(kill -0 "$DEMO_PID" 2>/dev/null && echo yes || echo no)"
if [ "$QUIT" = 1 ] && [ "$BROKEN" = 0 ]; then
  report PASS "$NAME-close" "$DETAIL"
else
  report FAIL "$NAME-close" "$DETAIL"
fi

echo "SUMMARY $NAME failed=$FAILED"
exit "$FAILED"
