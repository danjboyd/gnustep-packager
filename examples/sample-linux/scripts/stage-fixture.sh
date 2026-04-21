#!/bin/sh
set -eu

stage_root="${1:-dist/stage}"
script_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
fixture_root="$script_root/.."
built_executable="$fixture_root/out/build/SampleGNUstepLinuxApp"
app_root="$stage_root/app/SampleGNUstepLinuxApp.app"
runtime_bin="$stage_root/runtime/bin"
runtime_fonts="$stage_root/runtime/etc/fonts"
runtime_config="$stage_root/runtime/config"
runtime_theme_root="$stage_root/runtime/lib/GNUstep/Themes/Adwaita.theme"
metadata_icons="$stage_root/metadata/icons"
metadata_licenses="$stage_root/metadata/licenses"
metadata_smoke="$stage_root/metadata/smoke"
log_root="$stage_root/logs"

rm -rf "$stage_root"
mkdir -p "$app_root" "$runtime_bin" "$runtime_fonts" "$runtime_config" "$runtime_theme_root" "$metadata_icons" "$metadata_licenses" "$metadata_smoke" "$log_root"

if [ ! -f "$built_executable" ]; then
  printf 'Expected built sample executable not found: %s\n' "$built_executable" >&2
  exit 1
fi

cp "$built_executable" "$app_root/SampleGNUstepLinuxApp"
chmod +x "$app_root/SampleGNUstepLinuxApp"
printf 'fixture plist\n' >"$app_root/Info-gnustep.plist"
printf '#!/bin/sh\nprintf "GNUstep runtime helper\\n"\n' >"$runtime_bin/gnustep-env.sh"
chmod +x "$runtime_bin/gnustep-env.sh"
printf 'GSTheme=LinuxTheme\n' >"$runtime_config/theme.conf"
printf 'GNUstep theme fixture\n' >"$runtime_theme_root/theme.txt"
printf '<fontconfig></fontconfig>\n' >"$runtime_fonts/fonts.conf"
printf 'SampleGNUstepLinuxApp fixture license notice. License: MIT.\n' >"$metadata_licenses/SampleGNUstepLinuxApp.txt"
printf 'GNUstep runtime fixture notice. License: LGPL-2.1-or-later.\n' >"$metadata_licenses/GNUstep-runtime.txt"
printf '# Sample smoke document\n\nThis file is staged for AppImage open-file smoke tests.\n' >"$metadata_smoke/smoke-document.md"
printf 'fixture stage complete\n' >"$log_root/stage.txt"

base64_cmd="${BASE64:-/usr/bin/base64}"
if [ ! -x "$base64_cmd" ]; then
  base64_cmd="base64"
fi

"$base64_cmd" -d >"$metadata_icons/sample-linux.png" <<'EOF'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/a0kAAAAASUVORK5CYII=
EOF

printf 'Fixture stage output created at %s\n' "$stage_root"
