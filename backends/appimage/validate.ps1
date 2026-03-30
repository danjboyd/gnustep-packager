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

$context = Get-GpManifestContext -Path $Manifest -PackageVersion $PackageVersion
$backend = "appimage"
$artifactPlan = Get-GpArtifactPlan -Context $context -Backend $backend
$validationPlan = Get-GpValidationPlan -Context $context
$backendSupport = Get-GpBackendSupport -Backend $backend

if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
  Ensure-GpDirectory -Path (Split-Path -Parent $LogPath) | Out-Null
  Set-Content -Path $LogPath -Value ("[{0}] AppImage validation stub" -f (Get-Date).ToString("o"))
}

if ($DryRun) {
  [pscustomobject]@{
    backend = $backend
    mode = "dry-run"
    manifest = $context.ManifestPath
    artifactPath = $artifactPlan.ArtifactPath
    hostPlatform = $backendSupport.HostPlatform
    requiredPlatform = $backendSupport.RequiredPlatform
    hostSupported = [bool]$backendSupport.Supported
    runSmoke = [bool]$RunSmoke
    timeoutSeconds = $validationPlan.TimeoutSeconds
    logPath = $LogPath
  } | ConvertTo-Json -Depth 10
  exit 0
}

if (-not $backendSupport.Supported) {
  throw "AppImage validation requires host platform '$($backendSupport.RequiredPlatform)'. Current host: '$($backendSupport.HostPlatform)'."
}

throw "AppImage validation is not complete yet. Phase 8 remains."
