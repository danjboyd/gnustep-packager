[CmdletBinding()]
param(
  [string[]]$Path,
  [switch]$CI
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

. (Join-Path $PSScriptRoot "lib\\core.ps1")

function Install-GpPester {
  if (Get-Module -ListAvailable Pester) {
    return
  }

  Write-Host "Pester not found. Bootstrapping it into the current user module path."
  if (Get-Command Install-PSResource -ErrorAction SilentlyContinue) {
    Install-PSResource -Name Pester -Scope CurrentUser -TrustRepository -Quiet -ErrorAction Stop
    return
  }

  if (Get-Command Install-Module -ErrorAction SilentlyContinue) {
    Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck -ErrorAction Stop
    return
  }

  throw "Pester is not installed and no supported PowerShell package installer is available."
}

function Get-GpDefaultTestPaths {
  $paths = [System.Collections.Generic.List[string]]::new()
  $paths.Add((Join-Path $repoRoot "tests\\shared")) | Out-Null
  if ($IsWindows) {
    $paths.Add((Join-Path $repoRoot "tests\\windows")) | Out-Null
  } elseif ($IsLinux) {
    $paths.Add((Join-Path $repoRoot "tests\\linux")) | Out-Null
  } else {
    $paths.Add((Join-Path $repoRoot "tests")) | Out-Null
  }

  return [string[]]@($paths.ToArray())
}

$testPaths = @()
if ($PSBoundParameters.ContainsKey("Path")) {
  foreach ($item in @($Path)) {
    $testPaths += @(Resolve-GpPathRelativeToBase -BasePath $repoRoot -Path $item)
  }
} else {
  $testPaths = @(Get-GpDefaultTestPaths)
}

Install-GpPester
Import-Module Pester -ErrorAction Stop

if (Get-Command New-PesterConfiguration -ErrorAction SilentlyContinue) {
  $configuration = New-PesterConfiguration
  $configuration.Run.Path = @($testPaths)
  $configuration.Run.Exit = $false
  $configuration.Output.Verbosity = "Detailed"

  if ($CI) {
    $resultsRoot = Ensure-GpDirectory -Path (Join-Path $repoRoot "dist\\test-results")
    $configuration.TestResult.Enabled = $true
    $configuration.TestResult.OutputPath = Join-Path $resultsRoot "pester-results.xml"
    $configuration.TestResult.OutputFormat = "NUnitXml"
  }

  $results = Invoke-Pester -Configuration $configuration
} else {
  $invokeArgs = @{
    Script = @($testPaths)
    PassThru = $true
  }

  if ($CI) {
    $resultsRoot = Ensure-GpDirectory -Path (Join-Path $repoRoot "dist\\test-results")
    $invokeArgs["OutputFile"] = (Join-Path $resultsRoot "pester-results.xml")
    $invokeArgs["OutputFormat"] = "NUnitXml"
  }

  $results = Invoke-Pester @invokeArgs
}

$failedCount = 0
if ($null -ne $results) {
  $failedCount = [int]($results.FailedCount)
  if (($failedCount -le 0) -and $results.PSObject.Properties["Failed"]) {
    $failedCount = [int]@($results.Failed).Count
  }
  if (($failedCount -le 0) -and $results.PSObject.Properties["Result"] -and $results.Result -eq "Failed") {
    $failedCount = 1
  }
}

if ((($null -ne $global:LASTEXITCODE) -and ($global:LASTEXITCODE -ne 0)) -or ($failedCount -gt 0)) {
  exit 1
}
