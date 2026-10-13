#!/usr/bin/env bash
# Launch an AppImage in a container that has no GNUstep installed, as a first-time user's machine
# would be, and check that it starts and keeps running.
#
# Usage: scripts/ci/appimage-clean-smoke.sh <path/to/App.AppImage> [image]
#
#   image                      container image (default: ubuntu:24.04); apt- or dnf-based
#   GP_CLEAN_SMOKE_DESKTOP     XDG_CURRENT_DESKTOP for the launch (default: GNOME)
#   GP_CLEAN_SMOKE_SECONDS     how long the app has to stay up (default: 10)
#   GP_CLEAN_SMOKE_ARGS        extra arguments for the app (word-split)
#   GP_CLEAN_SMOKE_ENV         extra NAME=value environment for the app (word-split)
#   GP_CLEAN_SMOKE_PACKAGES    distribution packages to add first (word-split), for libraries the
#                              AppImage leaves to the host on purpose, as a desktop install has
#
# As with the launch-only smoke mode, the app passes when it is still running after the startup
# window or has exited with status 0.
#
# The runner's own GNUstep (if any) hides a package that loads the build host's backend, tools or
# themes instead of its own; this check doesn't. It needs Docker. The AppImage is extracted in the
# container (--appimage-extract), so FUSE isn't needed, and runs as an unprivileged user on Xvfb.

set -euo pipefail

APPIMAGE="${1:?usage: appimage-clean-smoke.sh <AppImage> [image]}"
IMAGE="${2:-ubuntu:24.04}"
DESKTOP="${GP_CLEAN_SMOKE_DESKTOP:-GNOME}"
SECONDS_UP="${GP_CLEAN_SMOKE_SECONDS:-10}"
APP_ARGS="${GP_CLEAN_SMOKE_ARGS:-}"
APP_ENV="${GP_CLEAN_SMOKE_ENV:-}"
EXTRA_PACKAGES="${GP_CLEAN_SMOKE_PACKAGES:-}"

[[ -f "${APPIMAGE}" ]] || { echo "appimage-clean-smoke: no AppImage at ${APPIMAGE}" >&2; exit 2; }
command -v docker >/dev/null || { echo "appimage-clean-smoke: docker is needed" >&2; exit 2; }
DOCKER=(docker)
docker info >/dev/null 2>&1 || DOCKER=(sudo -n docker)

APPIMAGE_DIR="$(cd "$(dirname "${APPIMAGE}")" && pwd)"
APPIMAGE_NAME="$(basename "${APPIMAGE}")"

echo "appimage-clean-smoke: ${APPIMAGE_NAME} on ${IMAGE} (XDG_CURRENT_DESKTOP=${DESKTOP}, ${SECONDS_UP}s)"
"${DOCKER[@]}" run --rm -i \
  -v "${APPIMAGE_DIR}:/package:ro" \
  -e APPIMAGE_NAME="${APPIMAGE_NAME}" -e DESKTOP="${DESKTOP}" -e SECONDS_UP="${SECONDS_UP}" \
  -e APP_ARGS="${APP_ARGS}" -e APP_ENV="${APP_ENV}" -e EXTRA_PACKAGES="${EXTRA_PACKAGES}" \
  "${IMAGE}" bash -s <<'EOF_CONTAINER'
set -euo pipefail
if command -v apt-get >/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >/dev/null
  # shellcheck disable=SC2086
  apt-get install -y -qq --no-install-recommends xvfb xauth ${EXTRA_PACKAGES} >/dev/null
elif command -v dnf >/dev/null; then
  # shellcheck disable=SC2086
  dnf install -y -q xorg-x11-server-Xvfb shadow-utils util-linux ${EXTRA_PACKAGES} >/dev/null
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
  # shellcheck disable=SC2086
  env DISPLAY=:42 XDG_CURRENT_DESKTOP="${DESKTOP}" APPIMAGE="${HOME}/app.AppImage" ${APP_ENV} \
    ./squashfs-root/AppRun ${APP_ARGS} >app.log 2>&1 </dev/null &
  pid=$!
  sleep "${SECONDS_UP}"
  status=0
  if ! kill -0 "${pid}" 2>/dev/null; then
    wait "${pid}"; code=$?
    if [ "${code}" -ne 0 ]; then
      echo "appimage-clean-smoke: the app exited within ${SECONDS_UP}s (status ${code})" >&2
      status=1
    fi
  fi
  if grep -Eq "Unable to find (the )?(backend|gdnc|gpbs)|NSInternalInconsistencyException|version .GLIBC_[0-9.]+. not found|error while loading shared libraries" app.log; then
    echo "appimage-clean-smoke: the app reported a missing runtime component" >&2
    status=1
  fi
  echo "--- app output (first 40 lines) ---"
  head -n 40 app.log
  kill -KILL "${pid}" 2>/dev/null
  exit "${status}"
'
EOF_CONTAINER
echo "appimage-clean-smoke: passed"
