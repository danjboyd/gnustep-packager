Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Toolchain roots shaped like the real gnustep-cli-new v0.1.8 ones. Their
# version lines were read from the published artifacts on 2026-11-17: both say
# gnustep-base 1.31.1, but the Linux one is built from libs-base master
# (d898f703) and the Windows one ships MSYS2's release headers.
Describe "GNUstep toolchain versions" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
    $script:workRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-toolchain-versions-" + [guid]::NewGuid().ToString("N"))

    function Write-GpTestFile([string]$Path, [string[]]$Lines) {
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
      Set-Content -Path $Path -Value $Lines
    }

    function New-GpVersionFiles([string]$Prefix, [string]$HeaderRoot, [string]$MakefilesRoot, [string]$Base = "1.31.1") {
      Write-GpTestFile (Join-Path $HeaderRoot "GNUstepBase/GSConfig.h") @("#define GNUSTEP_BASE_VERSION            $Base", "#define GNUSTEP_BASE_MAJOR_VERSION      1")
      Write-GpTestFile (Join-Path $HeaderRoot "GNUstepGUI/GSVersion.h") @("#ifndef GNUSTEP_GUI_VERSION", "#define GNUSTEP_GUI_VERSION          0.32.0", "#endif")
      Write-GpTestFile (Join-Path $MakefilesRoot "config-noarch.make") @("GNUSTEP_MAKE_MAJOR_VERSION=2", "GNUSTEP_MAKE_VERSION=2.9.3")
      Write-GpTestFile (Join-Path $Prefix "lib/pkgconfig/libobjc.pc") @("Name: libobjc", "Version: 2.2.0")
    }
  }

  AfterAll {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $script:workRoot
  }

  It "reads a Windows (MSYS2 CLANG64) root and prefers the clang64 headers" {
    $root = Join-Path $script:workRoot "windows"
    # The root-level copies are older here, so picking them would show.
    New-GpVersionFiles -Prefix $root -HeaderRoot (Join-Path $root "include") -MakefilesRoot (Join-Path $root "share/GNUstep/Makefiles") -Base "1.30.0"
    New-GpVersionFiles -Prefix (Join-Path $root "clang64") -HeaderRoot (Join-Path $root "clang64/include") -MakefilesRoot (Join-Path $root "clang64/share/GNUstep/Makefiles")

    $versions = Get-GpGnustepToolchainVersions -Root $root

    $versions.base | Should -Be "1.31.1"
    $versions.gui | Should -Be "0.32.0"
    $versions.make | Should -Be "2.9.3"
    $versions.objc | Should -Be "2.2.0"
    $versions.headers | Should -Be "clang64/include"
    $versions.builtFrom | Should -Be "packages"
    Format-GpGnustepToolchainVersions -Versions $versions |
      Should -Be "gnustep-base 1.31.1, gnustep-gui 0.32.0, gnustep-make 2.9.3, libobjc2 2.2.0 (packaged release headers)"
  }

  It "reads a source-built Linux root with its component revisions" {
    $root = Join-Path $script:workRoot "linux"
    New-GpVersionFiles -Prefix $root -HeaderRoot (Join-Path $root "Local/Library/Headers") -MakefilesRoot (Join-Path $root "System/Library/Makefiles")
    Write-GpTestFile (Join-Path $root "component-inventory.json") @(
      '{ "schema_version": 1, "components": ['
      '  { "name": "libobjc2", "version": "TBD", "source_revision": "b67709ad7851973fde127022d8ac6a710c82b1d5" },'
      '  { "name": "libs-base", "version": "TBD", "source_revision": "d898f703e6aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }'
      '] }'
    )

    $versions = Get-GpGnustepToolchainVersions -Root $root

    $versions.base | Should -Be "1.31.1"
    $versions.headers | Should -Be "Local/Library/Headers"
    $versions.builtFrom | Should -Be "source"
    @($versions.sources).Count | Should -Be 2
    Format-GpGnustepToolchainVersions -Versions $versions | Should -Match "\(built from source; libs-base d898f703e6\)$"
  }

  It "returns nothing for a missing root or one without GNUstep headers" {
    Get-GpGnustepToolchainVersions -Root (Join-Path $script:workRoot "missing") | Should -BeNullOrEmpty
    $empty = Join-Path $script:workRoot "empty"
    New-Item -ItemType Directory -Force -Path $empty | Out-Null
    Get-GpGnustepToolchainVersions -Root $empty | Should -BeNullOrEmpty
  }

  It "is reported by the reusable workflow before the caller preflight" {
    $workflow = Get-Content -Raw (Join-Path $script:repoRoot ".github/workflows/package-gnustep-app.yml")
    $report = $workflow.IndexOf("- name: Report GNUstep Toolchain Versions")
    $report | Should -BeGreaterThan $workflow.IndexOf("- name: Bootstrap And Smoke Test gnustep-cli-new`n")
    $report | Should -BeLessThan $workflow.IndexOf("- name: Run Caller Preflight (pwsh)")
    $workflow | Should -Match "toolchain-versions\.json"
  }
}
