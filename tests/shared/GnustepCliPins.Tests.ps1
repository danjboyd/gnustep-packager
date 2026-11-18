Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Pinning only gnustep-cli-manifest-url leaves the bootstrap on the packager's
# release. SpreadsheetApp pinned the v0.1.0-dev manifest and its MSI build was
# refused at setup with a signature error. The workflow now warns first.
Describe "gnustep-cli-new pin check" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
    $script:base = "https://github.com/danjboyd/gnustep-cli-new/releases/download"
  }

  It "reads the release tag of a GitHub release asset, and nothing else" {
    Get-GpGnustepCliReleaseTag -Url "$script:base/v0.1.8/release-manifest.json" | Should -Be "v0.1.8"
    Get-GpGnustepCliReleaseTag -Url "$script:base/v0.1.0-dev/release-manifest.json" | Should -Be "v0.1.0-dev"
    Get-GpGnustepCliReleaseTag -Url "https://mirror.example/gnustep/release-manifest.json" | Should -BeNullOrEmpty
    Get-GpGnustepCliReleaseTag -Url "" | Should -BeNullOrEmpty
  }

  It "says nothing for a matched pair or a URL it can't read" {
    Get-GpGnustepCliPinWarning -ManifestUrl "$script:base/v0.1.8/release-manifest.json" -BootstrapUrl "$script:base/v0.1.8/gnustep-bootstrap.sh" | Should -BeNullOrEmpty
    Get-GpGnustepCliPinWarning -ManifestUrl "https://mirror.example/release-manifest.json" -BootstrapUrl "$script:base/v0.1.8/gnustep-bootstrap.sh" | Should -BeNullOrEmpty
  }

  It "warns that a -dev manifest will be refused by a tagged bootstrap" {
    $warning = Get-GpGnustepCliPinWarning -ManifestUrl "$script:base/v0.1.0-dev/release-manifest.json" -BootstrapUrl "$script:base/v0.1.8/gnustep-bootstrap.sh"
    $warning | Should -Match "is from v0.1.0-dev but the bootstrap is from v0.1.8"
    $warning | Should -Match "setup will be refused"
  }

  It "warns, more softly, about two different stable releases" {
    $warning = Get-GpGnustepCliPinWarning -ManifestUrl "$script:base/v0.1.7/release-manifest.json" -BootstrapUrl "$script:base/v0.1.8/gnustep-bootstrap.sh"
    $warning | Should -Match "is from v0.1.7 but the bootstrap is from v0.1.8"
    $warning | Should -Not -Match "refused"
    $warning | Should -Match "pin gnustep-cli-bootstrap-url and both bootstrap digests to v0.1.7"
  }

  It "keeps the workflow defaults on one release" {
    $workflow = Get-Content -Raw (Join-Path $script:repoRoot ".github/workflows/package-gnustep-app.yml")
    $manifest = [regex]::Match($workflow, '(?s)gnustep-cli-manifest-url:.*?default: "([^"]+)"').Groups[1].Value
    $bootstrap = [regex]::Match($workflow, '(?s)gnustep-cli-bootstrap-url:.*?default: "([^"]+)"').Groups[1].Value
    Get-GpGnustepCliPinWarning -ManifestUrl $manifest -BootstrapUrl $bootstrap | Should -BeNullOrEmpty
  }

  It "checks before the bootstrap runs, and only warns" {
    $workflow = Get-Content -Raw (Join-Path $script:repoRoot ".github/workflows/package-gnustep-app.yml")
    $check = $workflow.IndexOf("- name: Check gnustep-cli-new Pins")
    $check | Should -BeGreaterThan 0
    $check | Should -BeLessThan $workflow.IndexOf("- name: Bootstrap And Smoke Test gnustep-cli-new For MSI")
    # Match the Linux step's name line whatever the checkout's line endings.
    $linuxBootstrap = [regex]::Match($workflow, '(?m)^\s*- name: Bootstrap And Smoke Test gnustep-cli-new\r?$')
    $linuxBootstrap.Success | Should -BeTrue
    $check | Should -BeLessThan $linuxBootstrap.Index
    $workflow | Should -Match "::warning title=gnustep-cli-new pins differ::"
  }
}
