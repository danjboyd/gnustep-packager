#!/bin/bash
. "$(dirname "$0")/lib.sh"
export PATH=$U/fakebin:$PATH
rm -f $OUT/xdg-open.log
# 1a. Manual check, up to date: the up-to-date alert, closed with Return.
launch c1a-uptodate-manual uptodate manual GPUI_RESET=1
w=$(wait_alert 1) && { shot c1a; press "$w" Return; }; sleep 1; stop
# 1b. Automatic check, up to date: no alert.
launch c1b-uptodate-auto uptodate auto
sleep 6; xwininfo -root -tree | grep -c '"Alert": ("UpdaterFixture"' > $OUT/c1b.alertcount; stop
# 3. Later, then the next automatic check offers it again.
launch c3-later offer101 auto GPUI_RESET=1
w=$(wait_alert 1) && { shot c3; press "$w" click:170,140; }; sleep 1; stop
launch c3-later-relaunch offer101 auto
w=$(wait_alert 1) && press "$w" click:170,140; sleep 1; stop
# 4. Skip This Version (no release notes: third button), then quiet for 1.0.1, offered 1.0.2.
launch c4-skip offer101 manual GPUI_RESET=1
w=$(wait_alert 1) && press "$w" Tab space; sleep 1; stop
launch c4-skip-auto101 offer101 auto
sleep 6; stop
launch c4-skip-auto102 offer102 auto
w=$(wait_alert 1) && press "$w" click:170,140; sleep 1; stop
# 5. More..., then View Changes: the release notes URL should reach xdg-open,
# and the first alert should come back.
launch c5-more offer101notes manual GPUI_RESET=1
w=$(wait_alert 1) && press "$w" Tab space
w=$(wait_alert 2) && { shot c5-more; press "$w" Return; }
w=$(wait_alert 3) && press "$w" click:170,140; sleep 1; stop
# 6. Install Update on a tampered asset: the helper refuses it, and the app says why.
launch c6-tampered tampered manual GPUI_RESET=1 APPIMAGE=$U/feeds/Installed.AppImage
w=$(wait_alert 1) && press "$w" Return
w=$(wait_alert 2) && { shot c6; press "$w" Return; }; sleep 1; stop
# 6b. The feed can't be read.
launch c6b-missing missing manual GPUI_RESET=1
w=$(wait_alert 1) && { shot c6b; press "$w" Return; }; sleep 1; stop
# 7. No build for this machine.
launch c7-armonly armonly manual GPUI_RESET=1
w=$(wait_alert 1) && { shot c7; press "$w" Return; }; sleep 1; stop
# 8. Install Update on a good asset: prepared, then Restart to Finish Updating, Later.
launch c8-restart-later offer101 manual GPUI_RESET=1 APPIMAGE=$U/feeds/Installed.AppImage
w=$(wait_alert 1) && press "$w" Return
w=$(wait_alert 2) && { shot c8; press "$w" click:170,140; }; sleep 1; stop
echo "STATE-BEFORE $(ls "$GPUI_STATE" | tr '\n' ' ')" >> "$GPUI_MARKER"
# 8, next launch: same state directory. The plan expects the restart offer.
export GPUI_MARKER=$OUT/c8-relaunch.marker; rm -f "$GPUI_MARKER"
env GPUI_CONFIG=$U/feeds/config-offer101.json GPUI_MODE=auto APPIMAGE=$U/feeds/Installed.AppImage "$APP" > $OUT/c8-relaunch.log 2>&1 &
APP_PID=$!
w=$(wait_alert 1) && { shot c8-relaunch; press "$w" click:170,140; }; sleep 1; stop
# Option A (#4462): the unapplied download and its state are gone.
echo "STATE-AFTER $(ls "$GPUI_STATE" | tr '\n' ' ')" >> "$GPUI_MARKER"
