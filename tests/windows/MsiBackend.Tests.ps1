Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Describe "MSI backend" {
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

    function Assert-GpFalse {
      param(
        [bool]$Condition,
        [string]$Message
      )

      if ($Condition) {
        throw $Message
      }
    }

    function New-GpSiblingManifest {
      param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Customize
      )

      $manifest = Get-GpJsonFile -Path $script:manifestPath
      & $Customize $manifest

      $manifestDirectory = Split-Path -Parent $script:manifestPath
      $tempManifestPath = Join-Path $manifestDirectory ("pester-msi-" + [guid]::NewGuid().ToString("N") + ".json")
      $manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $tempManifestPath -Encoding utf8
      return $tempManifestPath
    }

    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    $script:manifestPath = Join-Path $script:repoRoot "examples\\sample-gui\\package.manifest.json"
    $script:toolScript = Join-Path $script:repoRoot "scripts\\gnustep-packager.ps1"

    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
    . (Join-Path $script:repoRoot "backends\\msi\\lib\\msi.ps1")

    & $script:toolScript -Command build -Manifest $script:manifestPath
    & $script:toolScript -Command stage -Manifest $script:manifestPath

    $script:transformContext = Get-GpManifestContext -Path $script:manifestPath
    $script:transformConfig = Get-GpMsiConfig -Context $script:transformContext
    $script:transformWorkPaths = Get-GpMsiWorkPaths -Context $script:transformContext
    $script:transformLogPath = Join-Path $script:transformConfig.OutputPaths.LogRoot "pester-msi-transform.log"
    $script:transform = Prepare-GpMsiInstallTree -Context $script:transformContext -Config $script:transformConfig -WorkPaths $script:transformWorkPaths -LogPath $script:transformLogPath
  }

  Context "Manifest resolution" {
    It "applies defaults and honors package version override" {
      $context = Get-GpManifestContext -Path $script:manifestPath -PackageVersion "2.5.7-rc1"

      Assert-GpEqual -Actual $context.PackageVersionOverride -Expected "2.5.7-rc1" -Message "Version override should be preserved."
      Assert-GpEqual -Actual $context.Manifest["package"]["version"] -Expected "2.5.7-rc1" -Message "Resolved manifest should use the overridden version."
      Assert-GpEqual -Actual $context.Manifest["backends"]["msi"]["portableArtifactNamePattern"] -Expected "{name}-{version}-win64-portable.zip" -Message "MSI portable artifact default should be present."
      Assert-GpEqual -Actual @($context.Manifest["profiles"]) -Expected @("gnustep-gui") -Message "Resolved manifest should preserve requested built-in profiles."
      Assert-GpEqual -Actual @(Get-GpComplianceEntries -Manifest $context.Manifest).Count -Expected 2 -Message "Resolved manifest should surface compliance notice entries."
    }

    It "resolves enabled backends from the manifest" {
      $context = Get-GpManifestContext -Path $script:manifestPath

      Assert-GpEqual -Actual @(Get-GpEnabledBackends -Manifest $context.Manifest) -Expected @("msi") -Message "Enabled backends should match the sample manifest."
    }

    It "applies built-in profile defaults before manifest overrides" {
      $context = Get-GpManifestContext -Path $script:manifestPath

      Assert-GpEqual -Actual @($context.Manifest["launch"]["pathPrepend"]) -Expected @("runtime/bin") -Message "GUI profile should provide common runtime PATH defaults."
      Assert-GpEqual -Actual $context.Manifest["launch"]["env"]["GNUSTEP_PATHPREFIX_LIST"] -Expected "{@runtimeRoot}" -Message "GUI profile should provide the common GNUstep runtime root token."
      Assert-GpEqual -Actual @($context.Manifest["payload"]["runtimeSeedPaths"]) -Expected @("runtime/bin/defaults.exe") -Message "The Windows fixture manifest should declare its runtime seed paths."
    }

    It "normalizes launch environment policies for backend rendering" {
      $launch = Get-GpLaunchContract -Context $script:transformContext

      Assert-GpEqual -Actual $launch.Environment["GSTheme"]["value"] -Expected "WinUXTheme" -Message "Launch contract should preserve environment values."
      Assert-GpEqual -Actual $launch.Environment["GSTheme"]["policy"] -Expected "ifUnset" -Message "Launch contract should preserve conditional environment policies."
      Assert-GpEqual -Actual $launch.Environment["GNUSTEP_PATHPREFIX_LIST"]["policy"] -Expected "override" -Message "Plain string launch environment entries should normalize to override."
    }
  }

  Context "Versioning and transform" {
    It "normalizes semantic versions for MSI upgrade semantics" {
      Assert-GpEqual -Actual (Normalize-GpMsiVersion -Version "1.2.3-rc1+7") -Expected "1.2.3.1" -Message "MSI version normalization should keep the first four numeric groups."
    }

    It "builds artifact names from the overridden package version" {
      $context = Get-GpManifestContext -Path $script:manifestPath -PackageVersion "3.4.5"
      $config = Get-GpMsiConfig -Context $context

      Assert-GpEqual -Actual $config.ArtifactPlan.ArtifactName -Expected "SampleGNUstepApp-3.4.5-win64.msi" -Message "MSI artifact name should track the overridden version."
      Assert-GpEqual -Actual $config.PortablePlan.ArtifactName -Expected "SampleGNUstepApp-3.4.5-win64-portable.zip" -Message "Portable artifact name should track the overridden version."
      Assert-GpEqual -Actual $config.MsiVersion -Expected "3.4.5.0" -Message "MSI numeric version should be normalized from the overridden version."
    }

    It "computes the per-user install root used by validation" {
      $context = Get-GpManifestContext -Path $script:manifestPath
      $config = Get-GpMsiConfig -Context $context

      Assert-GpMatch -Actual (Get-GpMsiInstallPathGuess -Config $config) -Pattern ([regex]::Escape((Join-Path $env:LOCALAPPDATA "SampleGNUstepApp"))) -Message "Validation install path should point to LocalAppData for per-user installs."
    }

    It "copies the staged payload into the install tree" {
      Assert-GpTrue -Condition (Test-Path (Join-Path $script:transform.InstallRoot "app\\SampleGNUstepApp.app\\SampleGNUstepApp.exe")) -Message "Transformed install tree should contain the app executable."
      Assert-GpTrue -Condition (Test-Path (Join-Path $script:transform.InstallRoot "runtime\\bin\\defaults.exe")) -Message "Transformed install tree should contain the staged runtime seed."
      Assert-GpTrue -Condition (Test-Path (Join-Path $script:transform.InstallRoot "metadata\\icons\\sample-icon.txt")) -Message "Transformed install tree should contain staged metadata."
      Assert-GpTrue -Condition (Test-Path (Join-Path $script:transform.InstallRoot "metadata\\licenses\\GNUstep-runtime.txt")) -Message "Transformed install tree should contain staged license metadata."
    }

    It "generates launcher output and config" {
      Assert-GpTrue -Condition (Test-Path $script:transform.LauncherPath) -Message "Launcher executable should be generated."
      Assert-GpTrue -Condition (Test-Path $script:transform.LauncherConfigPath) -Message "Launcher config should be generated."
    }

    It "writes the launch contract into the generated launcher config" {
      $configText = Get-Content -Raw -Path $script:transform.LauncherConfigPath

      Assert-GpMatch -Actual $configText -Pattern "entryRelativePath=app/SampleGNUstepApp.app/SampleGNUstepApp.exe" -Message "Launcher config should contain the entry path."
      Assert-GpMatch -Actual $configText -Pattern "pathPrepend=runtime/bin" -Message "Launcher config should contain runtime PATH additions."
      Assert-GpMatch -Actual $configText -Pattern "env=GNUSTEP_PATHPREFIX_LIST=\{@runtimeRoot\}" -Message "Launcher config should preserve runtime token expansion."
      Assert-GpMatch -Actual $configText -Pattern "env=ifUnset\|GSTheme=WinUXTheme" -Message "Launcher config should preserve conditional environment defaults."
    }

    It "writes a bundled notice report from compliance entries" {
      $noticeText = Get-Content -Raw -Path $script:transform.NoticeReportPath

      Assert-GpTrue -Condition (Test-Path $script:transform.NoticeReportPath) -Message "Transform should emit a third-party notice report."
      Assert-GpMatch -Actual $noticeText -Pattern "Runtime notice entries: 2" -Message "Notice report should summarize compliance entries."
      Assert-GpMatch -Actual $noticeText -Pattern "GNUstep Runtime Seed" -Message "Notice report should list configured runtime notices."
      Assert-GpMatch -Actual $noticeText -Pattern "metadata/licenses/GNUstep-runtime.txt" -Message "Notice report should preserve staged notice paths."
    }

    It "places the shortcut at the Start Menu root" {
      $templateText = Get-Content -Raw -Path $script:transformConfig.ProductTemplatePath

      Assert-GpMatch -Actual $templateText -Pattern '<DirectoryRef Id="ProgramMenuFolder">' -Message "Shortcut template should write directly to the Start Menu root."
      Assert-GpFalse -Condition ($templateText -match 'ApplicationProgramsFolder') -Message "Shortcut template should not create an extra Start Menu folder."
    }

    It "writes bundled updater metadata into the MSI install tree when enabled" {
      $manifestPath = New-GpSiblingManifest {
        param($manifest)
        $manifest["updates"] = @{
          enabled = $true
          provider = "github-release-feed"
          channel = "stable"
          github = @{
            owner = "example-org"
            repo = "sample-gnustep-app"
            tagPattern = "v{version}"
          }
        }
        $manifest["backends"]["msi"]["updates"] = @{
          feedUrl = "https://example.invalid/updates/windows/stable.json"
        }
      }
      $workPaths = $null

      try {
        $context = Get-GpManifestContext -Path $manifestPath
        $config = Get-GpMsiConfig -Context $context
        $workPaths = Get-GpMsiWorkPaths -Context $context
        $logPath = Join-Path $config.OutputPaths.LogRoot "pester-msi-transform-updates.log"
        $result = Prepare-GpMsiInstallTree -Context $context -Config $config -WorkPaths $workPaths -LogPath $logPath
        $updaterConfig = Get-GpJsonFile -Path $result.UpdateRuntimeConfigPath

        Assert-GpTrue -Condition (Test-Path $result.UpdateRuntimeConfigPath) -Message "Update-enabled MSI transforms should bundle a runtime updater config."
        Assert-GpEqual -Actual $updaterConfig["package"]["backend"] -Expected "msi" -Message "The bundled updater config should record the MSI backend."
        Assert-GpEqual -Actual $updaterConfig["updates"]["feedUrl"] -Expected "https://example.invalid/updates/windows/stable.json" -Message "The bundled updater config should preserve the resolved MSI feed URL."
      } finally {
        if (Test-Path $manifestPath) {
          Remove-Item -Force $manifestPath
        }
        if ($null -ne $workPaths -and (Test-Path $workPaths.Root)) {
          Remove-Item -Recurse -Force $workPaths.Root
        }
      }
    }
  }

  Context "Icon configuration and wrapper" {
    It "resolves a staged .ico path when configured" {
      $stageRoot = Join-Path $env:TEMP ("gp-icon-test-" + [guid]::NewGuid().ToString("N"))
      $iconPath = Join-Path $stageRoot "metadata\\icons\\sample.ico"
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $iconPath) | Out-Null
      Set-Content -Path $iconPath -Value "placeholder"

      try {
        $config = [pscustomobject]@{
          StageRoot = $stageRoot
          IconRelativePath = "metadata/icons/sample.ico"
        }

        $resolvedIconPath = [System.IO.Path]::GetFullPath((Resolve-GpMsiIconSourcePath -Config $config))
        $expectedIconPath = [System.IO.Path]::GetFullPath($iconPath)
        Assert-GpEqual -Actual $resolvedIconPath -Expected $expectedIconPath -Message "Configured MSI icon path should resolve inside the staged payload."
      } finally {
        if (Test-Path $stageRoot) {
          Remove-Item -Recurse -Force $stageRoot
        }
      }
    }

    It "supports dry-run packaging with a version override" {
      try {
        & (Join-Path $script:repoRoot "scripts\\run-packaging-pipeline.ps1") `
          -Manifest $script:manifestPath `
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

  Context "Runtime closure policy" {
    It "fails by default on unresolved non-system dependencies after ignore filtering" {
      $config = [pscustomobject]@{
        UnresolvedDependencyPolicy = "fail"
      }
      $runtimeClosure = Resolve-GpMsiRuntimeClosureResult `
        -UnresolvedDependencies @("Missing.dll", "Optional.dll") `
        -IgnoredDependencies @("Optional.dll")
      $logPath = Join-Path $env:TEMP ("gp-msi-runtime-closure-" + [guid]::NewGuid().ToString("N") + ".log")
      $threw = $false

      try {
        Assert-GpEqual -Actual @($runtimeClosure.UnresolvedDependencies) -Expected @("Missing.dll") -Message "Ignored runtime dependencies should be filtered from the effective unresolved set."
        Assert-GpEqual -Actual @($runtimeClosure.IgnoredDependencies) -Expected @("Optional.dll") -Message "Ignored runtime dependencies should still be reported separately."
        try {
          Assert-GpMsiRuntimeClosurePolicy -Config $config -RuntimeClosure $runtimeClosure -LogPath $logPath
        } catch {
          $threw = $true
          Assert-GpMatch -Actual $_.Exception.Message -Pattern "Unresolved non-system runtime dependencies" -Message "The default MSI runtime policy should fail when unresolved DLLs remain."
        }
        Assert-GpTrue -Condition $threw -Message "The default MSI runtime policy should stop packaging when unresolved DLLs remain."
      } finally {
        if (Test-Path $logPath) {
          Remove-Item -Force $logPath
        }
      }
    }

    It "reports missing dependencies for runtime-extension DLLs with target provenance" {
      $tempRoot = Join-Path $env:TEMP ("gp-msi-runtime-audit-" + [guid]::NewGuid().ToString("N"))
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
}
