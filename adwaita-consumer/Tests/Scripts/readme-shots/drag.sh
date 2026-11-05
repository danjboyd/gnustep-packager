#!/bin/bash
# drag.sh WORKDIR X1 Y1 X2 Y2: a left-button drag in small steps, on the
# session's display only.
W=$1; shift; export DISPLAY=":$(cat "$W/display")"
xdotool mousemove "$1" "$2" mousedown 1
for i in $(seq 1 12); do
  xdotool mousemove $(( $1 + ($3-$1)*i/12 )) $(( $2 + ($4-$2)*i/12 )); sleep 0.03
done
xdotool mouseup 1; sleep 0.4
