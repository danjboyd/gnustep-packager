# GNUstep Adwaita Theme Implementation Roadmap

## Target

Build a GNUstep theme that feels at home on a modern GNOME system by targeting
stock Adwaita for v1.

This roadmap assumes:

1. The theme is code-based.
2. The renderer is not GTK4 snapshot rendering.
3. The first implementation should avoid `libs-gui` patches unless the theme
   layer cannot deliver acceptable menu typography and spacing.
4. A reference app is part of the project, not an afterthought.

## V1 Goals

1. Match the visual language of stock Adwaita closely enough that GNUstep apps
   no longer look out of place on GNOME.
2. Fix the most obvious GNUstep mismatches first: menu typography, menu row
   height, control spacing, scrollbars, focus states, and form density.
3. Pull in current GNOME settings where practical:
   font family and size, monospace font, light/dark preference, and high
   contrast if available.
4. Keep the initial scope inside the theme repository unless a clear technical
   blocker forces a `libs-gui` change.

## Explicit Non-Goals For V1

1. Support arbitrary third-party GTK themes.
2. Reuse GTK4 as the rendering engine.
3. Implement GNOME header bars or full client-side window decoration parity.
4. Solve every GNUstep widget before shipping a useful first version.

## Proposed Repository Layout

```text
plugins-themes-adwaita/
  Docs/
    IMPLEMENTATION_ROADMAP.md
    DesignNotes.md
  Source/
    GnomeTheme.h
    GnomeTheme.m
    Settings/
    Rendering/
    Adapters/
  Resources/
    Info-gnustep.plist
    ThemeColors.clr
    ThemeImages/
    ThemeTiles/
  Examples/
    ThemeDemo/
  Reference/
    AdwaitaDemo/
  Tests/
    Screenshots/
    Scripts/
```

`Resources/` should stay small and intentional. Static assets should fill gaps
in GNUstep-specific controls, not become the primary rendering strategy.

## Phase 0: Foundation And Constraints

### Scope

Set the project direction and create the minimum repo structure needed to work
without churn.

### Deliverables

1. GNUmakefile skeleton for a `.theme` bundle.
2. Empty `Source/`, `Resources/`, `Examples/ThemeDemo/`, and `Tests/`
   directories.
3. Initial `Info-gnustep.plist` with only the settings that are already known.
4. Design notes capturing the Adwaita references to follow.

### Exit Criteria

1. The repo builds an installable empty theme bundle.
2. The theme can be selected by GNUstep without crashing.
3. The project layout is stable enough to begin implementation.

## Phase 1: Reference App First

### Scope

Build a theme-agnostic demo app that exposes the widgets and layouts needed to
drive theme work.

### Deliverables

1. A `ThemeDemo` application under `Examples/ThemeDemo/`.
2. Demo pages for:
   - menus
   - typography and spacing
   - buttons and form controls
   - text fields and text views
   - sliders and progress indicators
   - table view, outline view, and scroll views
   - tab views and pop-up buttons
3. A stress page with:
   - long labels
   - long menu item titles
   - key equivalents
   - dense forms
   - disabled and mixed states
4. A simple scripted launch flow for capturing screenshots manually.

### Exit Criteria

1. Theme work can be evaluated without relying on unrelated applications.
2. The demo app covers every widget class planned for v1.
3. The demo app can be used as the basis for later screenshot regression tests.

## Phase 2: Adwaita Reference Harness

### Scope

Build a small Adwaita-native comparison app that acts as the visual target for
the GNUstep theme work.

### Deliverables

1. A `Reference/AdwaitaDemo/` application, preferably in Python with
   PyGObject + libadwaita.
2. Pages that mirror the GNUstep `ThemeDemo` closely enough to compare:
   - controls
   - text inputs
   - data views
   - menu or popover interactions
   - dense and long-label stress cases
3. Shared content strategy with the GNUstep demo:
   - same labels where practical
   - same control ordering where practical
   - same stress strings and dense-form cases
4. A simple screenshot flow so the Adwaita app can be captured alongside the
   GNUstep demo.

### Notes

1. This app is a design oracle, not a rendering dependency.
2. Prefer libadwaita over plain GTK4 because the visual target is stock GNOME,
   not raw GTK widgets in isolation.
3. Do not force false equivalence where GNOME patterns differ from GNUstep:
   menu comparisons should be native-adjacent, not a literal reproduction of a
   traditional in-window menu bar.

### Exit Criteria

1. The project has a concrete Adwaita baseline instead of relying on memory.
2. Typography, spacing, and control density can be compared page-by-page.
3. Later phases can use paired screenshots as the primary acceptance check.

## Phase 3: GNOME Settings Bridge

### Scope

Import the minimum GNOME settings required to get typography and color variant
selection right.

### Deliverables

1. A settings component that reads:
   - interface font
   - monospace font
   - color scheme preference
   - high contrast preference if practical
2. Caching and refresh logic for theme activation.
3. A single internal representation of:
   - family names
   - point sizes
   - dark/light mode
   - contrast mode

### Notes

This phase should avoid pulling in broad desktop dependencies unless they are
stable and justified. Prefer a narrow settings bridge over a full toolkit
integration layer.

### Exit Criteria

1. The theme can resolve the current GNOME text settings reliably.
2. Dark/light selection can be mapped to theme appearance.
3. Settings loading is deterministic and cheap enough to use on activation.

## Phase 4: Typography And Metrics

### Scope

Make the theme feel correct before chasing pixel polish.

### Deliverables

1. Theme-controlled defaults for:
   - menu bar height
   - menu item height
   - menu separator height
   - scroller width
