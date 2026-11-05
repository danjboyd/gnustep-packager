#!/bin/sh
# Fetch an app's source at a fixed tag or commit, build it, and install it
# under out/install. Usage: build-app.sh <git url> <tag or commit> [subdirectory]
# The subdirectory is for repos that hold several apps, such as gnustep/gap.
set -eu
repo_url="$1"
ref="$2"
subdir="${3:-.}"
source_root="out/source"

rm -rf "$source_root" out/install out/COPYING
mkdir -p "$source_root"
git -C "$source_root" init --quiet
git -C "$source_root" fetch --quiet --depth 1 "$repo_url" "$ref"
git -C "$source_root" checkout --quiet FETCH_HEAD
app_root="$source_root/$subdir"
# stage-app.sh ships this as the app's license.
cp "$app_root/COPYING" out/COPYING
install_root="$(pwd -P)/out/install"
cd "$app_root"
if [ -x ./configure ]; then
  ./configure
fi
make
make install GNUSTEP_INSTALLATION_DOMAIN=LOCAL DESTDIR="$install_root"
