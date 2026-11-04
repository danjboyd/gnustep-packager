#!/bin/sh
# Fetch an app's source at a fixed tag, build it, and install it under
# out/install. Usage: build-app.sh <git url> <tag>
set -eu
repo_url="$1"
tag="$2"
source_root="out/source"

rm -rf "$source_root" out/install
mkdir -p out
git clone --quiet --depth 1 --branch "$tag" "$repo_url" "$source_root"
install_root="$(pwd -P)/out/install"
cd "$source_root"
if [ -x ./configure ]; then
  ./configure
fi
make
make install GNUSTEP_INSTALLATION_DOMAIN=LOCAL DESTDIR="$install_root"