2. Runtime font assignment for:
   - user font
   - fixed-pitch font
   - menu font if possible from theme-only mechanisms
   - menu bar font if possible from theme-only mechanisms
3. Adwaita-inspired spacing values for:
   - menus
   - form controls
   - pop-up buttons
   - tabs
   - text fields

### Decision Gate

At the end of this phase, answer the following:

1. Can menu fonts and row heights be made acceptably close to Adwaita from the
   theme layer alone?
2. Can menu horizontal density be relaxed enough without changing `libs-gui`?

If both answers are yes, continue.

If either answer is no, open a small, isolated `libs-gui` investigation before
Phase 5. The likely problem areas are menu font role propagation and hard-coded
menu padding.

### Exit Criteria

1. Menus no longer read as undersized or cramped.
2. Dense forms no longer look visibly tighter than equivalent Adwaita forms.
3. The demo app shows acceptable typography before custom control painting is
   considered complete.

## Phase 5: Core Control Rendering

### Scope

Implement manual Adwaita-inspired rendering for the controls that matter most.

### Deliverables

1. Buttons:
   - push buttons
   - default buttons
   - disabled states
   - highlighted states
2. Selection controls:
   - checkboxes
   - radio buttons
   - mixed states
3. Text inputs:
   - text fields
   - focus ring behavior
   - disabled/read-only appearance where supported
4. Range controls:
   - sliders
   - progress indicators
   - scrollbars
5. Pop-up buttons and segmented controls if needed for parity in the demo app.

### Exit Criteria

1. Core controls are visually coherent as a family.
2. The controls fit the typography and spacing established in Phase 4.
3. No control still looks like a default GNUstep widget inside the demo app
   unless it is intentionally deferred.

## Phase 6: Menu System Polish

### Scope

Bring menus up to the standard expected on GNOME.

### Deliverables

1. Menu background and selection rendering.
2. Separator rendering.
3. Submenu arrow appearance.
4. Checkmark and radio indicator appearance.
5. Disabled, highlighted, and inactive states.
6. Key equivalent legibility.
7. Side-by-side comparison against the Adwaita reference harness for menu
   density and visual rhythm.

### Notes

This phase is separate from Phase 4 because menu visual styling should not mask
layout failures. The spacing and font issues need to be solved before visual
menu polish starts.

### Exit Criteria

1. Menus are readable and visually balanced in normal and stress cases.
2. Long menu items, submenu arrows, and key equivalents all align acceptably.
3. Menu selection no longer looks out of place beside GTK apps on Adwaita.

## Phase 7: Data Views And Secondary Widgets

### Scope

Handle the widgets that users see in real applications after the basics land.

### Deliverables

1. Table headers and table selection styling.
2. Outline view branch indicators if needed.
3. Tab view styling.
4. Optional toolbar and path control refinements if they are important in the
   demo app or target applications.

### Exit Criteria

1. Data-heavy demo pages look coherent with the rest of the theme.
2. Secondary widgets do not break the illusion created by the core controls.

## Phase 8: Variant Support

### Scope

Add the first round of appearance variants without broadening beyond Adwaita.

### Deliverables

1. Light and dark variants.
2. High-contrast support if the settings bridge can expose it cleanly.
3. Theme color token organization that avoids duplicating all rendering logic.

### Exit Criteria

1. The same theme codebase can render both light and dark Adwaita-inspired
   appearances.
2. Variant changes do not require hand-editing multiple unrelated code paths.

## Phase 9: Regression Harness And Release Readiness

### Scope

Make the theme maintainable.

### Deliverables

1. Scripted screenshot capture for the demo app.
2. Scripted screenshot capture for the Adwaita reference harness.
3. Baseline screenshots for the major demo pages and their Adwaita
   counterparts.
3. A manual QA checklist covering:
   - menu density
   - menu font size
   - focus visibility
   - disabled state readability
   - active/inactive window behavior
   - dark mode parity
4. Installation and activation documentation.

### Exit Criteria

1. Visual regressions can be caught without ad hoc manual comparison.
2. The theme can be installed and exercised repeatedly with predictable steps.
3. V1 quality is judged against paired GNUstep and Adwaita reference captures
   rather than subjective memory.

## Theme-Only First Policy

The default policy for v1 is to stay inside the theme repository.

Only escalate to `libs-gui` work if at least one of these remains unsolved after
Phase 4:

1. Menu font roles cannot be made to match GNOME acceptably.
2. Menu row density still looks materially too tight.
3. Hard-coded menu padding prevents Adwaita-like spacing.

If a `libs-gui` change becomes necessary, keep it minimal:

1. Prefer exposing an existing hard-coded value as a theme hook.
2. Prefer invalidation or font-role plumbing over broad menu rewrites.
3. Keep the patch small enough that it could plausibly be proposed upstream.

## Acceptance Criteria For V1

V1 is successful when:

1. The demo app no longer looks obviously foreign next to stock GNOME apps.
2. Menus look correctly sized and spaced at normal desktop DPI.
3. Buttons, text fields, pop-ups, tabs, sliders, progress indicators, and
   scrollbars form a coherent Adwaita-like system.
4. Light and dark variants are both credible.
5. The remaining differences from GTK apps are mostly structural GNUstep
   differences, not obvious theme failures.

## Suggested Immediate Next Steps

1. Create the repo skeleton from Phase 0.
2. Build `Examples/ThemeDemo` before writing rendering code.
3. Build `Reference/AdwaitaDemo` early so the project has a concrete visual
   target.
4. Implement the GNOME settings bridge early enough to drive font and variant
   decisions.
5. Treat menu typography as the first hard quality gate, not a later polish
   item.
