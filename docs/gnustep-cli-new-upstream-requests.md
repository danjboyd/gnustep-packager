# GNUstep CLI New Upstream Requests

This document tracks issues found while evaluating `gnustep-cli-new` as the
default GNUstep toolchain provider for `gnustep-packager` GitHub Actions.

The intended packager-side direction is:

- use `gnustep-cli-new` to provision and validate the GNUstep build toolchain
- keep `gnustep-packager` responsible for staging validation, MSI generation,
  AppImage generation, package validation, and release sidecars
- make `gnustep-cli-new` the default provider only after the hosted Windows and
  Linux runner paths are clean

## Request Set

### 1. Ubuntu 24.04 Managed Linux Artifact Loader Failure

Source:
- local clean-container validation against `ubuntu:24.04`
- `gnustep-cli-new` public release manifest:
  `https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.0-dev/release-manifest.json`
- original `gnustep-cli-new` commit reviewed by `gnustep-packager`:
  `78c9979ae1d08afe13f5edc750a3b81c33adabb8`
- follow-up bootstrap prerequisite commit retested by `gnustep-packager`:
  `77f2ee33752f108d576d64bfad023cda3f26831f`
- Ubuntu target commit inspected and retested by `gnustep-packager`:
  `e79a715377c3eb7fdc422a15a2e62a517e0bb523`
- Ubuntu artifact publication commit retested by `gnustep-packager`:
  `d9c0905e1deb518892c999a387abf0e898ff0573`

Why this matters:
- `gnustep-packager` currently uses `ubuntu-latest` as the default AppImage
  GitHub Actions runner
- `ubuntu-latest` maps to the Ubuntu 24.04 hosted runner family
- using `gnustep-cli-new` as the default provider across MSI and AppImage
  packaging requires the Linux managed CLI to start on that runner

Reproduction:

```sh
sudo docker run --rm ubuntu:24.04 bash -lc '
set -euo pipefail
apt-get update >/dev/null
apt-get install -y ca-certificates curl tar gzip >/dev/null
root=/tmp/gnustep-cli
curl -fsSL \
  https://raw.githubusercontent.com/danjboyd/gnustep-cli-new/master/scripts/bootstrap/gnustep-bootstrap.sh \
  -o /tmp/gnustep-bootstrap.sh
chmod +x /tmp/gnustep-bootstrap.sh
/tmp/gnustep-bootstrap.sh --json setup --user --root "$root" \
  --manifest https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.0-dev/release-manifest.json
export PATH="$root/bin:$root/Tools:$root/System/Tools:$PATH"
gnustep --version
'
```

Observed result:

```text
/tmp/gnustep-cli/libexec/gnustep-cli/bin/gnustep: error while loading shared libraries: libavahi-common.so.3: cannot open shared object file: No such file or directory
```

The setup step itself succeeds and installs the Linux CLI and managed toolchain
artifacts. The installed full CLI fails at process startup.

Follow-up result with `77f2ee3`:
- the POSIX bootstrap now reports Ubuntu host prerequisite packages derived from
  `https://github.com/gnustep/tools-scripts`
- running setup with `--yes` successfully invokes apt and installs the declared
  Ubuntu prerequisite set
- setup still succeeds
- the installed full CLI still fails at process startup, now narrowed to the ICU
  SONAME mismatch:

```text
/tmp/gnustep-cli/libexec/gnustep-cli/bin/gnustep: error while loading shared libraries: libicui18n.so.76: cannot open shared object file: No such file or directory
```

Follow-up result with `e79a715`:
- source now contains a first-class `linux-ubuntu2404-amd64-clang` target
- the POSIX bootstrap now selects `cli-linux-ubuntu2404-amd64-clang` and
  `toolchain-linux-ubuntu2404-amd64-clang` on Ubuntu 24.04 amd64
- this avoids selecting the Debian-scoped generic Linux artifacts on Ubuntu
- the public `v0.1.0-dev` release manifest still does not contain Ubuntu
  artifact IDs
- the public `v0.1.0-dev` GitHub release assets still only include:
  - `gnustep-cli-linux-amd64-clang-0.1.0-dev.tar.gz`
  - `gnustep-toolchain-linux-amd64-clang-0.1.0-dev.tar.gz`
  - Windows MSYS2 artifacts and release metadata
