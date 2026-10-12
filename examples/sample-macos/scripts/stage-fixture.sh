#!/bin/sh
# Stages the fixture with the packager layout: app/<Name>.app, an empty
# runtime/ (a native bundle carries its own runtime) and metadata/.
set -eu

stage_root="${1:-dist/stage}"
script_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
fixture_root="$script_root/.."
built_app="$fixture_root/out/build/SampleMacApp.app"

if [ ! -d "$built_app" ]; then
  printf 'Expected built sample app not found: %s\n' "$built_app" >&2
  exit 1
fi

rm -rf "$stage_root"
mkdir -p "$stage_root/app" "$stage_root/runtime" "$stage_root/metadata/licenses" "$stage_root/metadata/dmg"
ditto "$built_app" "$stage_root/app/SampleMacApp.app"
printf 'SampleMacApp fixture license notice. License: MIT.\n' >"$stage_root/metadata/licenses/SampleMacApp.txt"

# A 1x1 PNG is enough to exercise the background-image path.
printf '\211\120\116\107\015\012\032\012\000\000\000\015\111\110\104\122\000\000\000\001\000\000\000\001\010\004\000\000\000\265\034\014\002\000\000\000\013\111\104\101\124\170\332\143\374\377\037\000\003\003\002\000\357\277\153\111\000\000\000\000\111\105\116\104\256\102\140\202' >"$stage_root/metadata/dmg/background.png"

printf 'Fixture stage output created at %s\n' "$stage_root"
