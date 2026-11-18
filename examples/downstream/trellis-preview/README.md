# TrellisPreview AppImage (draft recipe)

A packaging recipe for [Trellis](https://github.com/danjboyd/gnustep-trellis)'s
`TrellisPreview.app`, staged with the Adwaita GNUstep theme. It is kept here
until it qualifies, and then moves to a `packaging/` folder in gnustep-trellis
(the manifest's paths assume that folder).

- **Source:** Trellis v0.10.1 (`4ea11c965b8b7c9a6d2a4a4a93aa15043694a5de`), built
  with `make hot_reload=no`.
- **Theme:** Adwaita at `9c25a6823c3d0af715b197e64e8ca2d9bee9b456`, the commit
  Trellis CI tests. Its light/dark appearance switch is Adwaita's own. The
  stage script copies its `COPYING.LIB` and `THIRD-PARTY-NOTICES` (some of its
  icons are GNOME's, under LGPL-3 / CC-BY-SA) into the package's notices.
- **Runtime:** the gnustep-cli-new toolchain the workflow sets up; libTrellis and
  libTrellisEngine go to `runtime/lib`. The tools (trellis-render, -lint) stay
  out: trellis-render refuses to run outside a private display.

Render fidelity was checked before packaging: TrellisPreview's `--snapshot` and
`trellis-render` matched pixel for pixel (0 differing) on Settings 520x400,
Dashboard 640x480 and QueueMockup 900x640, light and dark, under Adwaita.
