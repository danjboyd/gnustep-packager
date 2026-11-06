#!/bin/bash
# Builds the updater libraries, gp-update-helper and the fixture app against the
# host's GNUstep, makes the test feeds, and runs the dialog cases on a private
# display with a scratch home (scripts/run-gui-isolated.sh). Prints each case's
# marker file. Needs gnustep-config, clang, python3 with cryptography, xdotool,
# xwininfo and ImageMagick's import.
#
# Usage: tests/fixtures/updater-ui/run-local.sh WORKDIR
# WORKDIR must be outside the home directory, which the sandbox hides.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../../.." && pwd)
work=${1:?usage: run-local.sh WORKDIR (outside the home directory)}
case "$work" in "$HOME"|"$HOME"/*) echo "WORKDIR must be outside $HOME" >&2; exit 2 ;; esac
rm -rf "$work"; mkdir -p "$work/fixture" "$work/feeds" "$work/fakebin" "$work/out"
cp -R "$repo/updater" "$work/updater"
for component in GPUpdaterCore GPUpdaterUI gp-update-helper; do
  make -s -C "$work/updater/objc/$component" >/dev/null
done
here=$(cd "$(dirname "$0")" && pwd)
cp "$here"/main.m "$here"/lib.sh "$here"/run-cases.sh "$work/fixture/"
( cd "$work/fixture" && clang $(gnustep-config --objc-flags) -I../updater/objc/GPUpdaterUI/Headers -I../updater/objc/GPUpdaterCore/Headers \
    main.m -o UpdaterFixture ../updater/objc/GPUpdaterUI/libGPUpdaterUI.a ../updater/objc/GPUpdaterCore/libGPUpdaterCore.a $(gnustep-config --gui-libs) 2>/dev/null )
python3 -I "$here/make-feeds.py" "$work/feeds" >/dev/null
printf 'not really an AppImage 1.0.0\n' > "$work/feeds/Installed.AppImage"
cat > "$work/fakebin/xdg-open" <<SH
#!/bin/sh
printf 'xdg-open %s\n' "\$*" >> "$work/out/xdg-open.log"
SH
chmod +x "$work/fakebin/xdg-open" "$work/fixture/run-cases.sh"
makefiles=$(gnustep-config --variable=GNUSTEP_MAKEFILES)
"$repo/scripts/run-gui-isolated.sh" --seconds 300 -- /usr/bin/env GPUI_ROOT="$work" GNUSTEP_MAKEFILES="$makefiles" \
  "$work/fixture/run-cases.sh" >"$work/out/run.log" 2>&1 || true
for marker in "$work"/out/*.marker; do
  printf '== %s\n' "$(basename "$marker" .marker)"
  grep -v '^window' "$marker"
done
[ -f "$work/out/xdg-open.log" ] && cat "$work/out/xdg-open.log" || echo "(xdg-open was not called)"
