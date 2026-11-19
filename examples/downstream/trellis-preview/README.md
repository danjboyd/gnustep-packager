# TrellisPreview AppImage and MSI (draft recipe)

A packaging recipe for [Trellis](https://github.com/danjboyd/gnustep-trellis)'s
`TrellisPreview.app`, staged with the Adwaita GNUstep theme on Linux and
WinUITheme on Windows. It is kept here
until it qualifies, and then moves to a `packaging/` folder in gnustep-trellis
(the manifest's paths assume that folder).

- **Source:** Trellis v0.10.1 (`4ea11c965b8b7c9a6d2a4a4a93aa15043694a5de`), built
  with `make hot_reload=no`.
- **Theme:** Adwaita at `9c25a6823c3d0af715b197e64e8ca2d9bee9b456`, the commit
  Trellis CI tests. Its light/dark appearance switch is Adwaita's own. The
  stage script copies its `COPYING.LIB` and `THIRD-PARTY-NOTICES` (some of its
  icons are GNOME's, under LGPL-3 / CC-BY-SA) into the package's notices.
  AppImage only: Adwaita's GNOME adapters (X11 window manager, portal file
  chooser and print dialog) don't compile on MinGW.
- **Windows theme:** WinUITheme at `72f2a10743e5a441a2d4b4e36e03ce150da3caab`,
  the commit Workforce's MSI ships. The Windows stage script copies its
  `COPYING.LIB`; `platformOverrides.windows.compliance` lists it in place of
  Adwaita's notices.
- **Runtime:** the gnustep-cli-new toolchain the workflow sets up; libTrellis and
  libTrellisEngine go to `runtime/lib`. The tools (trellis-render, -lint) stay
  out: trellis-render refuses to run outside a private display.

- **Windows (MSI):** the same manifest, with `platformOverrides.windows` for the
  pwsh build and stage scripts. `package-msi.yml` uses gnustep-cli v0.1.9's
  patched toolchain (`toolchain-variant: patched`, packager PR 167), the whole
  stack, never mixed with MSYS2's own gnustep packages. The backend is
  gnustep-back's win32 server with cairo graphics and fontconfig, with DejaVu
  bundled. Trellis has not been built on Windows yet; gnustep-cssbox owns the
  source changes.
- **Run environment:** a scratch or packaged run must point gnustep-base at the
  toolchain's own `GNUstep.conf` (`GNUSTEP_CONFIG_FILE`), or the host's is read.
- **Not included:** a `.trellis` file association (Dan's call in the release
  proposal) and a real icon (gnustep-cssbox will supply `TrellisPreview.png`).

Render fidelity was checked before packaging: TrellisPreview's `--snapshot` and
`trellis-render` matched pixel for pixel (0 differing) on Settings 520x400,
Dashboard 640x480 and QueueMockup 900x640, light and dark, under Adwaita.
