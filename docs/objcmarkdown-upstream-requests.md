# ObjcMarkdown Upstream Requests

`ObjcMarkdown` filed the following upstream requests against
`gnustep-packager` as markdown documents in its repo:

- Windows bundle dependency-closure regression report
- `validation.smoke.requiredPaths` glob support
- better Windows diagnostics for bundle-present but runtime-incomplete failures

These requests are tracked here so the work is documented in the packager repo
itself rather than only in downstream issue notes.

## Request Set

### 1. Windows Bundle Dependency Closure
Source:
- `ObjcMarkdown/docs/upstream/gnustep-packager-windows-bundle-dependency-closure-bug.md`

Requested outcome:
- fail packaging or validation when a DLL under staged runtime bundle or plugin
  paths depends on non-system DLLs that are missing from the packaged runtime
- report which staged DLL required the missing dependency

Resolution plan:
- keep MSI closure analysis recursive across all runtime `.dll` and `.exe`
  files
- retain per-target dependency provenance instead of only emitting a flat list
  of unresolved DLL names
- add regression coverage for runtime-extension DLLs such as GNUstep bundles

Status:
- implemented in this repo once the MSI runtime-closure analysis and tests land

### 2. `validation.smoke.requiredPaths` Globs
Source:
- `ObjcMarkdown/docs/upstream/gnustep-packager-required-path-glob-feature-request.md`

Requested outcome:
- allow glob entries inside `validation.smoke.requiredPaths`
- treat each glob entry as satisfied when at least one path matches
- log the original pattern plus matched concrete paths

Resolution plan:
- extend shared staged-layout validation so literal entries preserve current
  semantics while wildcard entries resolve through a stage-relative match pass
- document the new semantics in the validation contract and downstream example
  manifests

Status:
- implemented in this repo once the shared validation update and tests land

### 3. Better Windows Diagnostics
Source:
- `ObjcMarkdown/docs/upstream/gnustep-packager-windows-diagnostics-feature-request.md`

Requested outcome:
- distinguish launcher problems from app-start problems and runtime-incomplete
  bundle/plugin failures
- report missing dependent DLL names and the runtime binary that required them

Resolution plan:
- classify MSI validation failures at a finer grain
- run a read-only installed-runtime dependency audit during MSI validation
- surface grouped missing-dependency diagnostics in the package sidecar, the
  MSI validation log, and the thrown validation error

Status:
- implemented in this repo once MSI validation classification, diagnostics, and
  Windows-host verification land

## Verification Plan

Development and most regression coverage can run on Linux hosts because the
shared validation logic and MSI dependency analysis are pure PowerShell
functions.

Final MSI verification uses OracleTestVMs plus the managed
`windows-msys2-clang64` toolchain path from `gnustep-cli`:

1. lease a fresh `windows-2022` guest through `otvm`
2. install the managed MSYS2 `CLANG64` GNUstep toolchain with `gnustep-cli`
3. run `gnustep-packager` MSI package and validate commands on the guest
4. collect logs, diagnostics sidecars, and artifacts back into `dist/otvm/`

## Leave-Off

When the work is complete, update this document with:

- exact tests added
- Windows verification evidence directory
- any residual limitations that remain documented rather than fully solved
