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
. (Join-Path $PSScriptRoot "lib\\msi.ps1")

$context = Get-GpManifestContext -Path $Manifest -PackageVersion $PackageVersion
$result = Invoke-GpMsiValidation -Context $context -DryRun:$DryRun -RunSmoke:$RunSmoke -LogPath $LogPath

if ($DryRun) {
  $result | ConvertTo-Json -Depth 20
  exit 0
}

Write-Host "MSI validation passed: $($result.ArtifactPath)"
Write-Host "Installed path probe: $($result.InstallPath)"
Write-Host "Validation log: $($result.LogPath)"
