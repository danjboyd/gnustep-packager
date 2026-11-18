Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Roots shaped like a gnustep-cli-new v0.1.9 Windows install. The carry-layer.json
# here is trimmed from the published gnustep-carry-windows-amd64-msys2-clang64-0.1.9.zip
# (read 2026-11-18): the same 4 carried files, and 2 of its 18 patch ids.
Describe "Toolchain variant" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
    $script:workRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-toolchain-variant-" + [guid]::NewGuid().ToString("N"))
    $script:base = "https://github.com/danjboyd/gnustep-cli-new/releases/download"

    function New-GpVariantRoot([string]$Name, [string]$State, [switch]$Layer) {
      $root = Join-Path $script:workRoot $Name
      New-Item -ItemType Directory -Force -Path (Join-Path $root "state") | Out-Null
      if ($State) { Set-Content -Path (Join-Path $root "state/cli-state.json") -Value $State }
      if ($Layer) {
        Set-Content -Path (Join-Path $root "carry-layer.json") -Value @'
{
  "schema_version": 1,
  "target": "windows-amd64-msys2-clang64",
  "release": "0.1.9",
  "requires_toolchain_sha256": "017facad5500cd7490fc58ac97a7961d0e240cd4a49f811977923d671c06d43a",
  "patches": [
    {"id": "win32-per-monitor-dpi", "library": "libs-back"},
    {"id": "gui-theme-live-switch", "library": "libs-gui"}
  ],
  "files": [
    {"path": "clang64/bin/gnustep-base-1_31.dll"},
    {"path": "clang64/bin/gnustep-gui-0.dll"},
    {"path": "clang64/bin/gpbs.exe"},
    {"path": "clang64/lib/GNUstep/Bundles/libgnustep-back-032.bundle/libgnustep-back-032.dll"}
  ]
}
'@
      }
      return $root
    }
  }

  AfterAll {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $script:workRoot
  }

  It "reads a patched root's variant, patches and carried files" {
    $root = New-GpVariantRoot -Name "patched" -Layer -State '{"toolchain_variant": "patched", "carry_layer": {"release": "0.1.9", "sha256": "7bd23d54", "patches": ["win32-per-monitor-dpi", "gui-theme-live-switch"]}}'
    $info = Get-GpToolchainVariant -Root $root
    $info.variant | Should -Be "patched"
    $info.carryLayerRelease | Should -Be "0.1.9"
    $info.patches | Should -Be @("win32-per-monitor-dpi", "gui-theme-live-switch")
    $info.carriedFiles.Count | Should -Be 4
    $info.carriedFiles | Should -Contain "clang64/bin/gnustep-gui-0.dll"
  }

  It "treats a state file without toolchain_variant (before v0.1.9) as stock, and a missing one as unknown" {
    $old = New-GpVariantRoot -Name "pre-019" -State '{"installed_version": "0.1.8"}'
    $info = Get-GpToolchainVariant -Root $old
    $info.variant | Should -Be "stock"
    @($info.patches).Count | Should -Be 0
    $info.carriedFiles.Count | Should -Be 0
    Get-GpToolchainVariant -Root (New-GpVariantRoot -Name "no-state") | Should -BeNullOrEmpty
  }

  It "accepts stock anywhere and patched on MSI with a v0.1.9 manifest" {
    Get-GpToolchainVariantProblem -Variant "stock" -Backend "appimage" -ManifestUrl "$script:base/v0.1.8/release-manifest.json" | Should -BeNullOrEmpty
    Get-GpToolchainVariantProblem -Variant "" -Backend "dmg" -ManifestUrl "" | Should -BeNullOrEmpty
    Get-GpToolchainVariantProblem -Variant "patched" -Backend "msi" -ManifestUrl "$script:base/v0.1.9/release-manifest.json" | Should -BeNullOrEmpty
    Get-GpToolchainVariantProblem -Variant "patched" -Backend "msi" -ManifestUrl "$script:base/v0.1.10/release-manifest.json" | Should -BeNullOrEmpty
    # A mirror or -dev manifest isn't judged here; setup reports it.
    Get-GpToolchainVariantProblem -Variant "patched" -Backend "msi" -ManifestUrl "https://mirror.example/release-manifest.json" | Should -BeNullOrEmpty
  }

  It "refuses an unknown value, patched off Windows, and patched with a pre-v0.1.9 manifest" {
    Get-GpToolchainVariantProblem -Variant "Patched-ish" -Backend "msi" -ManifestUrl "" | Should -BeLike "*must be 'stock' or 'patched'*"
    Get-GpToolchainVariantProblem -Variant "patched" -Backend "appimage" -ManifestUrl "$script:base/v0.1.9/release-manifest.json" | Should -BeLike "*needs the MSI backend*appimage*"
    Get-GpToolchainVariantProblem -Variant "patched" -Backend "dmg" -ManifestUrl "" | Should -BeLike "*needs the MSI backend*"
    Get-GpToolchainVariantProblem -Variant "patched" -Backend "msi" -ManifestUrl "$script:base/v0.1.8/release-manifest.json" | Should -BeLike "*needs gnustep-cli-new v0.1.9 or later*v0.1.8*"
  }

  It "adds the patched variant to the versions line, and leaves stock lines alone" {
    $versions = [ordered]@{ base = "1.31.1"; gui = "0.32.0"; make = "2.9.3"; objc = "2.2.0"; sources = @(); variant = "patched"; patches = [string[]]@("a", "b") }
    Format-GpGnustepToolchainVersions -Versions $versions | Should -Be "gnustep-base 1.31.1, gnustep-gui 0.32.0, gnustep-make 2.9.3, libobjc2 2.2.0 (packaged release headers); patched variant: 2 carried patch(es)"
    $versions.variant = "stock"
    Format-GpGnustepToolchainVersions -Versions $versions | Should -Be "gnustep-base 1.31.1, gnustep-gui 0.32.0, gnustep-make 2.9.3, libobjc2 2.2.0 (packaged release headers)"
  }

  It "wires the input through the reusable workflow" {
    $workflow = Get-Content -Raw -LiteralPath (Join-Path $script:repoRoot ".github/workflows/package-gnustep-app.yml")
    $workflow | Should -Match '(?m)^\s+toolchain-variant:\r?$'
    $workflow | Should -Match 'Get-GpToolchainVariantProblem -Variant ''\$\{\{ inputs\.toolchain-variant \}\}'''
    $workflow | Should -Match '@\("--variant", "patched"\)'
    $workflow | Should -Match '(?m)^\s+- name: Check Toolchain Variant\r?$'
    $workflow | Should -Match '-ProtectedPaths \$protectedPaths'
  }
}
