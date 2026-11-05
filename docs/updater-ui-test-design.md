# Updater Dialog Tests (proposed)

Status: plan for v0.1.10. Not implemented.

## Gap

The signed-update path is tested end to end below the user interface. The
helper's prepare and apply phases, the AppImage replacement and the MSI install
with relaunch all run in CI and locally (see #108). The dialogs that
`GPStandardUpdaterController` shows are not:

| Dialog | Buttons | What a button does |
| --- | --- | --- |
| "Version X is available" | Install Update, Later, Skip This Version (or More…) | prepare, then quit and apply; nothing; store the skipped version |
| More… | View Changes, Back, Skip This Version | open the release notes through `xdg-open` / the shell |
| "X is up to date" | OK | nothing |
| "Update Check Failed" | OK | shows the helper's or the check's error |
| "Restart to Finish Updating" | Restart and Install, Later | apply with `--wait-pid`, then quit |
| Previous-install outcome at the next launch | OK | shows the failure a quit-and-apply left behind |

Bugs here reach users directly. #94's duplicate offer after Install Update was
one: only a manual reproduction caught it.

## Approach

Drive a real packaged app under a private X server, the same way the smoke
launch does, and press the dialog buttons with synthetic key events.

- **Fixture app.** A small GNUstep app in `tests/fixtures/updater-ui/` that
  links GPUpdaterUI, puts "Check for Updates…" in its menu, bundles
  `gp-update-helper`, and writes one line per event to a marker file: launched
  with its version, the check result, the dialog shown, and quit. It's packaged
  as an AppImage at 1.0.0 and 1.0.1, with updates on and a throwaway key, like
  the end-to-end run in #108.
- **Triggering a check.** `startupDelaySeconds: 1` and
  `minimumCheckIntervalHours: 0` in the fixture manifest, with
  `GP_UPDATER_FEED_URL` pointing at a `file://` feed. No test hooks go into the
  controller.
- **Display.** `xvfb-run` in CI. Locally, `scripts/run-gui-isolated.sh`, which
  also binds a scratch home, so a dialog test never touches the real defaults.
- **Finding and answering dialogs.** `xwininfo -root -tree` lists the alert
  panels; `Get-GpAppImageSmokeAlertWindows` already does this for the smoke
  launch. The panel title and message come from `xprop WM_NAME` and the
  fixture's marker line, and `xdotool key --window <id> Return|Escape|Tab`
  presses a button. NSAlert's first button is the default, and Escape is
  Cancel. A screenshot (`import -window root`) is kept as a CI artifact when a
  step fails.
- **Assertions.** They come from the marker file, the helper's state file and
  the installed AppImage's version, never from pixel matching.

## Cases

1. Up to date: the feed's newest version is the installed one. The "up to date"
   dialog appears only for a check by hand; an automatic check stays quiet.
2. Install Update: prepare, then quit, apply and relaunch. The marker shows 1.0.1
   launched, and the installed AppImage is 1.0.1. Exactly one offer is shown
   (#94).
3. Later: no download, and the next automatic check offers it again.
4. Skip This Version: the next check is quiet for 1.0.1 and offers 1.0.2.
5. More…, then View Changes: `xdg-open` receives the release-notes URL with the
   host's environment (#105's wrapper; a fake `xdg-open` records it).
6. Refused update: a tampered asset or an altered versionSignature. The helper
   fails, "Update Check Failed" (or the apply outcome) shows the helper's
   message, and nothing is installed.
7. No build for this machine (#107): the error names the platform.
8. Restart to Finish Updating, Later: the update stays prepared, and the next
   launch offers the restart again.
9. A failed apply (an unwritable target folder): the next launch shows the
   outcome dialog with the apply script's reason.

## Windows

The same cases for the MSI, on `windows-latest`, are a second step. NSAlert on
the win32 backend is a native window, so UI Automation (PowerShell
`System.Windows.Automation`) can find it by title and invoke the buttons. The
MSI end-to-end job in `msi-update-e2e` is the starting point.

## Cost and order

About a day for the Linux fixture and cases 1 to 6 in a new CI job, and half a
day more for 7 to 9. Windows follows separately. The fixture app is the larger
part; the driver reuses the smoke launch's X handling.
