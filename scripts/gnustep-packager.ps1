[CmdletBinding()]
param(
  [ValidateSet("manifest-check", "resolve-manifest", "describe", "launch-plan", "backend-list", "build", "stage", "package", "validate")]
  [string]$Command = "describe",
  [string]$Manifest = "examples/sample-gui/package.manifest.json",
  [string]$Backend,
  [string]$PackageVersion,
  [switch]$DryRun,
  [switch]$RunSmoke
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib/core.ps1")

$context = Get-GpManifestContext -Path $Manifest -PackageVersion $PackageVersion
$manifestData = $context.Manifest
$issues = @()
$issues += @(Test-GpManifestSchema -Path $context.ManifestPath)
$issues += @(Test-GpManifest -Manifest $manifestData)

if ($issues.Count -gt 0) {
  Write-Host "Manifest validation failed: $($context.ManifestPath)"
  foreach ($issue in $issues) {
    Write-Host "  - $issue"
  }
  exit 1
}

$summary = Get-GpManifestSummary -Manifest $manifestData
$enabledBackends = @($summary.EnabledBackends)
$enabledBackendText = if ($enabledBackends.Count -gt 0) { [string]::Join(', ', $enabledBackends) } else { "(none)" }

switch ($Command) {
  "manifest-check" {
    Write-Host "Manifest is valid: $($context.ManifestPath)"
    Write-Host "Package: $($summary.Name) $($summary.Version)"
    if ($summary.Profiles.Count -gt 0) {
      Write-Host "Profiles: $([string]::Join(', ', $summary.Profiles))"
    }
    Write-Host "Compliance notices: $($summary.ComplianceNoticeCount)"
    Write-Host "Enabled backends: $enabledBackendText"
    break
  }

  "resolve-manifest" {
    $manifestData | ConvertTo-Json -Depth 20
    break
  }

  "backend-list" {
    foreach ($backendName in $enabledBackends) {
      Write-Output $backendName
    }
    break
  }

  "launch-plan" {
    Get-GpLaunchContract -Context $context | ConvertTo-Json -Depth 20
    break
  }

  "describe" {
    Write-Host "Manifest: $($context.ManifestPath)"
    Write-Host "Package ID: $($summary.PackageId)"
    Write-Host "Name: $($summary.Name)"
    Write-Host "Version: $($summary.Version)"
    if (-not [string]::IsNullOrWhiteSpace($context.PackageVersionOverride)) {
      Write-Host "Version override: $($context.PackageVersionOverride)"
    }
    Write-Host "Manufacturer: $($summary.Manufacturer)"
    Write-Host "Shell kind: $($summary.ShellKind)"
    if ($summary.Profiles.Count -gt 0) {
      Write-Host "Profiles: $([string]::Join(', ', $summary.Profiles))"
    }
    Write-Host "Compliance notices: $($summary.ComplianceNoticeCount)"
    Write-Host "Stage root: $($summary.StageRoot)"
    Write-Host "Entry path: $($summary.EntryRelative)"
    Write-Host "Build command: $($summary.BuildCommand)"
    Write-Host "Stage command: $($summary.StageCommand)"
    Write-Host "Package root: $($summary.PackageRoot)"
    Write-Host "Log root: $($summary.LogRoot)"
    Write-Host "Validation kind: $($summary.ValidationKind)"
    if ($summary.UpdatesEnabled) {
      Write-Host "Updates: enabled ($($summary.UpdateChannel))"
    } else {
      Write-Host "Updates: disabled"
    }
    Write-Host "Enabled backends: $enabledBackendText"
    break
  }

  "build" {
    $result = Invoke-GpPipelineCommand -Context $context -StepName "build" -DryRun:$DryRun
    if ($DryRun) {
      $result | ConvertTo-Json -Depth 10
    } else {
      Write-Host "Build completed. Log: $($result.LogPath)"
    }
    break
  }

  "stage" {
    $result = Invoke-GpPipelineCommand -Context $context -StepName "stage" -DryRun:$DryRun
    if ($DryRun) {
      $result | ConvertTo-Json -Depth 10
    } else {
      Write-Host "Stage completed. Output root: $($result.OutputRoot)"
      Write-Host "Log: $($result.LogPath)"
    }
    break
  }

  "package" {
    $backendName = Resolve-GpBackendName -Manifest $manifestData -RequestedBackend $Backend
    $backendScript = Join-Path $context.ToolRoot ("backends\\{0}\\package.ps1" -f $backendName)
    if (-not (Test-Path $backendScript)) {
      throw "Backend package script not found: $backendScript"
    }

    $backendLogPath = New-GpCommandLogPath -Context $context -CommandName ("package-" + $backendName)
    & $backendScript -Manifest $context.ManifestPath -PackageVersion $context.PackageVersionOverride -DryRun:$DryRun -LogPath $backendLogPath
    if (-not $DryRun) {
      Write-Host "Backend package command completed. Log: $backendLogPath"
    }
    break
  }

  "validate" {
    if (-not [string]::IsNullOrWhiteSpace($Backend)) {
      $backendName = Resolve-GpBackendName -Manifest $manifestData -RequestedBackend $Backend
      $backendScript = Join-Path $context.ToolRoot ("backends\\{0}\\validate.ps1" -f $backendName)
      if (-not (Test-Path $backendScript)) {
        throw "Backend validation script not found: $backendScript"
      }

      $backendLogPath = New-GpCommandLogPath -Context $context -CommandName ("validate-" + $backendName)
      & $backendScript -Manifest $context.ManifestPath -PackageVersion $context.PackageVersionOverride -DryRun:$DryRun -RunSmoke:$RunSmoke -LogPath $backendLogPath
      if (-not $DryRun) {
        Write-Host "Backend validation completed. Log: $backendLogPath"
      }
    } else {
      $result = Invoke-GpSharedValidation -Context $context -DryRun:$DryRun
      if ($DryRun) {
        $result | ConvertTo-Json -Depth 20
      } else {
        Write-Host "Shared validation passed. Log: $($result.LogPath)"
      }
    }
    break
  }
}
