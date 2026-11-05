# Packaging Swift GNUstep Apps (Design Note)

Status: proposal. Only the runtime closure check below is implemented. Swift
apps fall outside the support boundary in `AGENTS.md`, so the rest needs a
Roadmap entry that Dan approves first.

The facts about the toolchain come from the gnustep-swift stack note
(`gnustep-swift` `docs/GNUSTEP_CLI_SWIFT_STACK.md`). Where this note goes
beyond that, it says so.

## The Toolchain, Per The Stack Note
- It is a separate gnustep-cli flavor, `linux-amd64-clang-swift`, pinned to a
  13-component stack. The carried fixes live on the `danjboyd/*` gnustep-swift
  forks (`config/patched-stack.tsv`).
- Install order: libobjc2, tools-make, libdispatch, base, gui, back,
  tools-xctest, the Swift toolchain, the Swift overlays (the `ObjectiveC`
  module, `BOOL` as `Bool`), then apinotes.
- The prebuilt Swift archive is about 6 GB and must ship with its libobjc2
  pin.
- An app bundle has to carry the Swift runtime libraries (`libswiftCore`,
  `libFoundation` where the app uses it, and the overlays). The alternative is
  a target with the same flavor installed.

## Two Delivery Paths

### Path A: The Runtime Travels With The App (recommended for desktop apps)
The stage step copies the Swift runtime closure into the payload's `runtime/`
tree next to the GNUstep runtime. The AppImage is then self-contained, which
is the AppImage contract anyway.

What gnustep-packager already provides for this:
- `backends.appimage.validation.runtimeClosure` fails the package when a Swift
  runtime library (`libswiftCore`, the overlays, Foundation) isn't in the payload,
  even if the build host has a copy. That catches a forgotten `libswiftCore.so`.
- `toolchain.provenanceFile` with `toolchain.lockFile` ties the staged
  GNUstep libraries to the pinned stack by ELF build ID. If the Swift flavor
  writes the same `gnustep-toolchain-provenance.json` (to be confirmed), a
  libobjc2 from any other build fails validation. That is the pin-mismatch
  failure the stack note warns about.
- `toolchain.foreignLibraries` covers any Swift runtime files that the
  provenance file doesn't list.
- `appimage-clean-smoke-image` launches the result in a container with no
  GNUstep and no Swift. This is the real test of path A.

What is missing, and would be the implementation work:
1. A documented list of the Swift runtime files a GNUstep app needs, taken
   from a real app's `ldd` closure rather than guessed. The stage step owns
   copying them (stage-first: the backend never harvests).
2. A `sample-swift-linux` fixture: a minimal Swift AppKit app built with the
   flavor, staged with that closure, and run through the reusable workflow's
   appimage path with the clean-container smoke test.
3. The Swift toolchain version and the overlay commit in the release's
   `.provenance.json`, next to the GNUstep stack's commits.

Users never download the 6 GB archive under this path. Only the CI host that
builds the app needs it. The shipped closure is a small part of it, but how
small has not been measured yet.

### Path B: The Target Has The Flavor Installed
The package ships only the app and expects `linux-amd64-clang-swift` to be
installed on the target, for example through `gnustep` cli.

- This is not an AppImage in any useful sense. The clean-container smoke test
  would fail by design. It suits developer previews and machines that already
  run the flavor, not end users.
- `backends.appimage.validation.swiftFlavor` records the flavor at validation
  time and lets the Swift libraries stay out of the package. Nothing checks for
  the flavor on the target yet: that would need a launch-time check rather than a
  packaging feature. That is closer to Phase 19's headless runtime delivery
  (PR #77) than to the desktop backends.
- Every target needs the full toolchain, so this path does depend on where the
  archive is hosted.

## MSI And DMG
- **MSI:** no Windows Swift flavor exists in the stack note. Out of scope until
  one does.
- **DMG:** a macOS build uses Apple's Swift and AppKit, not the GNUstep
  stack. The DMG backend already packages native bundles, so a macOS build of
  a Swift app needs no Swift-specific work here.

## Decisions And Open Questions
- **Hosting the archive (Dan):** it is over 2 GiB, which rules out a single
  GitHub release asset. This blocks CI for both paths and every install under
  path B. It does not block users under path A.
- **libdispatch (to confirm):** the GNUstep stack builds its own libdispatch
  before base. Does the Swift toolchain carry a second `libdispatch.so` or
  `libBlocksRuntime.so`? If it does, the stage step must ship exactly one, and
  `foreignLibraries` must say which.
- **Overlays:** are they shared libraries the app loads at run time, or only
  modules needed at build time? That decides whether they belong in the
  closure.
- **Provenance:** does the flavor write `gnustep-toolchain-provenance.json` in
  the same schema? If not, the build-ID check covers the GNUstep half only.

## Suggested Order
1. Dan decides on hosting, or CI gets a cached copy of the archive on a
   self-hosted runner, which `runs-on-appimage` already supports.
2. Measure a real app's closure and write it down (item 1 above).
3. Add the fixture and the CI job (item 2).
4. Add the provenance fields (item 3).