- clean Ubuntu 24.04 setup against the public manifest now fails cleanly with:

```text
No matching release artifacts were found for this host.
```

Resolution result with `d9c0905`:
- the public `v0.1.0-dev` release manifest now includes:
  - `cli-linux-ubuntu2404-amd64-clang`
  - `toolchain-linux-ubuntu2404-amd64-clang`
- both Ubuntu artifacts are marked `published: true`
- both artifacts are scoped to:
  - `supported_distributions: ["ubuntu"]`
  - `supported_os_versions: ["ubuntu-24.04"]`
- the GitHub release now contains:
  - `gnustep-cli-linux-ubuntu2404-amd64-clang-0.1.0-dev.tar.gz`
  - `gnustep-toolchain-linux-ubuntu2404-amd64-clang-0.1.0-dev.tar.gz`
  - `tools-xctest-linux-ubuntu2404-amd64-clang-0.1.0.tar.gz`
- clean `ubuntu:24.04` Docker validation passed:
  - bootstrap `setup --yes` installed host prerequisites
  - setup selected the Ubuntu-specific CLI and toolchain artifacts
  - `gnustep --version` printed `0.1.0-dev`
  - `gnustep doctor --json` reported `toolchain_compatible`
  - `gnustep new cli-tool HelloPackager --json` succeeded
  - `gnustep build --json` succeeded through `gnustep-make`
  - `gnustep run --json` printed `Hello from CLI tool`

Dependency inspection after setup:

```sh
ldd /tmp/gnustep-cli/libexec/gnustep-cli/bin/gnustep
```

Missing libraries observed on clean `ubuntu:24.04`:

```text
libavahi-common.so.3 => not found
libavahi-client.so.3 => not found
libxslt.so.1 => not found
libxml2.so.2 => not found
libicui18n.so.76 => not found
libicuuc.so.76 => not found
libicudata.so.76 => not found
libcurl-gnutls.so.4 => not found
```

Ubuntu 24.04 package availability notes:

- `libavahi-client3`, `libxslt1.1`, `libxml2`, and `libcurl3t64-gnutls` are
  available through apt
- Ubuntu 24.04 provides ICU 74 packages, not ICU 76
- the ICU SONAME mismatch means the current Debian-built artifact is still not
  repairable on Ubuntu 24.04 by installing the declared host prerequisite
  packages

Expected result:
- bootstrap `setup` should either install a Linux CLI that starts on the
  supported Ubuntu runner baseline or reject the host before installing an
  incompatible artifact
- `gnustep --version`, `gnustep --help`, and `gnustep doctor --json` should pass
  after setup on the default AppImage runner baseline

Suggested upstream fixes:
- publish an Ubuntu 24.04-compatible managed Linux artifact, or
- bundle/relocate the required non-baseline shared libraries into the managed
  artifact, or
- mark the current `linux-amd64-clang` artifact as Debian-only in release
  selection so Ubuntu hosts receive a clear compatibility error rather than a
  loader failure

Packager status:
- resolved for clean Ubuntu 24.04 Docker smoke as of `d9c0905`
- no longer blocks evaluating `gnustep-cli-new` as the default Linux/AppImage
  toolchain provider for the `ubuntu-latest` runner family

### 2. POSIX Bootstrap `setup --json` Option Placement

Source:
- local Debian 13 validation of the POSIX bootstrap script from
  `gnustep-cli-new` `master`

Reproduction:

```sh
gnustep-bootstrap.sh setup --user --root /tmp/gnustep-cli \
  --manifest https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.0-dev/release-manifest.json \
  --json
```

Observed result:
- setup succeeds, but output is human-readable instead of JSON

Working form:

```sh
gnustep-bootstrap.sh --json setup --user --root /tmp/gnustep-cli \
  --manifest https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.0-dev/release-manifest.json
```

Expected result:
- if the command contract allows `gnustep <command> [options]`, then
  command-local `setup --json` should be accepted consistently, or docs should
  clearly require global options before the command for the bootstrap interface

Packager status:
- not a blocker if the workflow uses `--json setup`
- worth fixing upstream before downstream workflow examples rely on JSON output

