#!/bin/bash
# place.sh WORKDIR TITLE GNUstep|Adwaita WIDTH HEIGHT: moves the largest window
# whose title matches TITLE to the top left and sizes its visible part
# (Mutter's 37px title bar included for GNUstep; for Adwaita the X window
# also holds the 30/30/24/36px shadow margin). Apps may keep a larger
# minimum size.
W=$1; export DISPLAY=":$(cat "$W/display")"
TITLE=$2 THEME=$3 WIDTH_WANTED=$4 HEIGHT_WANTED=$5
best=""; area=0
for w in $(xdotool search --onlyvisible --name "$TITLE" 2>/dev/null); do
  # Mutter's frame for the window has its title too, but can't be sized.
  xprop -id "$w" WM_CLASS 2>/dev/null | grep -q mutter-x11-frames && continue
  eval "$(xdotool getwindowgeometry --shell "$w")"
  [ $((WIDTH*HEIGHT)) -gt $area ] && { area=$((WIDTH*HEIGHT)); best=$w; }
done
[ -z "$best" ] && { echo "no window titled $TITLE" >&2; exit 1; }
if [ "$THEME" = Adwaita ]; then
  xdotool windowsize "$best" $((WIDTH_WANTED+60)) $((HEIGHT_WANTED+60)); xdotool windowmove "$best" 50 60
else
  xdotool windowsize "$best" "$WIDTH_WANTED" $((HEIGHT_WANTED-37)); xdotool windowmove "$best" 80 80
fi
sleep 2
