# GNUstep CLI New Integration

`gnustep-cli-new` is the default GNUstep toolchain bootstrap path for supported
Windows/MSI and Linux/AppImage CI packaging flows.

The packager remains responsible for manifest resolution, staging validation,
backend transforms, AppImage generation, package validation, release sidecars,
and diagnostics. `gnustep-cli-new` is responsible for provisioning and checking
the GNUstep build toolchain that downstream build and stage commands use before
the staged payload is packaged.

## Default Baseline

The supported default release manifest is:

```text
https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.8/release-manifest.json
```

The supported default bootstrap script is:

```text
https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.8/gnustep-bootstrap.sh
```

The reusable workflow records both values in the `gnustep-cli-new` logs so a
failed run identifies which upstream artifact set was tested.

## Local Smoke Test

Use the repo-owned smoke script to validate a clean Linux host or container:

```sh
GP_GNUSTEP_CLI_ROOT=/tmp/gnustep-cli-new \
GP_GNUSTEP_CLI_LOG_ROOT=dist/logs/gnustep-cli-new \
./scripts/ci/gnustep-cli-new-bootstrap-smoke.sh
```

The smoke path downloads the bootstrap script, runs:

```sh
gnustep-bootstrap.sh --json --yes setup
```

Then it checks:

- `gnustep --version`
- `gnustep doctor --json`
- `gnustep new cli-tool HelloPackager --json`
- `gnustep build --json`
- `gnustep run --json`

The hosted Windows MSI path currently runs the built `HelloPackager.exe`
directly after `gnustep build --json`. This keeps the hosted packager gate
blocked on managed toolchain build/run viability without depending on older
published `gnustep-cli-new` artifacts that still resolve tool runs to the
POSIX-style `./obj/<target>` path.

The script writes selection, setup, doctor, build, run, and blocker-report logs
under `GP_GNUSTEP_CLI_LOG_ROOT`.

## Workflow Inputs

`.github/workflows/package-gnustep-app.yml` exposes:

- `gnustep-cli-manifest-url`
- `gnustep-cli-bootstrap-url`
- `gnustep-cli-bootstrap-sha256` and `gnustep-cli-bootstrap-ps1-sha256`
- `gnustep-cli-root`

Use these inputs to test a newly published upstream manifest or bootstrap
change without editing packager backend code. The downloaded bootstrap script
must match its digest input before it runs; an overridden bootstrap URL needs
its own digest, or an empty one to skip the check.

### Pinning only the manifest

The bootstrap URL and its digests follow the packager release, but
`gnustep-cli-manifest-url` stays whatever the caller sets. A caller that pins
only the manifest therefore runs the default bootstrap script against an older
manifest. The script verifies the manifest's signature against the trust keys
built into it before it uses anything in the manifest.

| Default bootstrap | Pinned manifest | Result (Linux, 2026-11-17) |
| --- | --- | --- |
| v0.1.8 | v0.1.7 | installs 0.1.7 |
| v0.1.7 | v0.1.8 | installs 0.1.8 |
| v0.1.7 or v0.1.8 | v0.1.0-dev | refused: "the release manifest signature did not verify against the pinned trusted key" |

The `v0.1.0-dev` manifest's signature doesn't verify against the keys built into
the v0.1.7 and v0.1.8 bootstraps. A caller still pinning it can't bootstrap
on the default path, whatever packager release it uses. Drop the
`gnustep-cli-manifest-url` input so that it follows the packager's default, or
pin a stable release. To keep an old manifest, pin `gnustep-cli-bootstrap-url`
and both digests to the same release.

When `skip-default-host-setup: false`, the workflow runs the bootstrap smoke
before packaging for both supported backends.

For `backend: appimage`, the workflow:

1. installs the Linux host baseline, including `ca-certificates`, `curl`,
   `tar`, `gzip`, `squashfs-tools`, and `desktop-file-utils`
2. runs the `gnustep-cli-new` bootstrap smoke
3. adds the selected `gnustep-cli-new` root to `PATH`
4. runs the normal shared packaging pipeline

For `backend: msi`, the workflow:

1. starts an MSYS2 `CLANG64` shell as the Windows bootstrap host
2. installs only bootstrap shell prerequisites plus manifest-declared MSYS2
   host packages
3. runs the `gnustep-cli-new` bootstrap smoke from that shell
4. adds the selected `gnustep-cli-new` root to `PATH`
5. runs the normal shared packaging pipeline

When `skip-default-host-setup: true`, the caller owns provisioning. The
workflow still runs the shared package pipeline, but it does not install or
smoke-test `gnustep-cli-new`.

## Blocker Policy

Failures in the supported `gnustep-cli-new` bootstrap path are blockers for MSI
and AppImage CI unless they are clearly caused by downstream app commands or
packager staging/package logic.

Record upstream bootstrap or artifact failures in
[gnustep-cli-new-upstream-requests.md](gnustep-cli-new-upstream-requests.md)
with:

- host OS and runner/container details
- selected manifest URL
- selected bootstrap URL
- resolved artifact IDs when available
- `gnustep --version` and `gnustep doctor --json` output when they run
- failing command output

Do not silently fall back to legacy repo-local GNUstep setup on the supported
default path.

