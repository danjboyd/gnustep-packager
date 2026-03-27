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

$context = Get-GpManifestContext -Path $Manifest -PackageVersion $PackageVersion
$backend = "appimage"
$artifactPlan = Get-GpArtifactPlan -Context $context -Backend $backend
$launch = Get-GpLaunchContract -Context $context

$message = "AppImage backend dispatch reached. Artifact target: $($artifactPlan.ArtifactPath)"
Write-Host $message
if ($LogPath) {
  Set-Content -Path $LogPath -Value $message
}

if ($DryRun) {
  [pscustomobject]@{
    backend = $backend
    manifest = $context.ManifestPath
    artifactPath = $artifactPlan.ArtifactPath
    entryPath = $launch.EntryPath
    mode = "dry-run"
  } | ConvertTo-Json -Depth 10
  exit 0
}

throw "AppImage backend implementation is not complete yet. Use -DryRun during phases 1 and 2."