### 3. Windows MSYS2 CLANG64 Bootstrap Host Detection

Source:
- hosted GitHub Actions validation run `24736846989`
- retested in hosted validation run `24737776995` with the same Windows
  selector failure
- `windows-latest` with `msys2/setup-msys2` using `MSYSTEM=CLANG64`
- `gnustep-cli-new` public release manifest:
  `https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.0-dev/release-manifest.json`

Why this matters:
- `gnustep-packager` uses MSYS2 `CLANG64` as the supported Windows build host
  for MSI packaging
- the public manifest includes published Windows artifacts:
  - `cli-windows-amd64-msys2-clang64`
  - `toolchain-windows-amd64-msys2-clang64`
- the bootstrap script must select those artifacts from an MSYS2 shell before
  the packager can build and validate MSI fixtures from the managed toolchain

Reproduction:

```sh
export MSYSTEM=CLANG64
root=/d/a/_temp/gnustep-cli-new
curl -fsSL \
  https://raw.githubusercontent.com/danjboyd/gnustep-cli-new/master/scripts/bootstrap/gnustep-bootstrap.sh \
  -o /tmp/gnustep-bootstrap.sh
chmod +x /tmp/gnustep-bootstrap.sh
/tmp/gnustep-bootstrap.sh --json --yes setup --user --root "$root" \
  --manifest https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.0-dev/release-manifest.json
```

Observed result:

```json
{"schema_version":1,"command":"setup","cli_version":"0.1.0-dev","ok":false,"status":"error","summary":"No matching release artifacts were found for this host.","doctor":{"status":"warning","environment_classification":"no_toolchain","summary":"No preexisting GNUstep toolchain was detected.","os":"unknown"},"plan":{"scope":"user","install_root":"/d/a/_temp/gnustep-cli-new","channel":"stable","selected_release":"0.1.0-dev","selected_artifacts":[],"system_privileges_ok":true},"actions":[{"kind":"report_bug","priority":1,"message":"No supported managed artifact matches this host yet."}]}
```

The hosted run recorded:

```text
uname=MINGW64_NT-10.0-26100 ...
msystem=CLANG64
runner_os=Windows
host_kind=windows-msys2-clang64
```

Expected result:
- the bootstrap should classify MSYS2 `MINGW64_NT-*` / `MSYSTEM=CLANG64` as a
  supported Windows host
- setup should select `cli-windows-amd64-msys2-clang64` and
  `toolchain-windows-amd64-msys2-clang64`
- Windows artifacts should be extracted with a format-aware path; the current
  bootstrap extraction path appears tarball-only, while the Windows manifest
  entries are `.zip`

Suggested upstream fixes:
- update bootstrap host detection so MSYS2 shells on Windows report
  `os=windows`, `arch=amd64`, and `toolchain_flavor=msys2-clang64`
- update managed target selection to emit `windows-amd64-msys2-clang64` for
  the supported Windows host
- add zip extraction support for published Windows artifacts, or publish the
  Windows CLI and toolchain artifacts in the format the bootstrap currently
  extracts

Packager status:
- blocks the hosted Windows MSI path from reaching build/stage/package
- packager diagnostics now upload `windows-gnustep-cli-new` with a
  ready-to-copy blocker report and host/path context logs
- release readiness is gated on retesting this path after upstream host
  detection and Windows artifact extraction are fixed

## Successful Control Check

On Debian 13, the same public release manifest successfully installs, starts,
and builds/runs a generated CLI-tool project:

```sh
gnustep-bootstrap.sh --json setup --user --root /tmp/gnustep-cli \
  --manifest https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.0-dev/release-manifest.json
export PATH="/tmp/gnustep-cli/bin:/tmp/gnustep-cli/Tools:/tmp/gnustep-cli/System/Tools:$PATH"
gnustep --version
gnustep doctor --json --manifest https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.0-dev/release-manifest.json
gnustep new cli-tool HelloPackager --json
cd HelloPackager
gnustep build --json
gnustep run --json
```

Observed Debian result:
- `gnustep --version` prints `0.1.0-dev`
- `doctor --json` reports `toolchain_compatible`
- `gnustep build --json` succeeds through the `gnustep-make` backend
- `gnustep run --json` prints `Hello from CLI tool`
