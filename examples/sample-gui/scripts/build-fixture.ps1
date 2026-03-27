[CmdletBinding()]
param(
  [string]$OutRoot = "out/build"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$resolvedRoot = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $OutRoot))
New-Item -ItemType Directory -Force -Path $resolvedRoot | Out-Null

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourcePath = Join-Path (Split-Path -Parent $scriptRoot) "src\\SampleGNUstepApp.c"
$outputExe = Join-Path $resolvedRoot "SampleGNUstepApp.exe"

$clangCandidates = @(
  "C:\msys64\clang64\bin\clang.exe",
  "C:\msys64\mingw64\bin\clang.exe"
)
$clang = $null
foreach ($candidate in $clangCandidates) {
  if (Test-Path $candidate) {
    $clang = $candidate
    break
  }
}
if (-not $clang) {
  $clang = (Get-Command clang -ErrorAction SilentlyContinue | Select-Object -First 1).Source
}
if (-not $clang) {
  throw "clang not found. The sample fixture currently expects a Windows-capable clang in PATH."
}

& $clang "-Os" "-municode" "-mwindows" "-o" $outputExe $sourcePath
if ($LASTEXITCODE -ne 0) {
  throw "clang failed while building the sample fixture executable."
}

Set-Content -Path (Join-Path $resolvedRoot "build.txt") -Value "sample fixture build output"
Write-Host "Fixture build output created at $resolvedRoot"
