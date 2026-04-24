# Shared CLI

## Purpose
The shared CLI is the backend-neutral command surface for `gnustep-packager`.

The initial command set is:
- `manifest-check`
- `resolve-manifest`
- `describe`
- `launch-plan`
- `backend-list`
- `host-preflight`
- `build`
- `stage`
- `provision`
- `package`
- `validate`

## Command Rules
- every command accepts `-Manifest`
- backend-dispatched commands accept `-Backend`
- release-oriented commands may accept `-PackageVersion`
- commands that should be previewable accept `-DryRun`
- command logs are written under the manifest's configured log root

## Shared Wrapper
For local and CI parity, the repo also provides:

- `scripts/run-packaging-pipeline.ps1`

That wrapper runs the normal build, stage, provision, package, and validate
sequence through the same CLI surface rather than inventing a separate CI-only
path.

## Command Intent
- `manifest-check`
  Validate the resolved manifest contract

- `resolve-manifest`
  Show the manifest after defaults and backend defaults have been applied

- `describe`
  Print a concise summary of the resolved package model

- `launch-plan`
  Print the normalized launch contract

- `host-preflight`
  Verify or install manifest-declared host/build dependencies for the current
  host

- `build`
  Run the consumer repo build command

- `stage`
  Run the consumer repo stage command

- `provision`
  Compose packager-owned inputs such as declared GNUstep `themeInputs` into the
  staged payload before validation and backend packaging

- `package`
  Resolve a backend and dispatch to its package handler

- `validate`
  Run shared validation and optionally dispatch to backend validation

The shared pipeline wrapper runs `host-preflight` before build by default. Use
`-InstallHostDependencies` to allow package-manager realization, or
`-SkipHostPreflight` when intentionally bypassing that step.
