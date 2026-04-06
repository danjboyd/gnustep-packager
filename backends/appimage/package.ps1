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
. (Join-Path $PSScriptRoot "lib\\appimage.ps1")

$context = Get-GpManifestContext -Path $Manifest -PackageVersion $PackageVersion
$result = Invoke-GpAppImagePackage -Context $context -DryRun:$DryRun -LogPath $LogPath

if ($DryRun) {
  $result | ConvertTo-Json -Depth 20
  exit 0
}

Write-Host "AppImage created: $($result.ArtifactPath)"
if (-not [string]::IsNullOrWhiteSpace($result.ZsyncArtifactPath)) {
  Write-Host "Zsync sidecar: $($result.ZsyncArtifactPath)"
}
Write-Host "Artifact metadata: $($result.MetadataPath)"
if (-not [string]::IsNullOrWhiteSpace($result.UpdateFeedPath)) {
  Write-Host "Update feed: $($result.UpdateFeedPath)"
}
Write-Host "Diagnostics summary: $($result.DiagnosticsPath)"
Write-Host "AppDir: $($result.AppDirRoot)"
Write-Host "AppRun: $($result.AppRunPath)"
Write-Host "Desktop entry: $($result.DesktopEntryPath)"
Write-Host "Notice report: $($result.NoticeReportPath)"
if (-not [string]::IsNullOrWhiteSpace($result.UpdateRuntimeConfigPath)) {
  Write-Host "Updater runtime config: $($result.UpdateRuntimeConfigPath)"
}
