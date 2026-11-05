#!/bin/sh
# Build the demo. The manifest's bootstrapCommands load the toolchain.
set -eu
make -C Examples/ThemeDemo
