#!/bin/sh
set -eu

marker_path="${GP_APPIMAGE_SMOKE_MARKER_PATH:-}"
if [ -n "$marker_path" ]; then
  mkdir -p "$(dirname "$marker_path")"
  {
    printf 'fixture=sample-linux\n'
    printf 'pwd=%s\n' "$PWD"
    printf 'appdir=%s\n' "${APPDIR:-}"
    printf 'gnustep=%s\n' "${GNUSTEP_PATHPREFIX_LIST:-}"
    printf 'argc=%s\n' "$#"
    printf 'argv0=%s\n' "$0"
    printf 'argv1=%s\n' "${1:-}"
  } >"$marker_path"
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

printf 'Sample GNUstep Linux fixture running\n'
