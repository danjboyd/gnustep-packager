#!/bin/sh
# Stage an app installed by build-app.sh with the GNUstep runtime it needs.
# Usage: stage-app.sh <AppName> <stage root>
set -eu
app_name="$1"
stage_root="$2"
runtime_root="$stage_root/runtime"
system_library=$(gnustep-config --variable=GNUSTEP_SYSTEM_LIBRARY)
system_tools=$(gnustep-config --variable=GNUSTEP_SYSTEM_TOOLS)
local_library="out/install$(gnustep-config --variable=GNUSTEP_LOCAL_LIBRARY)"
local_tools="out/install$(gnustep-config --variable=GNUSTEP_LOCAL_TOOLS)"
local_apps="out/install$(gnustep-config --variable=GNUSTEP_LOCAL_APPS)"

rm -rf "$stage_root"
mkdir -p "$stage_root/app" "$stage_root/metadata/icons" \
  "$stage_root/metadata/licenses" "$runtime_root/lib" "$runtime_root/bin" \
  "$runtime_root/System/Tools"

cp -a "$local_apps/$app_name.app" "$stage_root/app/"

# The system domain, without the build-time parts and the toolchain's themes.
cp -a "$system_library" "$runtime_root/System/Library"

# What the app installed besides itself: its frameworks, bundles and tools.
if [ -d "$local_library" ]; then
  cp -a "$local_library/." "$runtime_root/System/Library/"
fi
if [ -d "$local_tools" ]; then
  cp -a "$local_tools/." "$runtime_root/System/Tools/"
fi
rm -rf "$runtime_root/System/Library/Makefiles" \
  "$runtime_root/System/Library/Headers" \
  "$runtime_root/System/Library/Themes" \
  "$runtime_root/System/Library/Documentation"

# A GNUstep tool from the system domain, or from PATH when the toolchain keeps
# it elsewhere (gnustep-cli-new does not put gdnc and its peers in
# GNUSTEP_SYSTEM_TOOLS).
system_tool() {
  if [ -x "$system_tools/$1" ]; then
    printf '%s\n' "$system_tools/$1"
  elif command -v "$1" >/dev/null 2>&1; then
    command -v "$1"
  else
    printf 'GNUstep tool %s not found in %s or on PATH\n' "$1" "$system_tools" >&2
    return 1
  fi
}
for tool in gdnc gpbs make_services; do
  cp -L "$(system_tool "$tool")" "$runtime_root/System/Tools/$tool"
done
# Seeding packaged defaults runs the bundled defaults tool from here.
cp -L "$(system_tool defaults)" "$runtime_root/bin/defaults"

# Every shared library the staged programs and bundles need, except the host's
# C runtime and what is already staged.
LD_LIBRARY_PATH="$runtime_root/System/Library/Libraries:${LD_LIBRARY_PATH:-}"
export LD_LIBRARY_PATH
find "$stage_root/app" "$runtime_root/System" "$runtime_root/bin" -type f \
    -exec sh -c 'file -b "$1" | grep -q "^ELF" && printf "%s\n" "$1"' _ {} \; |
  while IFS= read -r elf; do
    ldd "$elf" 2>/dev/null | awk '$2 == "=>" && $3 ~ /^\// { print $3 }'
  done | sort -u | while IFS= read -r library; do
    case "$library" in
      */"$runtime_root"/*|"$runtime_root"/*) continue ;;
    esac
    case "$(basename "$library")" in
      libc.so.*|libdl.so.*|libm.so.*|libpthread.so.*|librt.so.*|ld-linux-*) continue ;;
    esac
    cp -L "$library" "$runtime_root/lib/"
  done

cp out/COPYING "$stage_root/metadata/licenses/$app_name.txt"

# The icon: the app's own, converted when it is a TIFF.
icon=$(find "$stage_root/app/$app_name.app" -type f \( -iname "$app_name*.png" -o -iname "$app_name*.tif*" \) | head -n 1)
if [ -z "$icon" ]; then
  icon=$(find "$stage_root/app/$app_name.app" -type f \( -iname '*.png' -o -iname '*.tif*' \) -size +2k | head -n 1)
fi
if [ -z "$icon" ]; then
  printf 'No icon found in %s.app\n' "$app_name" >&2
  exit 1
fi
convert "$icon" -resize 256x256 "$stage_root/metadata/icons/app.png"
