Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Describe "MSI diagnostics helpers" {
  BeforeAll {
    function Assert-GpEqual {
      param(
        [object]$Actual,
        [object]$Expected,
        [string]$Message
      )

      if ($Actual -is [System.Array] -or $Expected -is [System.Array]) {
        $actualJson = ConvertTo-Json @($Actual) -Compress
        $expectedJson = ConvertTo-Json @($Expected) -Compress
        if ($actualJson -ne $expectedJson) {
          throw "$Message Expected: $expectedJson Actual: $actualJson"
        }
        return
      }

      if ($Actual -ne $Expected) {
        throw "$Message Expected: $Expected Actual: $Actual"
      }
    }

    function Assert-GpMatch {
      param(
        [string]$Actual,
        [string]$Pattern,
        [string]$Message
      )

      if ($Actual -notmatch $Pattern) {
        throw "$Message Pattern: $Pattern Actual: $Actual"
      }
    }

    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
    . (Join-Path $script:repoRoot "backends\\msi\\lib\\msi.ps1")
  }

  It "reports missing dependencies for runtime-extension DLLs with target provenance" {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-msi-runtime-audit-" + [guid]::NewGuid().ToString("N"))
    $appPath = Join-Path $tempRoot "app\\SampleGNUstepApp.app\\SampleGNUstepApp.exe"
    $bundlePath = Join-Path $tempRoot "runtime\\lib\\GNUstep\\Bundles\\libgnustep-back-032.bundle\\libgnustep-back-032.dll"
    $logPath = Join-Path $tempRoot "runtime-audit.log"
    $originalImportFunction = ${function:Get-GpPeImportedDllNames}

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $appPath) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $bundlePath) | Out-Null
    Set-Content -Path $appPath -Value "fixture"
    Set-Content -Path $bundlePath -Value "fixture"

    try {
      ${function:Get-GpPeImportedDllNames} = {
        param([string]$Path)

        $leaf = [System.IO.Path]::GetFileName($Path)
        switch ($leaf.ToLowerInvariant()) {
          "samplegnustepapp.exe" { return @("kernel32.dll") }
          "libgnustep-back-032.dll" { return @("libcairo-2.dll") }
          default { return @() }
        }
      }

      $context = [pscustomobject]@{
        Manifest = @{
          launch = @{
            entryRelativePath = "app/SampleGNUstepApp.app/SampleGNUstepApp.exe"
          }
        }
      }
      $config = [pscustomobject]@{
        RuntimeRootRelative = "runtime"
        RuntimeSeedPaths = @()
      }

      $analysis = Get-GpMsiRuntimeClosureAnalysis -Context $context -Config $config -InstallRoot $tempRoot -SearchRoots @() -LogPath $logPath
      $groups = @(Get-GpMsiMissingDependencyGroups -Analysis $analysis)
      $primaryMessage = Get-GpMsiPrimaryMissingDependencyMessage -Analysis $analysis

      Assert-GpEqual -Actual @($analysis.MissingDependencyNames) -Expected @("libcairo-2.dll") -Message "Runtime closure analysis should report the missing non-system dependency."
      Assert-GpEqual -Actual $groups.Count -Expected 1 -Message "Runtime closure analysis should group missing dependencies by target binary."
      Assert-GpMatch -Actual $groups[0].TargetRelativePath -Pattern "runtime/lib/GNUstep/Bundles/libgnustep-back-032\.bundle/libgnustep-back-032\.dll$" -Message "The missing dependency group should point at the bundle DLL."
      Assert-GpEqual -Actual $groups[0].TargetRole -Expected "runtime-extension" -Message "Bundle DLLs should be classified as runtime extensions."
      Assert-GpMatch -Actual $primaryMessage -Pattern "libgnustep-back-032\.dll" -Message "Primary missing-dependency diagnostics should mention the requiring DLL."
      Assert-GpMatch -Actual $primaryMessage -Pattern "libcairo-2\.dll" -Message "Primary missing-dependency diagnostics should mention the missing DLL."
    } finally {
      ${function:Get-GpPeImportedDllNames} = $originalImportFunction
      if (Test-Path $tempRoot) {
        Remove-Item -Recurse -Force $tempRoot
      }
    }
  }
}
