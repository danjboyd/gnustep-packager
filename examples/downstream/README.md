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
- `manifest-gnustep-gui.template.json`
  Minimal manifest starting point for a typical GNUstep GUI app
- `manifest-gnustep-document-viewer.template.json`
  Slightly more opinionated starting point for a document-viewer style app
- `manifest-gnustep-linux-appimage.template.json`
  Linux-oriented manifest starting point for AppImage packaging

Recommended adoption order:

1. Start from the closest manifest template.
2. Fill in the app-specific package identity and stage paths.
3. Add real `compliance.runtimeNotices` entries for shipped runtime contents.
4. Run `scripts/run-packaging-pipeline.ps1 -Backend <msi|appimage> -RunSmoke`
   locally.
