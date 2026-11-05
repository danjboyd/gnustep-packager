#!/bin/bash
# Run a GUI program for a few seconds with nothing of the user's in reach: a
# private X display and session bus, and a scratch directory bound over the
# user's home.
#
# Setting HOME is not enough. gnustep-base takes the home directory from the
# passwd database, so an app given only a private HOME still reads and rewrites
# the real ~/GNUstep/Defaults. The bind covers that path itself.
#
# Usage: run-gui-isolated.sh [--seconds N] [--screenshot PATH] [--home DIR] -- PROGRAM [ARGS...]
# PROGRAM and PATH must be outside the home directory, which the bind hides.
# Exit status: the program's, or 0 if it was still running after N seconds.
set -euo pipefail

seconds=10
screenshot=""
scratch_home=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --seconds) seconds="$2"; shift 2 ;;
    --screenshot) screenshot="$2"; shift 2 ;;
    --home) scratch_home="$2"; shift 2 ;;
    --) shift; break ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 64 ;;
  esac
done
if [ "$#" -eq 0 ]; then
  printf 'No program given.\n' >&2
  exit 64
fi

for tool in bwrap xvfb-run dbus-run-session; do
  if ! command -v "$tool" >/dev/null; then
    printf 'Refusing to run without %s: nothing else isolates the real home.\n' "$tool" >&2
    exit 69
  fi
done

real_home=$(getent passwd "$(id -u)" | cut -d: -f6)
program=$(realpath -- "$1")
shift
case "$program/" in
  "$real_home"/*)
    printf 'Refusing to run %s: it is under %s, which the sandbox hides. Copy it out first.\n' "$program" "$real_home" >&2
    exit 64
    ;;
esac
if [ -n "$screenshot" ]; then
  screenshot=$(realpath -m -- "$screenshot")
  case "$screenshot" in
    "$real_home"/*)
      printf 'Refusing to write %s: it is under %s, which the sandbox hides.\n' "$screenshot" "$real_home" >&2
      exit 64
      ;;
  esac
fi

remove_home=""
if [ -z "$scratch_home" ]; then
  scratch_home=$(mktemp -d)
  remove_home=1
fi
scratch_home=$(realpath -- "$scratch_home")
case "$scratch_home/" in
  "$real_home"/*)
    printf 'Refusing to use %s as the scratch home: it is under %s.\n' "$scratch_home" "$real_home" >&2
    exit 64
    ;;
esac
trap '[ -z "$remove_home" ] || rm -rf "$scratch_home"' EXIT
chmod 700 "$scratch_home"

# Inside the sandbox: AppImages can't mount with FUSE there, so they extract.
inner='
  seconds="$1"; screenshot="$2"; shift 2
  "$@" &
  program_pid=$!
  waited=0
  while [ "$waited" -lt "$seconds" ]; do
    sleep 1
    waited=$((waited + 1))
    if ! kill -0 "$program_pid" 2>/dev/null; then
      wait "$program_pid"
      exit $?
    fi
  done
  if [ -n "$screenshot" ]; then
    import -window root "$screenshot" || printf "No screenshot: import failed.\n" >&2
  fi
  kill "$program_pid" 2>/dev/null || true
  pkill -P "$program_pid" 2>/dev/null || true
  exit 0
'
env -u WAYLAND_DISPLAY -u DISPLAY -u XAUTHORITY -u DBUS_SESSION_BUS_ADDRESS \
    -u GNUSTEP_MAKEFILES -u GNUSTEP_CONFIG_FILE -u GNUSTEP_USER_ROOT \
  bwrap --dev-bind / / --bind "$scratch_home" "$real_home" \
    --unshare-pid --proc /proc --die-with-parent \
    --setenv HOME "$real_home" \
    --setenv GNUSTEP_HOME "$real_home" \
    --setenv APPIMAGE_EXTRACT_AND_RUN 1 \
    -- dbus-run-session -- xvfb-run -a -s '-screen 0 1280x800x24' \
      bash -c "$inner" isolated "$seconds" "$screenshot" "$program" "$@"
