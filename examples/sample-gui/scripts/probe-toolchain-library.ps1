[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Module,
  [Parameter(Mandatory = $true)]
  [string]$Dll,
  [string]$StageRoot = ""
)

# The MSYS2 dependency fixture (package.msys2-library.manifest.json). An app
# built with `gnustep build` runs inside the gnustep-cli-new toolchain's own
# MSYS2 runtime, so the library declared under hostDependencies.windows.
# msys2Packages must be found by the toolchain's pkg-config, not the
# setup-msys2 shell's, and its DLL must come from the toolchain for the MSI
# to stage it. Without -StageRoot this checks; with it, it also stages the DLL.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = $env:GP_GNUSTEP_CLI_ROOT
if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root)) {
  throw "GP_GNUSTEP_CLI_ROOT isn't set to the gnustep-cli-new toolchain."
}

$pkgConfig = @(
  "clang64\bin\pkg-config.exe", "clang64\bin\pkgconf.exe", "usr\bin\pkg-config.exe", "usr\bin\pkgconf.exe"
) | ForEach-Object { Join-Path $root $_ } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $pkgConfig) {
  throw "The toolchain at $root has no pkg-config."
}

# Only the toolchain's own search path: what `gnustep build` sees.
$env:PKG_CONFIG_PATH = ""
Remove-Item Env:PKG_CONFIG_LIBDIR -ErrorAction SilentlyContinue
& $pkgConfig --exists $Module
if ($LASTEXITCODE -ne 0) {
  & $pkgConfig --variable pc_path pkg-config 2>$null | ForEach-Object { Write-Host "pkg-config search path: $_" }
  throw "The toolchain's pkg-config ($pkgConfig) doesn't find '$Module'. A library declared under hostDependencies.windows.msys2Packages didn't reach the toolchain."
}
$version = (& $pkgConfig --modversion $Module | Select-Object -First 1)
Write-Host "Toolchain pkg-config ($pkgConfig) finds $Module $version"

$dllPath = Join-Path $root "clang64\bin\$Dll"
if (-not (Test-Path -LiteralPath $dllPath)) {
  throw "$Dll isn't in the toolchain's clang64\bin, so the MSI couldn't stage it."
}
Write-Host "Toolchain has $dllPath"

if (-not [string]::IsNullOrWhiteSpace($StageRoot)) {
  $runtimeBin = Join-Path ([System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $StageRoot))) "runtime\bin"
  New-Item -ItemType Directory -Force -Path $runtimeBin | Out-Null
  Copy-Item -Force -LiteralPath $dllPath -Destination (Join-Path $runtimeBin $Dll)
  Write-Host "Staged $Dll into $runtimeBin"
}
