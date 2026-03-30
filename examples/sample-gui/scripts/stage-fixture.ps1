[CmdletBinding()]
param(
  [string]$StageRoot = "dist/stage"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$resolvedStageRoot = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $StageRoot))
$appRoot = Join-Path $resolvedStageRoot "app\\SampleGNUstepApp.app"
$resourceRoot = Join-Path $appRoot "Resources"
$runtimeBin = Join-Path $resolvedStageRoot "runtime\\bin"
$runtimeFonts = Join-Path $resolvedStageRoot "runtime\\etc\\fonts"
$runtimeConfig = Join-Path $resolvedStageRoot "runtime\\config"
$metadataIcons = Join-Path $resolvedStageRoot "metadata\\icons"
$metadataLicenses = Join-Path $resolvedStageRoot "metadata\\licenses"
$logRoot = Join-Path $resolvedStageRoot "logs"
$builtExe = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path "out\\build\\SampleGNUstepApp.exe"))
$defaultsCandidates = @(
  "C:\msys64\clang64\bin\defaults.exe",
  "C:\clang64\bin\defaults.exe"
)
$fontConfigCandidates = @(
  "C:\msys64\clang64\etc\fonts\fonts.conf",
  "C:\clang64\etc\fonts\fonts.conf"
)

if (Test-Path $resolvedStageRoot) {
  Remove-Item -Recurse -Force $resolvedStageRoot
}

foreach ($dir in @($appRoot, $resourceRoot, $runtimeBin, $runtimeFonts, $runtimeConfig, $metadataIcons, $metadataLicenses, $logRoot)) {
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
Set-Content -Path (Join-Path $metadataIcons "sample-icon.txt") -Value "fixture icon placeholder"
Set-Content -Path (Join-Path $metadataLicenses "SampleGNUstepApp.txt") -Value "SampleGNUstepApp fixture license notice. License: MIT."
Set-Content -Path (Join-Path $metadataLicenses "GNUstep-runtime.txt") -Value "GNUstep runtime fixture notice. License: LGPL-2.1-or-later."
Set-Content -Path (Join-Path $logRoot "stage.txt") -Value "fixture stage complete"

Write-Host "Fixture stage output created at $resolvedStageRoot"
