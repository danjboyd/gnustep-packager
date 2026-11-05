# Design Notes

## V1 Visual Target

1. Stock Adwaita only.
2. Theme code owns rendering decisions.
3. GTK4 is not used as the renderer.
4. The theme should prefer GNOME settings for fonts and appearance variants.

## Repository Intent

This repository is split into three implementation concerns:

1. `Source/Settings/`
   Reads GNOME settings and turns them into normalized theme inputs.
2. `Source/Rendering/`
   Builds the system palette and later the manual Adwaita-inspired drawing
   layer.
3. `Examples/ThemeDemo/`
   Gives the theme a stable target application for regression work.

## Phase 0-3 Decisions

1. Start with a buildable theme bundle and a buildable demo app.
2. Make typography and metrics the first real implementation milestone.
3. Avoid `libs-gui` changes until the theme layer clearly cannot fix menu
   typography and density well enough.
4. Keep resource assets optional in the first pass. Code and metrics matter more
   than shipped images in the opening phases.

## Current Implementation Status

1. Phase 0 is in place:
   repo skeleton, top-level `GNUmakefile`, build-artifact `.gitignore`, and
   `AdwaitaInfo.plist`.
2. Phase 1 is accepted:
   `Examples/ThemeDemo/` now covers controls, text/input widgets, table view,
   outline view, menus, scrollbars, and a stress page. `Tests/Scripts/` now
   gives both demo apps deterministic screenshot capture with per-run window
   titles, so the harness is reliable enough for visual regression work.
3. Phase 2 is in place:
   `Reference/AdwaitaDemo/` now provides a libadwaita comparison harness and a
   metrics dump path for native GNOME control sizes.
4. Phase 3 is in place:
   `Source/Settings/` reads GNOME interface font, monospace font, GTK theme
   name, color-scheme preference, and infers high-contrast/dark variants.
5. Phase 4 is accepted:
   runtime defaults now set the relevant font roles and core geometry values,
   the theme applies an Adwaita-oriented font scale, and the visual pass
   against `Reference/AdwaitaDemo/` shows that menu sizing, form density, and
   long-label handling are acceptable without a `libs-gui` patch.
6. Phase 5 is accepted:
   `Source/Rendering/GnomeThemeControls.m` now owns the Adwaita-inspired
   rendering for buttons, checkboxes, radios, text field centering, sliders,
   progress indicators, scrollers, pop-up affordances, steppers, segmented
   controls, and the top-tab treatment used by `ThemeDemo`.
7. The next visual work now belongs to Phases 6 and 7:
   the remaining obvious mismatches are menu-specific styling plus data-view
   chrome such as table headers, row selection, outline indicators, and the
   broader scroll view/table system rather than core control rendering.

## Open Technical Risks

1. GNOME settings schemas may differ across systems, so the settings bridge
   needs safe fallbacks.
2. Popup menu screenshot capture under Xwayland/Mutter is still less reliable
   than normal window capture, so popup-menu-specific regressions should be
   checked manually until a better root/window capture path is added.
3. `libs-gui` is still deferred:
   after the Phase 5 pass, the remaining blockers are no longer obvious theme
   layer failures in core controls, so any future `libs-gui` work should be
   justified against a specific Phase 6 or Phase 7 blocker.
