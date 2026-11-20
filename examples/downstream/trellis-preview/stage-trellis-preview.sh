#!/bin/sh
# Stage TrellisPreview, the Trellis libraries and the GNUstep runtime it links
# against. gnustep-packager builds and adds Adwaita itself from themeInputs
# after this script.

set -eu

stage_root="${1:-dist/stage}"
app_stage="$stage_root/app/TrellisPreview.app"
runtime_root="$stage_root/runtime"

rm -rf "$stage_root"
mkdir -p "$stage_root/app" "$runtime_root/lib" \
  "$stage_root/metadata/icons" "$stage_root/metadata/licenses"

cp -a TrellisPreview.app "$stage_root/app/"
# libTrellis and libTrellisEngine, built in obj/ next to the app.
cp -a obj/libTrellis.so* obj/libTrellisEngine.so* "$runtime_root/lib/"

# The system domain: bundles, fonts, resources and the libraries
# the app loads at run time. gnustepConfig.systemRoot points here.
system_library=$(gnustep-config --variable=GNUSTEP_SYSTEM_LIBRARY)
mkdir -p "$runtime_root/System"
cp -a "$system_library" "$runtime_root/System/Library"
# gnustep-cli-new installs gnustep-base, -gui and -back in the local domain
# and keeps only gnustep-make in the system domain, so stage the local
# domain's Library too when GNUstep itself lives there. (On a /usr/GNUstep
# install, base is in the system domain and the local one holds only
# unrelated extras, which stay out.)
toolchain_local_library=$(gnustep-config --variable=GNUSTEP_LOCAL_LIBRARY)
if [ "$toolchain_local_library" != "$system_library" ] &&
   ls "$toolchain_local_library"/Libraries/libgnustep-base.so* >/dev/null 2>&1; then
  cp -a "$toolchain_local_library/." "$runtime_root/System/Library/"
fi
rm -rf "$runtime_root/System/Library/Makefiles" \
  "$runtime_root/System/Library/Themes" \
  "$runtime_root/System/Library/Headers"
system_tools=$(gnustep-config --variable=GNUSTEP_SYSTEM_TOOLS)
mkdir -p "$runtime_root/System/Tools"
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
# Seeding packagedDefaults.defaultTheme runs the bundled defaults tool from here.
mkdir -p "$runtime_root/bin"
cp -L "$(system_tool defaults)" "$runtime_root/bin/defaults"

# Every shared library the app, the Trellis libraries, the tools and the back-end bundle need, except the host's
# C runtime.
find "$app_stage" "$runtime_root/lib" "$runtime_root/System/Library/Bundles" "$runtime_root/System/Tools" "$runtime_root/bin" -type f \
    -exec sh -c 'file -b "$1" | grep -q "^ELF" && printf "%s\n" "$1"' _ {} \; |
  while IFS= read -r elf; do
    ldd "$elf" 2>/dev/null | awk '$2 == "=>" && $3 ~ /^\// { print $3 }'
  done | sort -u | while IFS= read -r library; do
    case "$(basename "$library")" in
      libc.so.*|libdl.so.*|libm.so.*|libpthread.so.*|librt.so.*|ld-linux-*) continue ;;
    esac
    case "$(basename "$library")" in
      libTrellis.so*|libTrellisEngine.so*) continue ;;
    esac
    cp -L "$library" "$runtime_root/lib/"
  done

# TrellisPreview has no icon of its own: use packaging/TrellisPreview.png when the repo
# has one, otherwise GNUstep's own icon from the staged runtime.
# A TIFF can hold several sizes, and convert would write one PNG per page:
# take the largest page.
largest_page() {
  page=$(identify -format '%p %w\n' "$1" 2>/dev/null | sort -k2 -n | tail -n 1 | cut -d' ' -f1)
  printf '%s[%s]\n' "$1" "${page:-0}"
}
if [ -f packaging/TrellisPreview.png ]; then
  cp packaging/TrellisPreview.png "$stage_root/metadata/icons/TrellisPreview.png"
else
  gnustep_icon=$(find "$runtime_root/System/Library/Images" -name 'GNUstep.tiff' | head -n 1)
  if [ -z "$gnustep_icon" ]; then
    printf 'No packaging/TrellisPreview.png and no GNUstep.tiff to make an icon from\n' >&2
    exit 1
  fi
  convert "$(largest_page "$gnustep_icon")" -resize 256x256 "$stage_root/metadata/icons/TrellisPreview.png"
fi
# A sample screen for the smoke launch to open: with no file, TrellisPreview
# starts in a modal Open panel, which a launch check can't tell from a hang.
mkdir -p "$stage_root/metadata/samples"
cp Examples/TrellisDemo/Settings.trellis Examples/TrellisDemo/Settings.sample.json "$stage_root/metadata/samples/"

cp COPYING.LIB "$stage_root/metadata/licenses/trellis.txt"
# The GNUstep runtime is LGPL-2.1-or-later too: the same licence text.
cp COPYING.LIB "$stage_root/metadata/licenses/gnustep-runtime.txt"

# Adwaita's own licence and third-party notices (some of its icons are GNOME's,
# under LGPL-3 or CC-BY-SA), from the commit themeInputs pins. The packager
# builds the theme but doesn't stage its notices.
adwaita_ref=9c25a6823c3d0af715b197e64e8ca2d9bee9b456
for file in COPYING.LIB THIRD-PARTY-NOTICES; do
  curl --fail --location --silent --show-error \
    "https://raw.githubusercontent.com/danjboyd/plugins-themes-Adwaita/$adwaita_ref/$file" \
    -o "$stage_root/metadata/licenses/adwaita-$file.txt"
done
