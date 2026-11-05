# Review: libs-gui patch 1

**Item:** libs-gui 0001, "GSTheme: let a theme turn GNUstep-drawn window decorations on"
**Commit:** `bd5a9830b1443c41bcf1b26ef7e48df6c6614764`
**Base:** libs-gui master `549f63913` (unchanged since 2026-10-02; current on 2026-10-07)
**Where:** branch `ai-policy/theme-backend-defaults` in `~/git/gnustep/libs-gui-series`; patch file `Docs/upstream-patches/libs-gui/0001-GSTheme-let-a-theme-turn-GNUstep-drawn-window-decora.patch`
**Files:** `Source/GSTheme.m` (+143 −31), `Source/GSThemePrivate.h` (+11), `Source/NSApplication.m` (+5), `ChangeLog` (+20), `Tests/gui/GSTheme/backendDefaults.m` (new, 190 lines), `Tests/gui/GSTheme/TestInfo` (new, empty)

This is the version to sign off on. Master hasn't moved since the commit was made, so the series commit is already the standalone one: it stands alone and goes as its own pull request. Every statement in its message was checked (below); none needed changing.

It is independent of the libs-back patches: it only decides the value of `GSBackHandlesWindowDecorations` that the backend reads.

Prepared under `Docs/UPSTREAM_POLICY.md`. Nothing has been sent.

## The problem

A theme that draws the window decorations itself (the Adwaita theme's header bar) needs `GSBackHandlesWindowDecorations` NO. It can set that in the `GSThemeDomain` of its Info.plist, but the backend reads the default when the display server is created in `-[NSApplication _init]`, before the theme is loaded and its domain installed. So the theme's value always arrives too late, and every user has to set the default by hand.

## The fix, hunk by hunk

1. **`GSThemePathForFileName()` (new, `GSTheme.m`).** The theme bundle lookup from `+loadThemeNamed:` (an absolute path, or `Themes/<name>` in the standard Library directories), moved into a function so both callers use the same lookup. `+loadThemeNamed:` now calls it; its behaviour is unchanged.
2. **`GSDefaultSetAboveRegistration()` (new).** Whether any domain in the search list other than the registration domain (and `GSThemeDomain`) sets a key: the user's choice, on the command line or in the defaults, as opposed to a value an app or library registered.
3. **`GSThemeInstallBackendDefaults()` (new).** In order, it returns without doing anything when:
   - the user set `GSBackHandlesWindowDecorations` or `GSX11HandlesWindowDecorations` (step 2);
   - a theme has already put its domain in place;
   - `GSTheme` is unset or names the GNUstep theme;
   - the theme can't be found, or its `GSThemeDomain` doesn't set the default.

   Otherwise it reads the theme's Info.plist without loading its code and installs `GSBackHandlesWindowDecorations` alone as the `GSThemeDomain` volatile domain. It puts that domain in the search list where `-[GSTheme activate]` would: before `GSConfigDomain`, else before the registration domain, else at the end. Compared with `-activate`'s code on 2026-10-07: the same logic. When the theme is activated later, its whole domain replaces this one.
4. **`GSThemePrivate.h`.** The declaration, with a comment.
5. **`NSApplication.m`.** The call, in `-_init`, after `initialize_gnustep_backend()` and the user bundles, just before `[GSDisplayServer serverWithAttributes: nil]`.

## Who this affects

Users of a theme whose `GSThemeDomain` sets `GSBackHandlesWindowDecorations`: they get its value without setting it themselves. Nothing changes for the GNUstep theme, for themes that don't set it, or for anyone who set either default.

## The test: `Tests/gui/GSTheme/backendDefaults.m`

- **What it does:** it makes two theme bundles in a temporary directory, one with the default in its `GSThemeDomain` and one without, names them by absolute path in `GSTheme`, and calls the function directly, so it needs no display. Defaults are set in the argument domain, for the test process only. 11 checks:
  - **Installs nothing:** no `GSTheme`, the GNUstep theme, the user's value for either default, a theme without the default, a theme that isn't there.
  - **Installs the value:** alone in `GSThemeDomain`; it reads back NO although YES is registered; the domain appears once in the search list, above the registration domain; a second call changes nothing.
  - **Lookup:** `+loadThemeNamed:` still finds a theme by path.
- **Why that is enough:** each early return has a case, and the positive case checks the value, the domain's contents and its place in the search list. The registered-YES case is the one that would catch a check that counted registered values as the user's. The earlier draft had exactly that bug: it tested `-objectForKey:`, as the `-csd` worktree still shows.
- **Not covered by the test:** the call site in `-[NSApplication _init]`. The run below covers it.

## Results, each run on 2026-10-07

Private Xvfb (`:152`, `:153`, `:154`), a GNUstep.conf copy (mode 600) with empty user defaults, libs-base 1.31.1; each tree built with `make ADDITIONAL_OBJCFLAGS=-Wno-error=format-security` (as master needs), and the suites run with libs-gui's own `make check`.

| Check | Master `549f639` | With the patch (`bd5a983`) |
|---|---|---|
| `Tests/gui/GSTheme/backendDefaults.m` | doesn't link (`GSThemeInstallBackendDefaults` doesn't exist) | 11 of 11 pass |
| Whole libs-gui suite | 4819 passed; 33 failed tests, 2 aborted files, 1 dashed hope | 4829 passed; the same 33, 2 and 1, plus "Can create link from pasteboard" (NSDataLink), see below |
| `gui/NSDataLink` alone | 101 passed, 0 failed | 101 passed, 0 failed (twice) |
| `gcc-syntax-check.sh` | — | clean (canary rejected): `GSTheme.m`, `NSApplication.m` (only diagnostics it had before), `backendDefaults.m` |
| An app, empty defaults, `-GSTheme Adwaita` (the installed theme, whose `GSThemeDomain` sets the default NO) | the window manager draws the decorations | the gui draws them (header bar) |
| The same with `-GSBackHandlesWindowDecorations YES` | the window manager draws | the window manager draws |
| `-GSTheme GNUstep` | the window manager draws | the window manager draws |

