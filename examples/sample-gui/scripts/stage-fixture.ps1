[CmdletBinding()]
param(
  [string]$StageRoot = "dist/stage"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$resolvedStageRoot = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $StageRoot))
$appRoot = Join-Path (Join-Path $resolvedStageRoot "app") "SampleGNUstepApp.app"
$resourceRoot = Join-Path $appRoot "Resources"
$runtimeRoot = Join-Path $resolvedStageRoot "runtime"
$runtimeBin = Join-Path $runtimeRoot "bin"
$runtimeFonts = Join-Path (Join-Path $runtimeRoot "etc") "fonts"
$runtimeConfig = Join-Path $runtimeRoot "config"
$runtimeTheme = Join-Path (Join-Path (Join-Path (Join-Path $runtimeRoot "lib") "GNUstep") "Themes") "WinUXTheme.theme"
$metadataRoot = Join-Path $resolvedStageRoot "metadata"
$metadataIcons = Join-Path $metadataRoot "icons"
$metadataLicenses = Join-Path $metadataRoot "licenses"
$logRoot = Join-Path $resolvedStageRoot "logs"
$builtExe = [System.IO.Path]::GetFullPath((Join-Path (Join-Path (Get-Location).Path "out/build") "SampleGNUstepApp.exe"))
$defaultsCandidates = [System.Collections.Generic.List[string]]::new()
$fontConfigCandidates = [System.Collections.Generic.List[string]]::new()
if (-not [string]::IsNullOrWhiteSpace($env:MSYS2_LOCATION)) {
  $defaultsCandidates.Add((Join-Path $env:MSYS2_LOCATION "clang64\\bin\\defaults.exe")) | Out-Null
  $fontConfigCandidates.Add((Join-Path $env:MSYS2_LOCATION "clang64\\etc\\fonts\\fonts.conf")) | Out-Null
}
$defaultsCandidates.Add("C:\msys64\clang64\bin\defaults.exe") | Out-Null
$defaultsCandidates.Add("C:\clang64\bin\defaults.exe") | Out-Null
$fontConfigCandidates.Add("C:\msys64\clang64\etc\fonts\fonts.conf") | Out-Null
$fontConfigCandidates.Add("C:\clang64\etc\fonts\fonts.conf") | Out-Null

if (Test-Path $resolvedStageRoot) {
  Remove-Item -Recurse -Force $resolvedStageRoot
}

foreach ($dir in @($appRoot, $resourceRoot, $runtimeBin, $runtimeFonts, $runtimeConfig, $runtimeTheme, $metadataIcons, $metadataLicenses, $logRoot)) {
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

if (-not (Test-Path $builtExe)) {
  throw "Expected built sample executable not found: $builtExe"
}

Copy-Item -Force $builtExe (Join-Path $appRoot "SampleGNUstepApp.exe")
Set-Content -Path (Join-Path $resourceRoot "Info-gnustep.plist") -Value "fixture plist"

$defaultsSource = $defaultsCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($defaultsSource) {
  Copy-Item -Force $defaultsSource (Join-Path $runtimeBin "defaults.exe")
} else {
  Set-Content -Path (Join-Path $runtimeBin "defaults.exe") -Value "fixture runtime launcher"
}

$fontConfigSource = $fontConfigCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($fontConfigSource) {
  Copy-Item -Force $fontConfigSource (Join-Path $runtimeFonts "fonts.conf")
}

Set-Content -Path (Join-Path $runtimeConfig "theme.conf") -Value "GSTheme=WinUXTheme"
Set-Content -Path (Join-Path $runtimeTheme "WinUXTheme.dll") -Value "fixture theme payload"
Set-Content -Path (Join-Path $metadataIcons "sample-icon.txt") -Value "fixture icon placeholder"
Set-Content -Path (Join-Path $metadataLicenses "SampleGNUstepApp.txt") -Value "SampleGNUstepApp fixture license notice. License: MIT."
Set-Content -Path (Join-Path $metadataLicenses "GNUstep-runtime.txt") -Value "GNUstep runtime fixture notice. License: LGPL-2.1-or-later."
Set-Content -Path (Join-Path $logRoot "stage.txt") -Value "fixture stage complete"

Write-Host "Fixture stage output created at $resolvedStageRoot"
