#!/bin/bash
# stop.sh WORKDIR: stops session.sh's session (its processes are found by
# their runtime directory) and deletes WORKDIR, never across a mount.
W=$1; N=$(cat "$W/display")
for pid in $(pgrep -u "$(id -u)"); do
  { tr '\0' '\n' <"/proc/$pid/environ"; } 2>/dev/null | grep -qxF "XDG_RUNTIME_DIR=$W/run" && kill "$pid" 2>/dev/null
  { tr '\0' '\n' <"/proc/$pid/environ"; } 2>/dev/null | grep -qxF "DISPLAY=:$N" && kill -9 "$pid" 2>/dev/null
done
pkill -f "^Xvfb :$N " ; sleep 2
for m in $(awk -v w="$W" 'index($2, w) == 1 {print $2}' /proc/mounts); do fusermount -u "$m" 2>/dev/null || umount "$m" 2>/dev/null; done
if awk -v w="$W" 'index($2, w) == 1 {f = 1} END {exit !f}' /proc/mounts; then
  echo "not deleting $W: something is still mounted in it" >&2; exit 1
fi
rm -rf --one-file-system "$W"
