[CmdletBinding()]
param(
  [string]$Path = "tests",
  [switch]$CI
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

. (Join-Path $PSScriptRoot "lib\\core.ps1")

$testPath = Resolve-GpPathRelativeToBase -BasePath $repoRoot -Path $Path
Import-Module Pester -ErrorAction Stop

if (Get-Command New-PesterConfiguration -ErrorAction SilentlyContinue) {
  $configuration = New-PesterConfiguration
  $configuration.Run.Path = $testPath
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
    Script = $testPath
    PassThru = $true
  }

  if ($CI) {
    $resultsRoot = Ensure-GpDirectory -Path (Join-Path $repoRoot "dist\\test-results")
    $invokeArgs["OutputFile"] = (Join-Path $resultsRoot "pester-results.xml")
    $invokeArgs["OutputFormat"] = "NUnitXml"
  }

  $results = Invoke-Pester @invokeArgs
}

if ($results.FailedCount -gt 0) {
  exit 1
}
