-- Lays out the Finder window of a mounted read-write DMG volume so Finder writes
-- the volume's .DS_Store. It only addresses the disk mounted at the given path;
-- it does not touch any other window, volume or application.
--
-- Arguments: mountPath appName windowX windowY windowWidth windowHeight
--            iconSize textSize appX appY applicationsName applicationsX
--            applicationsY backgroundName noticeName noticeX noticeY
-- Empty applicationsName, backgroundName or noticeName skip that item.
on run argv
	set mountPath to item 1 of argv
	set appName to item 2 of argv
	set windowX to (item 3 of argv) as integer
	set windowY to (item 4 of argv) as integer
	set windowWidth to (item 5 of argv) as integer
	set windowHeight to (item 6 of argv) as integer
	set iconSize to (item 7 of argv) as integer
	set textSize to (item 8 of argv) as integer
	set appX to (item 9 of argv) as integer
	set appY to (item 10 of argv) as integer
	set applicationsName to item 11 of argv
	set applicationsX to (item 12 of argv) as integer
	set applicationsY to (item 13 of argv) as integer
	set backgroundName to item 14 of argv
	set noticeName to item 15 of argv
	set noticeX to (item 16 of argv) as integer
	set noticeY to (item 17 of argv) as integer

	set mountAlias to (POSIX file mountPath) as alias
	set backgroundAlias to missing value
	if backgroundName is not "" then
		set backgroundAlias to (POSIX file (mountPath & "/.background/" & backgroundName)) as alias
	end if
	tell application "Finder"
		set theDisk to item mountAlias
		open theDisk
		set theWindow to container window of theDisk
		set current view of theWindow to icon view
		set toolbar visible of theWindow to false
		set statusbar visible of theWindow to false
		set bounds of theWindow to {windowX, windowY, windowX + windowWidth, windowY + windowHeight}
		set theOptions to icon view options of theWindow
		set arrangement of theOptions to not arranged
		set icon size of theOptions to iconSize
		set text size of theOptions to textSize
		if backgroundAlias is not missing value then
			set background picture of theOptions to backgroundAlias
		end if
		set position of item appName of theDisk to {appX, appY}
		if applicationsName is not "" then
			set position of item applicationsName of theDisk to {applicationsX, applicationsY}
		end if
		if noticeName is not "" then
			set position of item noticeName of theDisk to {noticeX, noticeY}
		end if
		close theWindow
		open theDisk
		update theDisk without registering applications
		delay 1
		close container window of theDisk
	end tell
end run