The smoke script writes `gnustep-cli-new-blocker-report.md` into the log root
on both success and failure. On failure, that file is the ready-to-copy upstream
report body. The reusable workflow uploads the `gnustep-cli-new` log directory
as a dedicated diagnostic artifact even when later packaging steps fail.

See [windows-gnustep-cli-new-hardening.md](windows-gnustep-cli-new-hardening.md)
for the Windows/MSYS2 hosted-runner evidence contract and failure
classification guidance.

## Migration Notes

Downstream projects should remove workflow-local GNUstep installation steps
from default hosted-runner packaging jobs. The reusable workflow owns the
standard bootstrap path when `skip-default-host-setup` is `false`.

Keep app-specific build prerequisites in the package manifest:

- `hostDependencies.windows.msys2Packages`
- `hostDependencies.linux.aptPackages`
- reusable profiles such as `gnustep-cmark`

Use workflow package inputs only as temporary overrides while default host setup
is enabled. For self-hosted runners with `skip-default-host-setup: true`, make
the caller preflight run `gnustep --version` and `gnustep doctor --json` against
the expected toolchain before packaging.

## Strict TLS (gnustep-cli v0.1.5 and later)

From v0.1.5, gnustep-cli builds gnustep-base with strict host verification on
by default. An app that fetches https through GNUstep (`NSURLSession`,
`NSURLConnection`, `NSStream` with TLS, or the updater) refuses the connection
when it can't read any trusted certificate authorities. gnustep-base looks for
them in this order, and uses the first one that is set:

1. the `GSTLSCAFile` user default
2. the `GS_TLS_CA_FILE` environment variable
3. the `SSL_CERT_FILE` environment variable
4. the system trust store, through the bundled libgnutls
5. only if that fails, `GSTLS/ca-certificates.crt` in gnustep-base's resources

In a package, step 4 is the trust-store path compiled into the libgnutls you
bundle. A library built on Debian or Ubuntu reads
`/etc/ssl/certs/ca-certificates.crt`. A target that keeps its bundle elsewhere
falls through to step 5, so the package needs that file.

On Windows, libgnutls reads the Windows certificate store. v0.1.5's gnustep-base
also always loads `GSTLS/ca-certificates.crt`, alongside the store rather than
only when the store fails, because Windows adds many roots to its store only
when its own software first needs them. The v0.1.5 Windows toolchain's file is
Mozilla's set as MSYS2 packages it (121 authorities, dated 2026-08-16), at
`lib/GNUstep/Libraries/gnustep-base/Versions/1.31/Resources/GSTLS/`.
gnustep-base's older file is a personal list with expired entries; ObjcMarkdown
0.2.6's MSI carries 180 of them. So rebuild Windows packages with v0.1.5, and
stage that folder there too.

To keep step 5 working, stage gnustep-base's `Resources/GSTLS` folder with
the rest of its resources. A stage script that copies the whole system
`Library`, as `examples/downstream/gnustep-apps/stage-app.sh` does, already
includes it, and so does a Windows stage that copies all of
`clang64/lib/GNUstep`. To use a bundle of your own, ship it and set `GS_TLS_CA_FILE` to
it under `launch.env`.

Set `validation.fetchesHttps: true` for an app that does this without
`updates.enabled`. AppImage and MSI validation then warn when the package has
neither `GSTLS/ca-certificates.crt` nor one of the settings above. It's a
warning, not an error, because the target's system store may be enough.

## Release Baseline

Release notes should identify the known-good `gnustep-cli-new` release manifest
used by the packager release. The current baseline is:

```text
https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.8/release-manifest.json
```

## What each toolchain release ships

The GNUstep an app compiles against depends on the platform as well as the
gnustep-cli-new release. The version number alone can mislead. Each Linux
toolchain is built from upstream source at pinned commits, usually ahead of the
last release. The Windows toolchain installs MSYS2's packaged release. Both can
report the same gnustep-base version and still expose different API.

Read from the published artifacts on 2026-11-17:

| Release | Target | gnustep-base | gnustep-gui | gnustep-make | libobjc2 | Built from |
| --- | --- | --- | --- | --- | --- | --- |
| v0.1.7, v0.1.8 | `linux-amd64-clang` | 1.31.1 | 0.32.0 | 2.9.3 | 2.2.0 | source: libs-base `d898f703`, libs-gui `7892137b`, libs-back `bf3b3ced`, libobjc2 `b67709ad` |
| v0.1.7, v0.1.8 | `windows-amd64-msys2-clang64` | 1.31.1 | 0.32.0 | 2.9.3 | 2.2.0 | MSYS2 CLANG64 packages (release headers) |

The difference shows up as compile errors that happen only on Windows. For
example, `+[NSData dataWithContentsOfFile:options:error:]` is declared in the
Linux toolchain's headers (libs-base master) but not in the Windows ones
(1.31.1). An app developed on Linux that calls it builds there and fails in the
MSI build with "no known class method for selector". Until the two converge,
code that has to build on Windows should stick to API that the 1.31.1 release
headers declare.

Each run also reports what it got. The reusable workflow's "Report GNUstep
Toolchain Versions" step prints a line such as `gnustep-base 1.31.1,
gnustep-gui 0.32.0, gnustep-make 2.9.3, libobjc2 2.2.0 (packaged release
headers)` and adds it to the job summary. It writes
`<logRoot>/gnustep-cli-new/toolchain-versions.json`, and the provenance sidecar
records the same values under `gnustepVersions`.
