#!/bin/sh
set -eu

# Resolve the bundled GNUstep.conf the way gnustep-base does: a path that
# starts with ./ or ../ is relative to the config file's directory.
gnustep_config="${GNUSTEP_CONFIG_FILE:-}"
gnustep_system_library=""
gnustep_theme=""
if [ -n "$gnustep_config" ] && [ -f "$gnustep_config" ]; then
  config_dir=$(dirname -- "$gnustep_config")
  library_value=$(sed -n 's/^GNUSTEP_SYSTEM_LIBRARY=//p' "$gnustep_config" | tail -n 1)
  case "$library_value" in
    ./*|../*) library_value="$config_dir/$library_value" ;;
  esac
  if [ -d "$library_value/Bundles" ]; then
    gnustep_system_library=$(CDPATH= cd -- "$library_value" && pwd -P)
  fi
  if [ -f "$config_dir/GlobalDefaults.plist" ]; then
    gnustep_theme=$(sed -n 's/.*"GSTheme" = "\([^"]*\)";.*/\1/p' "$config_dir/GlobalDefaults.plist")
  fi
fi

marker_path="${GP_APPIMAGE_SMOKE_MARKER_PATH:-}"
if [ -n "$marker_path" ]; then
  mkdir -p "$(dirname "$marker_path")"
  {
    printf 'fixture=sample-linux\n'
    printf 'pwd=%s\n' "$PWD"
    printf 'appdir=%s\n' "${APPDIR:-}"
    printf 'gnustep=%s\n' "${GNUSTEP_PATHPREFIX_LIST:-}"
    printf 'gnustep_config=%s\n' "$gnustep_config"
    printf 'gnustep_system_library=%s\n' "$gnustep_system_library"
    printf 'gnustep_theme=%s\n' "$gnustep_theme"
    printf 'argc=%s\n' "$#"
    printf 'argv0=%s\n' "$0"
    printf 'argv1=%s\n' "${1:-}"
    printf 'path=%s\n' "${PATH:-}"
    printf 'home=%s\n' "${HOME:-}"
    printf 'gnustep_home=%s\n' "${GNUSTEP_HOME:-}"
    printf 'wayland=%s\n' "${WAYLAND_DISPLAY:-}"
    printf 'dbus=%s\n' "${DBUS_SESSION_BUS_ADDRESS:-}"
  } >"$marker_path"
fi

# Lets a test make the fixture report a startup failure and keep going, as
# GNUstep does when it logs an exception.
if [ -n "${GP_FIXTURE_STDERR_LINE:-}" ]; then
  printf '%s\n' "$GP_FIXTURE_STDERR_LINE" >&2
fi

if [ -n "${GP_FIXTURE_EXPECT_ARG0:-}" ] && [ "${1:-}" != "$GP_FIXTURE_EXPECT_ARG0" ]; then
  printf 'ERROR: expected argv1=%s but got %s\n' "$GP_FIXTURE_EXPECT_ARG0" "${1:-}" >&2
  exit 12
fi

if [ -n "${GP_FIXTURE_EXPECT_ARG0_BASENAME:-}" ]; then
  arg0_basename=$(basename -- "${1:-}")
  if [ "$arg0_basename" != "$GP_FIXTURE_EXPECT_ARG0_BASENAME" ]; then
    printf 'ERROR: expected argv1 basename=%s but got %s\n' "$GP_FIXTURE_EXPECT_ARG0_BASENAME" "$arg0_basename" >&2
    exit 13
  fi
fi

if [ -n "${GP_FIXTURE_DEFAULTS_DOMAIN:-}" ] && [ -n "${HOME:-}" ]; then
  defaults_file="${HOME}/GNUstep/Defaults/${GP_FIXTURE_DEFAULTS_DOMAIN}.defaults"
  if [ -f "$defaults_file" ]; then
    printf 'defaults_file=%s\n' "$defaults_file"
    sed 's/^/defaults:/' "$defaults_file"
  fi
fi

if [ -n "${GP_FIXTURE_EXPECT_GNUSTEP_CONFIG:-}" ] && [ -z "$gnustep_system_library" ]; then
  printf 'ERROR: GNUSTEP_CONFIG_FILE (%s) does not lead to the bundled System/Library\n' "$gnustep_config" >&2
  exit 14
fi

printf 'Sample GNUstep Linux fixture running\n'
