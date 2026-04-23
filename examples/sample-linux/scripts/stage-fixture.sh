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
cat >"$runtime_bin/defaults" <<'EOF'
#!/bin/sh
set -eu

if [ "$#" -lt 3 ]; then
  printf 'usage: defaults <read|write> <domain> <key> [value]\n' >&2
  exit 64
fi

command_name="$1"
domain="$2"
key="$3"
store_root="${HOME}/GNUstep/Defaults"
store_path="${store_root}/${domain}.defaults"
mkdir -p "$store_root"
touch "$store_path"

case "$command_name" in
  read)
    if grep -Fq "${key}=" "$store_path"; then
      grep -F "${key}=" "$store_path" | tail -n 1 | sed "s/^${key}=//"
      exit 0
    fi
    exit 1
    ;;
  write)
    if [ "$#" -ne 4 ]; then
      printf 'usage: defaults write <domain> <key> <value>\n' >&2
      exit 64
    fi
    value="$4"
    temp_path="${store_path}.tmp"
    grep -Fv "${key}=" "$store_path" >"$temp_path" || true
    printf '%s=%s\n' "$key" "$value" >>"$temp_path"
    mv "$temp_path" "$store_path"
    ;;
  *)
    printf 'unsupported defaults command: %s\n' "$command_name" >&2
    exit 64
    ;;
esac
EOF
chmod +x "$runtime_bin/defaults"
printf 'GSTheme=LinuxTheme\n' >"$runtime_config/theme.conf"
printf 'GNUstep theme fixture\n' >"$runtime_theme_root/theme.txt"
printf '<fontconfig></fontconfig>\n' >"$runtime_fonts/fonts.conf"
printf 'SampleGNUstepLinuxApp fixture license notice. License: MIT.\n' >"$metadata_licenses/SampleGNUstepLinuxApp.txt"
printf 'GNUstep runtime fixture notice. License: LGPL-2.1-or-later.\n' >"$metadata_licenses/GNUstep-runtime.txt"
printf '# Sample smoke document\n\nThis file is staged for AppImage open-file smoke tests.\n' >"$metadata_smoke/smoke-document.md"
printf 'fixture stage complete\n' >"$log_root/stage.txt"

icon_path="$metadata_icons/sample-linux.png"
: >"$icon_path"
printf '\211\120\116\107\015\012\032\012\000\000\000\015\111\110\104\122\000\000\000\001\000\000\000\001\010\004\000\000\000\265\034\014\002\000\000\000\013\111\104\101\124\170\332\143\374\377\037\000\003\003\002\000\357\277\153\111\000\000\000\000\111\105\116\104\256\102\140\202' >"$icon_path"
if [ ! -s "$icon_path" ]; then
  printf 'Expected fixture icon was not created: %s\n' "$icon_path" >&2
  exit 1
fi

printf 'Fixture stage output created at %s\n' "$stage_root"
