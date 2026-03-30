# Downstream Examples

This directory holds consumer-facing examples rather than packager
implementation.

Contents:

- `package-msi.yml`
  Example GitHub Actions workflow that calls the reusable workflow from a
  downstream repository
- `manifest-gnustep-gui.template.json`
  Minimal manifest starting point for a typical GNUstep GUI app
- `manifest-gnustep-document-viewer.template.json`
  Slightly more opinionated starting point for a document-viewer style app

Recommended adoption order:

1. Start from the closest manifest template.
2. Fill in the app-specific package identity and stage paths.
3. Add real `compliance.runtimeNotices` entries for shipped runtime contents.
4. Run `scripts/run-packaging-pipeline.ps1 -Backend msi -RunSmoke` locally.
