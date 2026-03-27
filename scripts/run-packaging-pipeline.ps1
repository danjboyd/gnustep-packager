[CmdletBinding()]
param(
  [string]$Manifest = "examples/sample-gui/package.manifest.json",
  [string]$Backend,
  [string]$PackageVersion,
  [switch]$SkipBuild,
  [switch]$SkipStage,
  [switch]$SkipSharedValidation,
  [switch]$SkipPackage,
  [switch]$SkipBackendValidation,
  [switch]$RunSmoke,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$toolScript = Join-Path $PSScriptRoot "gnustep-packager.ps1"

function Invoke-GpPipelineStep {
  param(
    [Parameter(Mandatory = $true)]
    [string]$CommandName,
    [string]$BackendName,
    [switch]$UseRunSmoke
  )

  $parameters = @{
    Command = $CommandName
    Manifest = $Manifest
  }

  if (-not [string]::IsNullOrWhiteSpace($BackendName)) {
    $parameters["Backend"] = $BackendName
  }

  if (-not [string]::IsNullOrWhiteSpace($PackageVersion)) {
    $parameters["PackageVersion"] = $PackageVersion
  }

  if ($UseRunSmoke) {
    $parameters["RunSmoke"] = $true
  }

  if ($DryRun) {
    $parameters["DryRun"] = $true
  }

  & $toolScript @parameters
}

if (-not $SkipBuild) {
  Invoke-GpPipelineStep -CommandName "build"
}

if (-not $SkipStage) {
  Invoke-GpPipelineStep -CommandName "stage"
}

if (-not $SkipSharedValidation) {
  Invoke-GpPipelineStep -CommandName "validate"
}

if (-not $SkipPackage) {
  Invoke-GpPipelineStep -CommandName "package" -BackendName $Backend
}

if (-not $SkipBackendValidation) {
  Invoke-GpPipelineStep -CommandName "validate" -BackendName $Backend -UseRunSmoke:$RunSmoke
}
