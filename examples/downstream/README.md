# Downstream Examples

This directory holds consumer-facing examples rather than packager
implementation.

Contents:

- `package-msi.yml`
  Example GitHub Actions workflow that calls the reusable workflow from a
  downstream repository
- `package-appimage.yml`
  Example GitHub Actions workflow that calls the reusable workflow for Linux
  AppImage packaging
- `package-appimage-self-hosted.yml`
  Example GitHub Actions workflow that targets a self-hosted GNUstep Linux
  runner and uses a caller-provided preflight script
- `manifest-gnustep-gui.template.json`
  Minimal manifest starting point for a typical GNUstep GUI app, including a
  GitHub release-feed update block for MSI publishing
- `manifest-gnustep-document-viewer.template.json`
  Slightly more opinionated starting point for a document-viewer style app,
  using the reusable `gnustep-cmark` host dependency profile
- `manifest-gnustep-linux-appimage.template.json`
  Linux-oriented manifest starting point for AppImage packaging, including
  AppImage-native update metadata settings
- `package-release-with-updates.yml`
  End-to-end downstream GitHub Actions example that packages Windows and Linux,
  publishes release assets, and deploys stable update feeds to GitHub Pages
- `objc/AppDelegate+Updates.m`
  Minimal Objective-C snippet that wires `GPStandardUpdaterController` into an
  app delegate

Recommended adoption order:

1. Start from the closest manifest template.
2. Fill in the app-specific package identity and stage paths.
3. Reuse built-in host dependency profiles where they fit, then add any
   remaining app-specific host packages under `hostDependencies` instead of
   copying package-manager lists into workflow YAML.
4. Declare semantic packaging intent under `packagedDefaults`,
   `validation.packageContract`, and `validation.installedResult` before adding
   backend-specific path assertions.
   Keep theme selection under `packagedDefaults.defaultTheme`, and move any
   packaged first-run app preferences into `packagedDefaults.appDomain`.
   Stage a real GNUstep `defaults` tool in the packaged runtime when using
   `appDomain`.
5. For externally built GNUstep themes, declare `themeInputs` in the manifest
   instead of adding repo-local fetch/build/install/copy scripts. Required or
   default theme inputs automatically produce bundled-theme validation
   contracts.
6. Replace the placeholder `updates.github.*` and backend `updates.feedUrl`
   values with your real repo and feed URLs.
7. Keep the default `gnustep-cli-new` workflow bootstrap unless you are using a
   self-hosted runner with an explicit preflight.
8. Add real `compliance.runtimeNotices` entries for shipped runtime contents.
9. Run `scripts/run-packaging-pipeline.ps1 -Backend <msi|appimage> -RunSmoke`
   locally.
