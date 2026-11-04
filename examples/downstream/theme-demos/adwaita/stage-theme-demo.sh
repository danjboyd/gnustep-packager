#!/bin/sh
# Stage ThemeDemo and the GNUstep runtime it links against. gnustep-packager
# builds and adds the theme itself from themeInputs after this script.

set -eu

stage_root="${1:-dist/stage}"
demo_root="Examples/ThemeDemo"
app_stage="$stage_root/app/ThemeDemo.app"
runtime_root="$stage_root/runtime"

rm -rf "$stage_root"
mkdir -p "$stage_root/app" "$runtime_root/lib" \
  "$stage_root/metadata/icons" "$stage_root/metadata/licenses"

cp -a "$demo_root/ThemeDemo.app" "$stage_root/app/"

# The system domain: bundles, fonts, resources and the libraries
# the demo loads at run time. gnustepConfig.systemRoot points here.
system_library=$(gnustep-config --variable=GNUSTEP_SYSTEM_LIBRARY)
mkdir -p "$runtime_root/System"
cp -a "$system_library" "$runtime_root/System/Library"
rm -rf "$runtime_root/System/Library/Makefiles" \
  "$runtime_root/System/Library/Themes" \
  "$runtime_root/System/Library/Headers"
system_tools=$(gnustep-config --variable=GNUSTEP_SYSTEM_TOOLS)
mkdir -p "$runtime_root/System/Tools"
for tool in gdnc gpbs make_services; do
  cp -a "$system_tools/$tool" "$runtime_root/System/Tools/"
done
# Seeding packagedDefaults.defaultTheme runs the bundled defaults tool from here.
mkdir -p "$runtime_root/bin"
cp -a "$system_tools/defaults" "$runtime_root/bin/"

# Every shared library the demo, the tools and the back-end bundle need, except the host's
# C runtime.
find "$app_stage" "$runtime_root/System/Library/Bundles" "$runtime_root/System/Tools" "$runtime_root/bin" -type f \
    -exec sh -c 'file -b "$1" | grep -q "^ELF" && printf "%s\n" "$1"' _ {} \; |
  while IFS= read -r elf; do
    ldd "$elf" 2>/dev/null | awk '$2 == "=>" && $3 ~ /^\// { print $3 }'
  done | sort -u | while IFS= read -r library; do
    case "$(basename "$library")" in
      libc.so.*|libdl.so.*|libm.so.*|libpthread.so.*|librt.so.*|ld-linux-*) continue ;;
    esac
    cp -L "$library" "$runtime_root/lib/"
  done

cp packaging/ThemeDemo.png "$stage_root/metadata/icons/ThemeDemo.png"
cp COPYING.LIB "$stage_root/metadata/licenses/gnustep-runtime.txt"
