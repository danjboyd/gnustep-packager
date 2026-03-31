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
Write-Host "Artifact metadata: $($result.MetadataPath)"
Write-Host "Diagnostics summary: $($result.DiagnosticsPath)"
Write-Host "AppDir: $($result.AppDirRoot)"
Write-Host "AppRun: $($result.AppRunPath)"
Write-Host "Desktop entry: $($result.DesktopEntryPath)"
Write-Host "Notice report: $($result.NoticeReportPath)"
