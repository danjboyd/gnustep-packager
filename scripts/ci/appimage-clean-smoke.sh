#!/usr/bin/env bash
# Launch an AppImage in a container that has no GNUstep installed, as a first-time user's machine
# would be, and check that it starts and keeps running.
#
# Usage: scripts/ci/appimage-clean-smoke.sh <path/to/App.AppImage> [image]
#
#   image                      container image (default: ubuntu:24.04); apt- or dnf-based
#   GP_CLEAN_SMOKE_DESKTOP     XDG_CURRENT_DESKTOP values, separated by spaces: the app is launched
#                              once per value (default: "GNOME KDE", so a default theme picked
#                              for GNOME and the plain configuration both get launched)
#   GP_CLEAN_SMOKE_SECONDS     how long the app has to stay up (default: 10)
#   GP_CLEAN_SMOKE_ARGS        extra arguments for the app (word-split)
#   GP_CLEAN_SMOKE_ENV         extra NAME=value environment for the app (word-split)
#   GP_CLEAN_SMOKE_PACKAGES    distribution packages to add first (word-split), for libraries the
#                              AppImage leaves to the host on purpose, as a desktop install has
#   GP_CLEAN_SMOKE_ALLOW_ALERT 1 when the app shows an alert at launch on purpose
#   GP_CLEAN_SMOKE_FONTS       desktop (default): the distribution's default UI fonts, as a
#                              desktop install has, with fontconfig (fonts-dejavu-core on apt, Fedora's
#                              default-fonts-core-sans, which has no DejaVu, on dnf); none: no fonts
#
# As with the launch-only smoke mode, the app passes when it is still running after the startup
# window or has exited with status 0. It fails when its output shows a missing runtime component,
# no usable font or an exception, or when a GNUstep alert panel is on screen at the end of the window: an
# uncaught exception shows a modal "Critical Error" panel and logs nothing.
#
# The runner's own GNUstep (if any) hides a package that loads the build host's backend, tools or
# themes instead of its own; this check doesn't. It needs Docker. The AppImage is extracted in the
# container (--appimage-extract), so FUSE isn't needed, and runs as an unprivileged user on Xvfb.

set -euo pipefail

APPIMAGE="${1:?usage: appimage-clean-smoke.sh <AppImage> [image]}"
IMAGE="${2:-ubuntu:24.04}"
DESKTOPS="${GP_CLEAN_SMOKE_DESKTOP:-GNOME KDE}"
SECONDS_UP="${GP_CLEAN_SMOKE_SECONDS:-10}"
APP_ARGS="${GP_CLEAN_SMOKE_ARGS:-}"
APP_ENV="${GP_CLEAN_SMOKE_ENV:-}"
EXTRA_PACKAGES="${GP_CLEAN_SMOKE_PACKAGES:-}"
ALLOW_ALERT="${GP_CLEAN_SMOKE_ALLOW_ALERT:-0}"
FONTS="${GP_CLEAN_SMOKE_FONTS:-desktop}"
case "${FONTS}" in
  desktop|none) ;;
  *) echo "appimage-clean-smoke: GP_CLEAN_SMOKE_FONTS is desktop or none, not ${FONTS}" >&2; exit 2 ;;
esac

[[ -f "${APPIMAGE}" ]] || { echo "appimage-clean-smoke: no AppImage at ${APPIMAGE}" >&2; exit 2; }
command -v docker >/dev/null || { echo "appimage-clean-smoke: docker is needed" >&2; exit 2; }
DOCKER=(docker)
docker info >/dev/null 2>&1 || DOCKER=(sudo -n docker)

APPIMAGE_DIR="$(cd "$(dirname "${APPIMAGE}")" && pwd)"
APPIMAGE_NAME="$(basename "${APPIMAGE}")"

echo "appimage-clean-smoke: ${APPIMAGE_NAME} on ${IMAGE} (XDG_CURRENT_DESKTOP: ${DESKTOPS}, ${FONTS} fonts, ${SECONDS_UP}s)"
"${DOCKER[@]}" run --rm -i \
  -v "${APPIMAGE_DIR}:/package:ro" \
  -e APPIMAGE_NAME="${APPIMAGE_NAME}" -e DESKTOPS="${DESKTOPS}" -e SECONDS_UP="${SECONDS_UP}" \
  -e APP_ARGS="${APP_ARGS}" -e APP_ENV="${APP_ENV}" -e EXTRA_PACKAGES="${EXTRA_PACKAGES}" \
  -e ALLOW_ALERT="${ALLOW_ALERT}" -e FONTS="${FONTS}" \
  "${IMAGE}" bash -s <<'EOF_CONTAINER'
set -euo pipefail
if command -v apt-get >/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >/dev/null
  font_packages=""
  [ "${FONTS}" = desktop ] && font_packages="fontconfig fonts-dejavu-core"
  # shellcheck disable=SC2086
  apt-get install -y -qq --no-install-recommends xvfb xauth x11-utils ${font_packages} ${EXTRA_PACKAGES} >/dev/null
