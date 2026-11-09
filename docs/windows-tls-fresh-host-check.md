# Windows https on a Fresh Host: Check Plan

Status: plan only. Nothing here has been run yet.

## What It Has To Show

An MSI built with gnustep-cli-new v0.1.5 can fetch https on a Windows machine
whose certificate store doesn't yet hold the root the server chains to.

v0.1.5's gnustep-base loads `GSTLS/ca-certificates.crt` alongside the Windows
store (see "Strict TLS" in `gnustep-cli-new-integration.md`). That matters
because Windows adds many roots to its store only when its own software first
needs them, so a freshly installed machine may lack a root that a browser on the
same machine would fetch on demand. libgnutls doesn't trigger that fetch.

So far this is checked only by reading the toolchain: the file is there (121
Mozilla authorities, dated 2026-08-16) and the patch loads it. No installed app
has made an https request on a host that lacked the root.

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
   fails, which proves the store no longer trusts it.
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
| 4 | ObjcMarkdown 0.2.6's MSI (the 180-entry older list), if the root is missing from that list | fetch fails, which shows why a rebuild is needed |

Case 2 is what makes the check meaningful. If case 2 passes, the root wasn't
really gone, and case 1 says nothing.

## Where It Would Run

As a manual `workflow_dispatch` job on a test-only branch, as with the other
end-to-end checks, not in default CI. It changes the runner's trust store, and
the result depends on outside sites.

## Open Questions

- Whether `DisableRootAutoUpdate` takes effect for the rest of the job without a
  restart on hosted runners. If it doesn't, removing the root from both stores
  may still be enough, since case 2 shows the outcome either way.
- Which test URL to use. It should be a stable https endpoint whose root is in
  the bundle but isn't one Windows ships pre-installed. The run picks it and
  records it, rather than this plan naming one.
