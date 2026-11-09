# AppImage RUNPATH Design (proposed)

Status: proposed as an opt-in. Not scheduled and not implemented.

## Problem

`AppRun` puts the bundled library directories on `LD_LIBRARY_PATH` and exports
it. Every process the app starts inherits it. A host browser opened through
`xdg-open`, the shell in a packaged Terminal, or an app launched from a
packaged GWorkspace then loads our libraries before its own. The bundle holds
the libraries that do the most harm there: `libssl`, `libgnutls`,
`libp11-kit`, `libGL`/`libGLX`/`libGLdispatch`, `libdrm`, `libstdc++`,
`libgcc_s` and ICU.

Since v0.1.9, `AppRun` saves the caller's environment as `GP_HOST_*`, and
the bundled `gp-bin/xdg-open` restores it (see "AppImage: the Caller's
Environment" in `launch-contract.md`). That covers opening URLs and files, and
an app can restore the same way for programs it starts itself, but nothing
does it for them automatically. This document is about
removing the bundled paths from the environment altogether.

## Proposal

Add an opt-in `backends.appimage.runpath: "origin"`. When it's set:

1. At package time, set `DT_RUNPATH` on every staged ELF that has a dynamic
   section. The value is `$ORIGIN`-relative paths from the file to the
   runtime library directories (`runtime/lib`,
   `runtime/System/Library/Libraries`).
2. Leave those directories out of the `LD_LIBRARY_PATH` that `AppRun`
   exports.
3. Run strict runtime-closure validation with `ldd` and no `LD_LIBRARY_PATH`,
   so a missing RUNPATH shows up as an unresolved dependency.

Make it the default only after a release in which it was opt-in.

## Which files

Measured on the Gorm example's stage (2026-11-05): 226 ELF files.

- 179 in `runtime/lib`
- 10 in `runtime/System/Library/Libraries`
- 4 tools
- about 30 bundles, plugins and frameworks that GNUstep loads with `dlopen`,
  at various depths (`*.plugin`, ColorPickers, Services, PreferencePanes, the
  `gnustep-back` bundle)

Only 2 already carried a RUNPATH (`$ORIGIN`): `libdispatch` and `librabbitmq`.

`DT_RUNPATH` applies only to an object's own direct dependencies. Each of these
files therefore needs its own RUNPATH, with a relative path for its depth.
Setting it on the executable alone isn't enough.

## Risks

- **Lookup order.** The loader searches `LD_LIBRARY_PATH` before `DT_RUNPATH`,
  so a user's own `LD_LIBRARY_PATH` would now take precedence over the bundled
  libraries. Today the bundled ones come first. `DT_RPATH` (`--force-rpath`)
  would keep them first, but it is deprecated and applies to transitive
  lookups. Use RUNPATH, and keep the manifest opt-out.
- **Loading by name.** `dlopen` by bare name (gnutls loading p11-kit modules,
  glvnd loading the host GL vendor library) searches the calling object's
  RUNPATH, so the caller needs one too. NSBundle loads by absolute path, which
  is unaffected. Test GL on Fedora.
- **patchelf.** Older versions have corrupted binaries when growing the dynamic
  section. Require patchelf 0.18 or newer, and check each patched file with
  `readelf` and with `ldd` without `LD_LIBRARY_PATH`.
- **Hashes.** Patched files change hash but keep their build ID
  (see `manifest.md`). Provenance and update feeds are computed after staging,
  so they're unaffected. The MSI and DMG backends aren't touched.
- **Hosts.** Packaging hosts need patchelf: an apt package on Ubuntu runners,
  added to the AppImage backend's host dependencies.

## Testing

- Pester, on fixture ELFs: the RUNPATH string for each depth; that the
  validator flags a missing RUNPATH when `LD_LIBRARY_PATH` is unset; and that
  files which already have `$ORIGIN` come out unchanged.
- The `examples/downstream/gnustep-apps` setups and ScreenshotTool, rebuilt
  with the option on: the smoke runs and screenshots under
  `scripts/run-gui-isolated.sh`.
- Clean-smoke containers (`ubuntu:24.04`, `fedora:42`) through
  `appimage-clean-smoke-image`, including GL on Fedora.
- The `xdg-open` test from v0.1.9: no bundled paths in the child's
  `LD_LIBRARY_PATH`.
- A startup with `LD_DEBUG=libs`, to confirm libraries resolve through
  RUNPATH.

## Cost

About a day of agent time including tests, plus CI runs.
