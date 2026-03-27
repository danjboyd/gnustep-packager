Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$manifestPath = Join-Path $repoRoot "examples\\sample-gui\\package.manifest.json"
$toolScript = Join-Path $repoRoot "scripts\\gnustep-packager.ps1"

. (Join-Path $repoRoot "scripts\\lib\\core.ps1")
. (Join-Path $repoRoot "backends\\msi\\lib\\msi.ps1")

& $toolScript -Command build -Manifest $manifestPath
& $toolScript -Command stage -Manifest $manifestPath

$transformContext = Get-GpManifestContext -Path $manifestPath
$transformConfig = Get-GpMsiConfig -Context $transformContext
$transformWorkPaths = Get-GpMsiWorkPaths -Context $transformContext
$transformLogPath = Join-Path $transformConfig.OutputPaths.LogRoot "pester-msi-transform.log"
$transform = Prepare-GpMsiInstallTree -Context $transformContext -Config $transformConfig -WorkPaths $transformWorkPaths -LogPath $transformLogPath

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

function Assert-GpTrue {
  param(
    [bool]$Condition,
    [string]$Message
  )

  if (-not $Condition) {
    throw $Message
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

Describe "Manifest resolution" {
  It "applies defaults and honors package version override" {
    $context = Get-GpManifestContext -Path $manifestPath -PackageVersion "2.5.7-rc1"

    Assert-GpEqual -Actual $context.PackageVersionOverride -Expected "2.5.7-rc1" -Message "Version override should be preserved."
    Assert-GpEqual -Actual $context.Manifest["package"]["version"] -Expected "2.5.7-rc1" -Message "Resolved manifest should use the overridden version."
    Assert-GpEqual -Actual $context.Manifest["backends"]["msi"]["portableArtifactNamePattern"] -Expected "{name}-{version}-win64-portable.zip" -Message "MSI portable artifact default should be present."
  }

  It "resolves enabled backends from the manifest" {
    $context = Get-GpManifestContext -Path $manifestPath

    Assert-GpEqual -Actual @(Get-GpEnabledBackends -Manifest $context.Manifest) -Expected @("msi") -Message "Enabled backends should match the sample manifest."
  }
}

Describe "MSI versioning and artifact rules" {
  It "normalizes semantic versions for MSI upgrade semantics" {
    Assert-GpEqual -Actual (Normalize-GpMsiVersion -Version "1.2.3-rc1+7") -Expected "1.2.3.1" -Message "MSI version normalization should keep the first four numeric groups."
  }

  It "builds artifact names from the overridden package version" {
    $context = Get-GpManifestContext -Path $manifestPath -PackageVersion "3.4.5"
    $config = Get-GpMsiConfig -Context $context

    Assert-GpEqual -Actual $config.ArtifactPlan.ArtifactName -Expected "SampleGNUstepApp-3.4.5-win64.msi" -Message "MSI artifact name should track the overridden version."
    Assert-GpEqual -Actual $config.PortablePlan.ArtifactName -Expected "SampleGNUstepApp-3.4.5-win64-portable.zip" -Message "Portable artifact name should track the overridden version."
    Assert-GpEqual -Actual $config.MsiVersion -Expected "3.4.5.0" -Message "MSI numeric version should be normalized from the overridden version."
  }

  It "computes the per-user install root used by validation" {
    $context = Get-GpManifestContext -Path $manifestPath
    $config = Get-GpMsiConfig -Context $context

    Assert-GpMatch -Actual (Get-GpMsiInstallPathGuess -Config $config) -Pattern ([regex]::Escape((Join-Path $env:LOCALAPPDATA "SampleGNUstepApp"))) -Message "Validation install path should point to LocalAppData for per-user installs."
  }
}

Describe "MSI transform behavior" {
  It "copies the staged payload into the install tree" {
    Assert-GpTrue -Condition (Test-Path (Join-Path $transform.InstallRoot "app\\SampleGNUstepApp.app\\SampleGNUstepApp.exe")) -Message "Transformed install tree should contain the app executable."
    Assert-GpTrue -Condition (Test-Path (Join-Path $transform.InstallRoot "runtime\\bin\\defaults.exe")) -Message "Transformed install tree should contain the staged runtime seed."
    Assert-GpTrue -Condition (Test-Path (Join-Path $transform.InstallRoot "metadata\\icons\\sample-icon.txt")) -Message "Transformed install tree should contain staged metadata."
  }

  It "generates launcher output and config" {
    Assert-GpTrue -Condition (Test-Path $transform.LauncherPath) -Message "Launcher executable should be generated."
    Assert-GpTrue -Condition (Test-Path $transform.LauncherConfigPath) -Message "Launcher config should be generated."
  }

  It "writes the launch contract into the generated launcher config" {
    $configText = Get-Content -Raw -Path $transform.LauncherConfigPath

    Assert-GpMatch -Actual $configText -Pattern "entryRelativePath=app/SampleGNUstepApp.app/SampleGNUstepApp.exe" -Message "Launcher config should contain the entry path."
    Assert-GpMatch -Actual $configText -Pattern "pathPrepend=runtime/bin" -Message "Launcher config should contain runtime PATH additions."
    Assert-GpMatch -Actual $configText -Pattern "env=GNUSTEP_PATHPREFIX_LIST=\{@runtimeRoot\}" -Message "Launcher config should preserve runtime token expansion."
  }
}

Describe "Shared pipeline wrapper" {
  It "supports dry-run packaging with a version override" {
    try {
      & (Join-Path $repoRoot "scripts\\run-packaging-pipeline.ps1") `
        -Manifest $manifestPath `
        -Backend msi `
        -PackageVersion "9.9.9" `
        -SkipBuild `
        -SkipStage `
        -SkipSharedValidation `
        -SkipBackendValidation `
        -DryRun | Out-Null
    } catch {
      throw "Dry-run pipeline wrapper should not throw. Error: $($_.Exception.Message)"
    }
  }
}
