#!/usr/bin/env bash
# Copyright (C) 2026 Daniel Boyd
#
# This file is part of the GNUstep Adwaita theme.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; see the file COPYING.LIB.
# If not, see <http://www.gnu.org/licenses/>.

# GCC check for anything sent to GNUstep (Docs/UPSTREAM_POLICY.md): GNUstep
# also builds with GCC, whose Objective-C front end has no blocks, no
# object literals, no properties' dot syntax and no ARC, and treats a
# method it hasn't seen declared as returning id.  Clang, which builds
# GNUstep here, accepts all of these.
#
# Runs GCC's Objective-C front end, syntax only, over each .m and .c file
# a commit range adds or changes, and fails if GCC reports anything in the
# file itself that it didn't already report for the same file before the
# change.  The installed GNUstep headers were built for clang and
# libobjc2 and GCC can't parse all of them, so diagnostics inside headers
# are ignored: this checks our code, it is not a full GCC build.
#
# Before anything else it shows GCC rejecting a planted array literal and
# block with the same flags; if it doesn't, the check proves nothing and
# the script stops.
#
# Usage:
#   gcc-syntax-check.sh <repository> [<base>] [<ref>]
#       the files changed between <base> (default origin/master) and <ref>
#       (default HEAD) of a GNUstep repository
#   gcc-syntax-check.sh --files <file>...
#       the given files as they are on disk (an issue's reproducer)
#
# Exit status: 0 clean, 1 new diagnostics, 2 the check couldn't run.

set -u
export GIO_USE_VFS=local GVFS_DISABLE_FUSE=1 GIO_USE_VOLUME_MONITOR=unix

if [ $# -lt 1 ]; then
  sed -n '/^# Usage:/,/^# Exit status/p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi

GNUSTEP_SH=/usr/GNUstep/System/Library/Makefiles/GNUstep.sh
if [ -z "${GNUSTEP_MAKEFILES:-}" ] && [ -f "$GNUSTEP_SH" ]; then
  set +u; . "$GNUSTEP_SH"; set -u
fi
command -v gcc >/dev/null && command -v gnustep-config >/dev/null || {
  echo "gcc-syntax-check: needs gcc (with gobjc) and gnustep-config" >&2
  exit 2
}

# GNUstep's flags, less clang's own and those that write files.
BASE_FLAGS=()
for f in $(gnustep-config --objc-flags); do
  case "$f" in
    -fblocks|-fobjc-runtime=*|-fconstant-string-class=*|-fobjc-arc|-ffile-prefix-map=*|-MMD|-MP) ;;
    *) BASE_FLAGS+=("$f") ;;
  esac
done
BASE_FLAGS+=(-x objective-c -fsyntax-only -fgnu-runtime
  -fconstant-string-class=NSConstantString
  "-I$GNUSTEP_MAKEFILES/TestFramework")
for pkg in x11 xext xrender cairo freetype2 fontconfig gio-2.0; do
  BASE_FLAGS+=($(pkg-config --cflags "$pkg" 2>/dev/null))
done

WORK=$(mktemp -d "${TMPDIR:-/tmp}/gcc-syntax-check.XXXXXX") || exit 2
trap 'rm -rf --one-file-system -- "${WORK:?}"' EXIT

# gcc_diagnostics <file to compile> <extra flags...>: GCC's diagnostics
# for that file itself, without line and column (they move between
# versions of the file).
gcc_diagnostics() {
  local file=$1; shift
  local name; name=$(basename "$file")
  (cd "$(dirname "$file")" && gcc "${BASE_FLAGS[@]}" "$@" "$name" 2>&1) \
    | grep -E "^$(printf '%s' "$name" | sed 's/[.[\*^$]/\\&/g'):[0-9]+:[0-9]+: " \
    | sed -E 's/^[^:]+:[0-9]+:[0-9]+: //' | sort -u
}

# The canary: GCC must reject what clang would accept.
cat >"$WORK/canary.m" <<'EOF'
#import <Foundation/Foundation.h>
int main(void)
{
  NSArray *a = @[@"x"];
  void (^b)(void) = ^{ };
  return a == nil && b == 0;
}
EOF
if [ -z "$(gcc_diagnostics "$WORK/canary.m" | grep -i error)" ]; then
  echo "gcc-syntax-check: GCC accepted an array literal and a block with these" >&2
  echo "flags, so the check would prove nothing; not checking." >&2
  exit 2
fi
echo "canary: GCC rejects an array literal and a block, as it should"

status=0

# check_file <label> <file now> <file before, or empty> <include flags...>
check_file() {
  local label=$1 now=$2 before=$3; shift 3
  local new old added
  new=$(gcc_diagnostics "$now" "$@")
  old=""
  [ -n "$before" ] && old=$(gcc_diagnostics "$before" "$@")
  added=$(comm -23 <(printf '%s\n' "$new" | sed '/^$/d') <(printf '%s\n' "$old" | sed '/^$/d'))
  if [ -n "$added" ]; then
    echo "FAIL  $label"
    printf '%s\n' "$added" | sed 's/^/        /'
    status=1
  elif [ -n "$new" ]; then
    echo "ok    $label (only diagnostics it had before the change)"
  else
    echo "ok    $label"
  fi
}

if [ "$1" = "--files" ]; then
  shift
  for f in "$@"; do
    [ -f "$f" ] || { echo "SKIP  $f: no such file"; continue; }
    d=$(cd "$(dirname "$f")" && pwd)
    check_file "$f" "$d/$(basename "$f")" "" "-I$d"
  done
  exit $status
fi

REPO=$(cd "$1" && pwd) || exit 2
BASE=${2:-origin/master}
REF=${3:-HEAD}
git -C "$REPO" rev-parse -q --verify "$BASE^{commit}" >/dev/null \
  && git -C "$REPO" rev-parse -q --verify "$REF^{commit}" >/dev/null || {
  echo "gcc-syntax-check: $BASE or $REF is not a commit in $REPO" >&2
  exit 2
}

FILES=$(git -C "$REPO" diff --name-only --diff-filter=AM "$BASE" "$REF" -- '*.m' '*.c')
HEADERS=$(git -C "$REPO" diff --name-only --diff-filter=AM "$BASE" "$REF" -- '*.h')
if [ -z "$FILES" ]; then
  echo "no .m or .c file changed between $BASE and $REF"
fi
for f in $FILES; do
  dir=$(dirname "$f")
  name=$(basename "$f")
  # Both versions sit in their directory of the repository's tree as it is
  # at <ref>, under names of their own, so relative includes resolve.
  mkdir -p "$WORK/now" "$WORK/before"
  git -C "$REPO" archive "$REF" | tar -x -C "$WORK/now" || exit 2
  now="$WORK/now/$dir/$name"
  before=""
  if git -C "$REPO" cat-file -e "$BASE:$f" 2>/dev/null; then
    before="$WORK/now/$dir/.before-$name"
    git -C "$REPO" show "$BASE:$f" >"$before"
  fi
  check_file "$f" "$now" "$before" \
    "-I$WORK/now" "-I$WORK/now/Headers" "-I$WORK/now/Source" \
    "-I$WORK/now/Headers/Additions" "-I$WORK/now/$dir" \
    "-I$REPO" "-I$REPO/Headers" "-I$REPO/Source"
  rm -rf --one-file-system -- "${WORK:?}/now"
done
if [ -n "$HEADERS" ]; then
  echo "headers changed (checked through the files that include them):"
  printf '%s\n' "$HEADERS" | sed 's/^/        /'
fi
exit $status
