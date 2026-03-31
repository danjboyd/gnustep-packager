[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Manifest,
  [string]$PackageVersion,
  [switch]$DryRun,
  [switch]$RunSmoke,
  [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "..\\..\\scripts\\lib\\core.ps1")
. (Join-Path $PSScriptRoot "lib\\appimage.ps1")

$context = Get-GpManifestContext -Path $Manifest -PackageVersion $PackageVersion
$result = Invoke-GpAppImageValidation -Context $context -DryRun:$DryRun -RunSmoke:$RunSmoke -LogPath $LogPath

if ($DryRun) {
  $result | ConvertTo-Json -Depth 20
  exit 0
}

Write-Host "AppImage validation completed. Extracted root: $($result.ExpandedRoot)"
Write-Host "Extract log: $($result.ExtractLog)"
if (-not [string]::IsNullOrWhiteSpace($result.SmokeLog)) {
  Write-Host "Smoke log: $($result.SmokeLog)"
}
