#!/bin/bash
# shot.sh WORKDIR OUT.png [CROP]: the screen below GNOME's top bar (or CROP,
# an ImageMagick geometry), trimmed to what isn't background, with a 28px
# margin, at most 1200px wide.
W=$1; OUT=$2; CROP=${3:-1600x968+0+32}
DISPLAY=":$(cat "$W/display")" import -window root png:- \
  | convert png:- -crop "$CROP" +repage -fuzz 1.5% -trim +repage \
      -bordercolor '#deddda' -border 28 -resize '1200x>' -strip "$OUT"
