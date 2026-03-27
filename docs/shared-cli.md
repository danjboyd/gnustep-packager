# Shared CLI

## Purpose
The shared CLI is the backend-neutral command surface for `gnustep-packager`.

The initial command set is:
- `manifest-check`
- `resolve-manifest`
- `describe`
- `launch-plan`
- `backend-list`
- `build`
- `stage`
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

That wrapper runs the normal build, stage, package, and validate sequence
through the same CLI surface rather than inventing a separate CI-only path.

## Command Intent
- `manifest-check`
  Validate the resolved manifest contract

- `resolve-manifest`
  Show the manifest after defaults and backend defaults have been applied

- `describe`
  Print a concise summary of the resolved package model

- `launch-plan`
  Print the normalized launch contract

- `build`
  Run the consumer repo build command

- `stage`
  Run the consumer repo stage command

- `package`
  Resolve a backend and dispatch to its package handler

- `validate`
  Run shared validation and optionally dispatch to backend validation
