[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Manifest,
  [string]$PackageVersion,
  [string]$Platform,
  [switch]$DryRun,
  [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "..\\..\\scripts\\lib\\core.ps1")
. (Join-Path $PSScriptRoot "lib\\dmg.ps1")

$context = Get-GpManifestContext -Path $Manifest -PackageVersion $PackageVersion -Backend "dmg" -Platform $Platform
$result = Invoke-GpDmgPackage -Context $context -DryRun:$DryRun -LogPath $LogPath

if ($DryRun) {
  $result | ConvertTo-Json -Depth 20
  exit 0
}

Write-Host "DMG created: $($result.ArtifactPath) ($([Math]::Round($result.SizeBytes / 1MB, 1)) MB, $($result.Arch))"
Write-Host "Volume name: $($result.VolumeName)"
Write-Host "Finder layout: $(if ($result.FinderLayoutApplied) { 'applied' } else { 'not applied' }) ($($result.FinderLayoutReason))"
Write-Host "Notarization: $($result.NotarizationStatus)"
Write-Host "Artifact metadata: $($result.MetadataPath)"
Write-Host "Diagnostics summary: $($result.DiagnosticsPath)"
