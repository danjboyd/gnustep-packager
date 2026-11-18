# Core Library Layout

`scripts/lib/core.ps1` held every shared function the CLI, the backends and
the reusable workflow use: about 5,900 lines and 149 functions. At that size it's
hard to review a change, to see what a function depends on, or to tell where a
new function belongs. This note sets out how to split it without breaking any
caller.

## Rules for every split

- **One entry point.** Callers keep dot-sourcing `scripts/lib/core.ps1` alone:
  the CLI, the backends, every test and the reusable workflow's inline steps.
  `core.ps1` dot-sources the split-out files from `$PSScriptRoot`, so a checkout
  of the packager (`.gnustep-packager-toolkit`) brings them along.
- **Moves only.** Function bodies, names and parameters don't change in a split
  PR. Each split is checked by comparing every moved function's text with the
  original, and by the full test suite. A behavior change goes in its own PR.
- **One subject per file.** A function goes where its callers would look for it.
  Small helpers move with their only users.
- **No overlap with open PRs.** A split moves code that no open PR edits, so
  reviews don't turn into conflict resolution.

## Files

| File | Holds | Status |
| --- | --- | --- |
| `host-setup.ps1` | `hostDependencies` planning, the reusable workflow's host-setup plan, and the MSYS2 (pacman) and apt installers and preflight: 17 functions | first split |
| `msys2-overlay.ps1` | `Install-GpMsys2PackageOverlay` and the toolchain-overlay helpers (package choice, dependency closure) | after the open overlay PRs land |
| `provenance.ps1` | provenance settings, file identities (ELF build ID, Mach-O UUID, PE CodeView), toolchain provenance and the sidecar | later |
| `theme.ps1` | theme inputs, theme targets and declarative theme defaults | later |
| `updates.ps1` | updater settings, feeds and signatures | later |
| `process.ps1` | process launching, captured output and pipeline shell commands | later |
| `core.ps1` | the manifest context and defaults, paths, logging, and the dot-sourcing of the files above | what remains |

The order is set by risk. Host setup came first because it's a closed group:
its helpers have no other callers, and no open PR touches it. The overlay
functions stay in `core.ps1` until the open overlay PRs land, because they edit
that region.

## Finding a function

```powershell
. ./scripts/lib/core.ps1
(Get-Command Get-GpWorkflowHostSetupPlan).ScriptBlock.File
```