- **The NSDataLink failure** is an artefact of running both suites at once: they share the user's pasteboard server. Run alone, the directory passes on both trees.
- **Suite totals:** 10 more passes is the new test's 11 checks, less that one NSDataLink check. The other failures are in master already; the patch adds none.
- **The app:** a small program that prints `-[GSDisplayServer handlesWindowDecorations]`, run against each build with `LD_LIBRARY_PATH` (`ldd` confirmed which libs-gui it used). It checks the call site end to end.

## Statements in the commit message, checked

| Statement | How checked |
|---|---|
| The backend reads the default when the server is created, before the theme loads | `-_init` order; read |
| Installed just before the server is created | the call site; read |
| Without loading the theme's code | reads the bundle's `infoDictionary` only; read |
| Only `GSBackHandlesWindowDecorations` | the test's "alone in GSThemeDomain" check |
| Placed where `-activate` puts it, above the registration domain | the same insertion code as `-activate`; read; and the test |
| Nothing installed for a user's value (either default), a theme already in place, the GNUstep theme, a missing theme or no default | the test's negative cases; the app run |
| The lookup moved into `GSThemePathForFileName()` | the diff; the test's `+loadThemeNamed:` check |
| Without the change the test doesn't run; with it 11 pass | run, above |
| An earlier draft tested `-objectForKey:` | `~/git/gnustep/libs-gui-csd`, `GSThemeInstallBackendDefaults()` |

## Risks and open points

- **It reads the theme's Info.plist twice:** once here, once when the theme loads. That's cheap, and only when `GSTheme` names a theme.
- **Only one key.** A maintainer might ask for a general mechanism, such as any `GSBack*` key, or a list in the theme. This patch keeps to the one key that has to be read early.
- **A theme named by a relative path with directories** is reduced to its last component, as `+loadThemeNamed:` does for lookup. That is consistent, but worth knowing if asked.

## Questions to be able to answer

- Why not load the theme earlier? *Loading a theme loads its code and activates it, which needs a display server for images and colours; reading one key from its Info.plist doesn't.*
- Why ignore registered values? *Apps and libraries register defaults as fallbacks. Only a value the user set should beat the theme's.*

## To check it yourself

```
cd ~/git/gnustep/libs-gui-series
git show bd5a983
```

## Sign-off

If you approve this exact version, say so in the chat ("I approve libs-gui-0001") and Claude records it, or add this row to `Docs/UPSTREAM_SIGNOFF.md` yourself:

```
| <date> | libs-gui 0001 | bd5a9830b1443c41bcf1b26ef7e48df6c6614764 | | |
```

## The patch, as it would be sent

`Docs/upstream-patches/libs-gui/0001-GSTheme-let-a-theme-turn-GNUstep-drawn-window-decora.patch` (`git am` onto `549f63913` gives the same tree).
