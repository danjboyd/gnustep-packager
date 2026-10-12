[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Manifest,
  [string]$PackageVersion,
  [string]$Platform,
  [switch]$DryRun,
  [switch]$RunSmoke,
  [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "..\\..\\scripts\\lib\\core.ps1")
. (Join-Path $PSScriptRoot "lib\\dmg.ps1")

$context = Get-GpManifestContext -Path $Manifest -PackageVersion $PackageVersion -Backend "dmg" -Platform $Platform
$result = Invoke-GpDmgValidation -Context $context -DryRun:$DryRun -RunSmoke:$RunSmoke -LogPath $LogPath

if ($DryRun) {
  $result | ConvertTo-Json -Depth 20
  exit 0
}

Write-Host "DMG validation completed: $($result.ArtifactPath)"
Write-Host "Gatekeeper: $(if ($result.GatekeeperAccepted) { 'accepted' } else { 'rejected (recorded, not required)' })"
if (-not [string]::IsNullOrWhiteSpace($result.SmokeLog)) {
  Write-Host "Smoke log: $($result.SmokeLog)"
}
Write-Host "Validation summary: $($result.SummaryPath)"