elif command -v dnf >/dev/null; then
  # Fedora's default UI fonts are Cantarell and Noto, without the DejaVu gnustep-back falls back to.
  font_packages=""
  [ "${FONTS}" = desktop ] && font_packages="fontconfig default-fonts-core-sans"
  # shellcheck disable=SC2086
  dnf install -y -q --setopt=install_weak_deps=False xorg-x11-server-Xvfb xwininfo shadow-utils util-linux ${font_packages} ${EXTRA_PACKAGES} >/dev/null
else
  echo "appimage-clean-smoke: the image has neither apt-get nor dnf" >&2
  exit 2
fi
for path in /usr/GNUstep /etc/GNUstep /usr/lib/GNUstep /usr/local/GNUstep; do
  if [ -e "${path}" ]; then
    echo "appimage-clean-smoke: ${path} exists in the image; it isn't a clean host" >&2
    exit 2
  fi
done
useradd -m smoke
cp "/package/${APPIMAGE_NAME}" /home/smoke/app.AppImage
chown smoke /home/smoke/app.AppImage
chmod 755 /home/smoke/app.AppImage
su smoke -s /bin/bash -c '
  set -uo pipefail
  cd ~
  ./app.AppImage --appimage-extract >/dev/null || { echo "appimage-clean-smoke: extraction failed" >&2; exit 1; }
  Xvfb :42 -screen 0 1280x800x24 -nolisten tcp >/dev/null 2>&1 &
  sleep 2
  # Stops the GNUstep daemons a launch leaves behind (gdnc and gpbs detach). The images may have no
  # pkill, so this reads /proc.
  stop_gnustep_daemons() {
    for comm in /proc/[0-9]*/comm; do
      case "$(cat "${comm}" 2>/dev/null)" in
        gdnc|gpbs|gdomap) kill -KILL "$(basename "$(dirname "${comm}")")" 2>/dev/null ;;
      esac
    done
  }
  overall=0
  for desktop in ${DESKTOPS}; do
    echo "--- XDG_CURRENT_DESKTOP=${desktop} ---"
    # Each launch is a first launch: no daemons or defaults from the previous one.
    stop_gnustep_daemons
    rm -rf ~/GNUstep ~/.config ~/.cache ~/.local
    # shellcheck disable=SC2086
    env DISPLAY=:42 XDG_CURRENT_DESKTOP="${desktop}" APPIMAGE="${HOME}/app.AppImage" ${APP_ENV} \
      ./squashfs-root/AppRun ${APP_ARGS} >app.log 2>&1 </dev/null &
    pid=$!
    sleep "${SECONDS_UP}"
    status=0
    if ! kill -0 "${pid}" 2>/dev/null; then
      wait "${pid}"; code=$?
      if [ "${code}" -ne 0 ]; then
        echo "appimage-clean-smoke: the app exited within ${SECONDS_UP}s (status ${code}) on ${desktop}" >&2
        status=1
      fi
    fi
    # Every GNUstep alert panel is titled " " (one space). Only the app runs on this display.
    if [ "${ALLOW_ALERT}" != "1" ] && kill -0 "${pid}" 2>/dev/null; then
      for window in $(DISPLAY=:42 xwininfo -root -tree | sed -n "s/^ *\(0x[0-9a-f]*\) \" \": .*/\1/p"); do
        if DISPLAY=:42 xwininfo -id "${window}" | grep -q "Map State: IsViewable"; then
          echo "appimage-clean-smoke: the app is showing a GNUstep alert panel on ${desktop} (an uncaught exception shows a modal Critical Error panel); set GP_CLEAN_SMOKE_ALLOW_ALERT=1 if it is intended" >&2
          status=1
          break
        fi
      done
    fi
    if grep -Eq "Unable to find (the )?(backend|gdnc|gpbs|[^ ]+ tool)|[Uu]ncaught exception|ignoring exception|Problem posting .*NSException|NSInternalInconsistencyException|version .GLIBC_[0-9.]+. not found|error while loading shared libraries" app.log \
      && ! grep -q "Glyph generation with no font" app.log; then
      echo "appimage-clean-smoke: the app reported a missing runtime component or an exception on ${desktop}" >&2
      status=1
    fi
    # Without a font it can use, GNUstep draws no text and maps no window, but keeps running.
    if grep -q "Glyph generation with no font" app.log; then
      echo "appimage-clean-smoke: the app found no font it can use on ${desktop} (gnustep-back falls back to DejaVu Sans; see backends.appimage.fonts.bundle)" >&2
      status=1
    fi
    echo "--- app output (first 40 lines) ---"
    head -n 40 app.log
    kill -KILL "${pid}" 2>/dev/null
    wait "${pid}" 2>/dev/null
    stop_gnustep_daemons
    [ "${status}" -eq 0 ] || overall=1
  done
  exit "${overall}"
'
EOF_CONTAINER
echo "appimage-clean-smoke: passed"
