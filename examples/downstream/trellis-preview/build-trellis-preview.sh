#!/bin/sh
# Build Trellis and TrellisPreview. The manifest's bootstrapCommands load the
# toolchain. hot_reload=no compiles TRLoader's dev hot reload out of release
# builds; TrellisPreview's own live reload of the open file stays.
set -eu
make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)" hot_reload=no
