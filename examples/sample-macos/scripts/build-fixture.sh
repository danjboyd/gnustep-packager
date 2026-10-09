#!/bin/sh
# Builds out/build/SampleMacApp.app: a universal (arm64 + x86_64), ad-hoc
# signed bundle with the hardened runtime, the shape a native macOS build
# hands to the stage step.
set -eu

out_root="${1:-out/build}"
script_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
fixture_root="$script_root/.."
app="$out_root/SampleMacApp.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
xcrun clang -O2 -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 \
  "$fixture_root/src/SampleMacApp.c" -o "$app/Contents/MacOS/SampleMacApp"
cat >"$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>SampleMacApp</string>
  <key>CFBundleIdentifier</key><string>com.example.SampleMacApp</string>
  <key>CFBundleName</key><string>SampleMacApp</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSBackgroundOnly</key><true/>
</dict>
</plist>
PLIST
printf 'APPL????' >"$app/Contents/PkgInfo"
codesign --force --options runtime --timestamp=none -s - "$app"
printf 'Fixture build output created at %s\n' "$app"
