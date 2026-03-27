[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Manifest,
  [string]$PackageVersion,
  [switch]$DryRun,
  [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "..\\..\\scripts\\lib\\core.ps1")
. (Join-Path $PSScriptRoot "lib\\msi.ps1")

$context = Get-GpManifestContext -Path $Manifest -PackageVersion $PackageVersion
$result = Invoke-GpMsiPackage -Context $context -DryRun:$DryRun -LogPath $LogPath

if ($DryRun) {
  $result | ConvertTo-Json -Depth 20
  exit 0
}

Write-Host "MSI created: $($result.ArtifactPath)"
Write-Host "Portable ZIP created: $($result.PortableArtifactPath)"
Write-Host "Launcher: $($result.LauncherPath)"
if ($result.UnresolvedDependencies.Count -gt 0) {
  Write-Host "Unresolved runtime dependencies: $([string]::Join(', ', $result.UnresolvedDependencies))"
}
