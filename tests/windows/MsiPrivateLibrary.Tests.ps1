Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# An app that links its own DLL, built in the app's tree and not part of
# GNUstep (AIManager's Trellis, for example). backends.msi.runtimeSearchRoots
# names the build directory, and the runtime closure copies the DLL into
# runtime\bin, which the launcher puts on PATH.
Describe "MSI: a private DLL built in the app's tree" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
    . (Join-Path $script:repoRoot "backends\\msi\\lib\\msi.ps1")

    $script:workRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-msi-privlib-" + [guid]::NewGuid().ToString("N"))
    $script:buildRoot = Join-Path $script:workRoot "build"
    New-Item -ItemType Directory -Force -Path $script:buildRoot | Out-Null
    Set-Content -Path (Join-Path $script:buildRoot "private.c") -Value '__declspec(dllexport) int gp_private_answer(void) { return 42; }'
    Set-Content -Path (Join-Path $script:buildRoot "app.c") -Value @(
      '#include <stdio.h>'
      '__declspec(dllimport) int gp_private_answer(void);'
      'int main(void) { printf("answer=%d\n", gp_private_answer()); return 0; }'
    )

    $clang = Get-GpPreferredWindowsClang
    & $clang -shared -o (Join-Path $script:buildRoot "gpprivate.dll") "-Wl,--out-implib,$(Join-Path $script:buildRoot 'libgpprivate.dll.a')" (Join-Path $script:buildRoot "private.c")
    if ($LASTEXITCODE -ne 0) { throw "building gpprivate.dll failed" }
    & $clang -o (Join-Path $script:buildRoot "Demo.exe") (Join-Path $script:buildRoot "app.c") "-L$($script:buildRoot)" -lgpprivate
    if ($LASTEXITCODE -ne 0) { throw "building Demo.exe failed" }

    $script:context = [pscustomobject]@{
      Manifest = @{ launch = @{ entryRelativePath = "app/Demo.app/Demo.exe" } }
    }

    function New-GpInstallTree {
      param([string]$Name)
      $root = Join-Path $script:workRoot $Name
      $appDir = New-Item -ItemType Directory -Force -Path (Join-Path $root "app/Demo.app")
      New-Item -ItemType Directory -Force -Path (Join-Path $root "runtime/bin") | Out-Null
      Copy-Item (Join-Path $script:buildRoot "Demo.exe") $appDir.FullName
      return $root
    }
  }

  AfterAll {
    if ($script:workRoot -and (Test-Path $script:workRoot)) {
      Remove-Item -Recurse -Force $script:workRoot
    }
  }

  It "copies the DLL from runtimeSearchRoots into runtime\bin, and the app runs with only that on PATH" {
    $root = New-GpInstallTree -Name "search-root"
    $config = [pscustomobject]@{
      RuntimeRootRelative = "runtime"
      RuntimeSeedPaths = @()
      RuntimeSearchRoots = [string[]]@($script:buildRoot)
    }

    $missing = @(Complete-GpMsiRuntimeClosure -Context $script:context -Config $config -InstallRoot $root -LogPath (Join-Path $script:workRoot "search-root.log"))
    $missing.Count | Should -Be 0 -Because ([string]::Join(", ", $missing))
    Join-Path $root "runtime/bin/gpprivate.dll" | Should -Exist

    # Run it the way the launcher does: runtime\bin on PATH, not the build directory.
    $savedPath = $env:PATH
    try {
      $env:PATH = (Join-Path $root "runtime\bin") + ";" + [Environment]::GetFolderPath("System")
      $output = & (Join-Path $root "app/Demo.app/Demo.exe")
      $LASTEXITCODE | Should -Be 0
      $output | Should -Be "answer=42"
    } finally {
      $env:PATH = $savedPath
    }
  }

  It "reports the DLL as missing when runtimeSearchRoots doesn't name the build directory" {
    $root = New-GpInstallTree -Name "no-search-root"
    $config = [pscustomobject]@{
      RuntimeRootRelative = "runtime"
      RuntimeSeedPaths = @()
      RuntimeSearchRoots = [string[]]@()
    }

    $missing = @(Complete-GpMsiRuntimeClosure -Context $script:context -Config $config -InstallRoot $root -LogPath (Join-Path $script:workRoot "no-search-root.log"))
    $missing | Should -Contain "gpprivate.dll"
  }
}
