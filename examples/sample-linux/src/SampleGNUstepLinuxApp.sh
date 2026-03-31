#!/bin/sh
set -eu

marker_path="${1:-}"
if [ -n "$marker_path" ]; then
  mkdir -p "$(dirname "$marker_path")"
  {
    printf 'fixture=sample-linux\n'
    printf 'pwd=%s\n' "$PWD"
    printf 'appdir=%s\n' "${APPDIR:-}"
    printf 'gnustep=%s\n' "${GNUSTEP_PATHPREFIX_LIST:-}"
    printf 'argv0=%s\n' "$0"
  } >"$marker_path"
fi

printf 'Sample GNUstep Linux fixture running\n'
