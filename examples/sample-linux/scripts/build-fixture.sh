#!/bin/sh
set -eu

out_root="${1:-out/build}"
script_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
source_path="$script_root/../src/SampleGNUstepLinuxApp.sh"
mkdir -p "$out_root"
cp "$source_path" "$out_root/SampleGNUstepLinuxApp"
chmod +x "$out_root/SampleGNUstepLinuxApp"
printf 'sample linux fixture build output\n' >"$out_root/build.txt"
printf 'Fixture build output created at %s\n' "$out_root"
