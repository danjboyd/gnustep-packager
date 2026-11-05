#!/bin/bash
# session.sh WORKDIR [DISPLAY_NUMBER]: GNOME Shell (X11) on a private Xvfb for
# the README's screenshots, with a solid light background, scratch XDG
# directories, its own D-Bus session, no gvfs and empty GNUstep defaults.
# Runs until killed; stop it with stop.sh WORKDIR.
set -u
W=$1; N=${2:-140}
mkdir -p "$W"/{config/glib-2.0/settings,data,cache,state,run,gs/glib-2.0/settings,gsdefaults}
chmod 700 "$W/run"
cat >"$W/config/glib-2.0/settings/keyfile" <<'K'
[org/gnome/desktop/background]
picture-uri=''
picture-uri-dark=''
picture-options='none'
color-shading-type='solid'
primary-color='#deddda'

[org/gnome/mutter]
attach-modal-dialogs=true

[org/gnome/desktop/interface]
color-scheme='default'
font-name='Cantarell 11'
K
cp "$W/config/glib-2.0/settings/keyfile" "$W/gs/glib-2.0/settings/keyfile"
printf "\n[org/gnome/desktop/wm/preferences]\nbutton-layout='appmenu:minimize,maximize,close'\n" \
  >>"$W/gs/glib-2.0/settings/keyfile"
# Empty user defaults: a user's own settings (menu style, decorations)
# don't reach either side. GNUstep ignores a config others can write.
grep -v '^GNUSTEP_USER_DEFAULTS_DIR=' "${GNUSTEP_CONFIG_FILE:-/etc/GNUstep/GNUstep.conf}" >"$W/GNUstep.conf"
echo "GNUSTEP_USER_DEFAULTS_DIR=$W/gsdefaults" >>"$W/GNUstep.conf"
chmod 600 "$W/GNUstep.conf"
echo "$N" >"$W/display"
# The session's bus can start only these services. The standard service
# directories would also let any client start gvfs (which mounts the phone
# that is this machine's network), the keyring, Tracker or the document
# portal's FUSE mount; GIO_USE_VFS and friends only stop clients that read
# them.
mkdir -p "$W/dbus/services"
for svc in org.a11y.Bus; do
  [ -e "/usr/share/dbus-1/services/$svc.service" ] \
    && ln -sf "/usr/share/dbus-1/services/$svc.service" "$W/dbus/services/"
done
sed "s|<standard_session_servicedirs */>|<servicedir>$W/dbus/services</servicedir>|" \
  /usr/share/dbus-1/session.conf >"$W/dbus/session.conf"
export DISPLAY=":$N"
Xvfb "$DISPLAY" -screen 0 1600x1000x24 -nolisten tcp +extension GLX +extension RANDR >/dev/null 2>&1 &
sleep 1
env -i HOME="$HOME" PATH="$PATH" DISPLAY="$DISPLAY" XDG_CONFIG_HOME="$W/config" \
  XDG_DATA_HOME="$W/data" XDG_CACHE_HOME="$W/cache" XDG_STATE_HOME="$W/state" \
  XDG_RUNTIME_DIR="$W/run" GSETTINGS_BACKEND=keyfile LIBGL_ALWAYS_SOFTWARE=1 \
  GIO_USE_VFS=local GVFS_DISABLE_FUSE=1 GIO_USE_VOLUME_MONITOR=unix \
  dbus-run-session --config-file="$W/dbus/session.conf" -- gnome-shell --x11 >"$W/wm.log" 2>&1 &
for _ in $(seq 1 60); do
  xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q "window id" && break
  sleep 0.5
done
# GNOME Shell starts in the overview, and a first run shows a welcome dialog.
sleep 4; xdotool key Escape; sleep 1; xdotool key Escape; sleep 1
echo "ready on :$N"
wait
