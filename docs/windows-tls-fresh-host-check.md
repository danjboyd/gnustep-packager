# Windows https on a Fresh Host: Check Plan

Status: run as the `windows-tls-fresh-host` job
(`.github/workflows/windows-tls-fresh-host.yml`,
`scripts/ci/windows-tls-fresh-host.ps1`). It passed in run 42741630580; see
"Results" below. The plan as first written follows, with what the run changed
noted where it differs.

## What It Has To Show

An MSI built with gnustep-cli-new v0.1.5 can fetch https on a Windows machine
whose certificate store doesn't yet hold the root the server chains to.

v0.1.5's gnustep-base loads `GSTLS/ca-certificates.crt` alongside the Windows
store (see "Strict TLS" in `gnustep-cli-new-integration.md`). That matters
because Windows adds many roots to its store only when its own software first
needs them, so a freshly installed machine may lack a root that a browser on the
same machine would fetch on demand. libgnutls doesn't trigger that fetch.

Before the job, this was checked only by reading the toolchain: the file is
there (121 Mozilla authorities, dated 2026-08-16) and the patch loads it.

## Why the Hosted Runner Alone Isn't Enough

A GitHub-hosted `windows-latest` runner isn't a fresh machine: its store already
holds the common roots, so an https fetch there passes with or without the
bundle. The check has to remove the root first, and it has to show that the same
fetch fails without the bundle. Otherwise a pass proves nothing.

## Setup

Use a disposable host: a hosted Windows runner (it's thrown away after the job)
or a Windows Sandbox or VM snapshot. Never a developer's own machine.

1. Stop Windows from fetching roots on demand for the rest of the job: set
   `HKLM\SOFTWARE\Policies\Microsoft\SystemCertificates\AuthRoot`
   `DisableRootAutoUpdate` to `1`.
2. Choose the test URL and find its root at run time, so the plan doesn't
   depend on which authority a site uses this year. For example, fetch the
   chain with `certutil -urlfetch -verify` on a saved server certificate, or
   with PowerShell's `X509Chain`, and record the root's thumbprint.
3. Remove that root from `Cert:\LocalMachine\Root` and
   `Cert:\LocalMachine\AuthRoot`. Then show that `Invoke-WebRequest` to the URL
   fails, which proves the store no longer trusts it. (In the run it didn't:
   Windows' own TLS still connected, so the job records `Invoke-WebRequest` as
   information only. Case 2, the app's own fetch without the bundle, is the
   proof.)
4. Check that the root is among the 121 in the MSI's
   `GSTLS/ca-certificates.crt`, and record it. If it isn't, choose another URL.

## Cases

Install the MSI and run a small fetch from inside the app's environment. The
test app's updater check works for this, as does a `-RunSmoke` fetch of a fixed
URL. Each case writes one line to the job log: the case, the URL, the root's
thumbprint, and whether the fetch passed.

| Case | Package | Expected |
| ---- | ------- | -------- |
| 1 | Built with v0.1.5, `GSTLS` staged | fetch succeeds |
| 2 | Same MSI, `GSTLS/ca-certificates.crt` deleted after install | fetch fails (control: shows the store really lacks the root) |
| 3 | Case 2, plus `GS_TLS_CA_FILE` pointing to a copy of the bundle | fetch succeeds |
| 4 | ObjcMarkdown 0.2.6's older list (180 entries) put in place of the bundle, if the root is missing from that list | fetch fails, which shows why a rebuild is needed |

Case 2 is what makes the check meaningful. If case 2 passes, the root wasn't
really gone, and case 1 says nothing.

## Where It Runs

As a `workflow_dispatch` job, which also runs on pushes to the test-only
`windows-tls-fresh-host` branch, as with the other end-to-end checks, not in
default CI. It changes the runner's trust store, and the result depends on
outside sites. The script captures every registry value it changes and each
root it removes, puts them back exactly at the end (even when a case fails),
and checks that it did. With a root left out, the job hung after its last step
in an earlier run; whether the changed store caused that wasn't proven.

## Results

Run 42741630580 (commit b03004a), on `windows-latest` with gnustep-cli-new
v0.1.5 (`gnustep-base-1_31.dll`), the fixture `tests/fixtures/windows-tls-fetch`
built into an MSI and installed per user:

- Sanity, store intact: PASS 200.
- `https://letsencrypt.org/` (ISRG Root X1) and `https://github.com/` (Sectigo
  Public Server Authentication Root E46): case 2 passed with the root removed.
  Another trust path exists, so the job moved on without running their other
  cases. `https://www.google.com/` chains to GlobalSign Root CA, which isn't in
  the bundle, so it was skipped.
- `https://www.digicert.com/` (DigiCert Global Root G2,
  `DF3C24F9BFD666761B268073FE06D1CC8D4F82A4`, removed from
  `LocalMachine\Root`):

| Case | Result |
| ---- | ------ |
| 1, bundle in place | PASS (HTTP 406, the site's answer to a bare request; TLS completed) |
| 2, bundle moved aside | FAIL "TLS verification: remote certificate is not trusted." |
| 3, `GS_TLS_CA_FILE` = a copy of the bundle | PASS (HTTP 406) |
| 4, ObjcMarkdown 0.2.6's list, root not in it | FAIL "remote certificate is not trusted." |

- Restoration: the three removed roots were back, and the three registry values
  matched what they were before. No process from the install root was left
  after any case.
- Not run: the MSI backend's smoke launch (`validation.smoke.enabled` is false,
  because the fixture fetches once and exits). That is a skipped check, not a
  pass; the MSI's install, layout and uninstall validation did run.

A packaged app on Windows also needs `gdnc`: gnustep-base starts it when the
URL loading system first runs, and throws "Unable to find the gdnc tool"
without it. The fixture stages it in `runtime\System\Tools`, with a
`GNUstep.conf` next to the DLL, as the winuitheme example does.

## Open Questions

- Whether `DisableRootAutoUpdate` takes effect without a restart. On the hosted
  image it was already set to 1 before the job touched it. Case 2 shows the
  outcome either way.
- The test URL depends on outside sites. The job tries several in order and
  records which one isolated a root; if none does, it fails and says so.
