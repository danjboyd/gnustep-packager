# Updater Dialog Tests (proposed)

Status: plan for v0.1.10. Cases 1 and 3–8 ran locally on 2026-11-06 (below); no CI job yet.

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

## Local run, 2026-11-06

`tests/fixtures/updater-ui/run-local.sh WORKDIR` builds GPUpdaterCore,
GPUpdaterUI, `gp-update-helper` and a fixture app (`main.m`) against the host's
GNUstep. It makes signed `file://` feeds with the published test key, then runs
the cases in `run-cases.sh` under `scripts/run-gui-isolated.sh`: a private X
server, a private session bus, and a scratch home, so skipped versions and
other defaults go to scratch.

The fixture isn't packaged: it runs the libraries directly, with `APPIMAGE`
pointing at a stand-in file. It logs each NSAlert's text and buttons, and the
button that closed it. The driver clicks the panel, which gives it keyboard
focus, then presses Return or Tab and space, or clicks a button. Without the
first click, synthetic keys don't reach the panel under Xvfb.

Host: Debian 13, GNUstep from `/usr/GNUstep` (base 1.31, gui 0.32), Xvfb.

| Case | Result |
| --- | --- |
| 1 Up to date, manual check | Pass: "is up to date", OK |
| 1 Up to date, automatic check | Pass: no alert |
| 3 Later, then the next automatic check | Pass: offered again |
| 4 Skip This Version | Pass: the next automatic check is quiet for 1.0.1 (status skipped) and offers 1.0.2 |
| 5 More…, then View Changes | **Fails here**: `xdg-open` is never called, and the first alert doesn't come back. The app sits idle in `poll` for at least 28 s. |
| 6 Tampered asset, Install Update | Pass: the helper refuses it, and the app shows "Downloaded update failed verification." |
| 6 Feed can't be read | Pass: "Update Check Failed" with the reason |
| 7 No build for this machine | Pass: "…has no download for this computer (linux-x64)." |
| 8 Restart to Finish Updating, Later | Prepares and shows the restart offer: pass. On the next launch with the same state directory, the app offers "1.0.1 is available" again, not the restart. |

Findings, not fixed here:

- **View Changes (case 5).** On Linux, `GPUpdaterUIOpenURL` calls
  `-[NSWorkspace openURL:]`, not `xdg-open`. On this host that call doesn't
  return within the test, and the first alert never comes back. It isn't known
  yet whether a packaged AppImage, with gdnc, gpbs and the #105 `xdg-open`
  wrapper, behaves the same. If it does, the fix is to call `xdg-open` (through
  the wrapper) on Linux.
- **Restart after Later (case 8).** A prepared update isn't offered for
  restart at the next launch: the controller checks again and offers a fresh
  Install Update. The download stays in the state directory. The plan expected
  the restart offer. Which one is intended is a product decision.
- **Wording (case 6).** A verification failure after Install Update is titled
  "Update Check Failed", though the check itself succeeded.

Not run:

- **Case 2 (Install Update through to relaunch) and case 9 (a failed apply).**
  Both replace and relaunch a real AppImage, so they need the packaged fixture
  and the CI job.
- **Windows.**
- **Two runs of an earlier draft** had one launch that didn't start within 20 s,
  right after a case 5 run that had stalled. The CI job should run each case in a
  new isolated session.

## Windows

The same cases for the MSI, on `windows-latest`, are a second step. NSAlert on
the win32 backend is a native window, so UI Automation (PowerShell
`System.Windows.Automation`) can find it by title and invoke the buttons. The
MSI end-to-end job in `msi-update-e2e` is the starting point.

## Cost and order

The fixture and driver exist now (`tests/fixtures/updater-ui/`). What's left
for CI: package the fixture as an AppImage, run cases 2 and 9 against it, and
put `run-cases.sh` in a job. That's about half a day, once the case 5 and
case 8 questions are settled. Windows follows separately. The fixture app is the larger
part; the driver reuses the smoke launch's X handling.
