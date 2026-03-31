Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Describe "AppImage backend" {
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

    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    $script:manifestPath = Join-Path $script:repoRoot "examples/sample-linux/package.manifest.json"
    $script:toolScript = Join-Path $script:repoRoot "scripts\\gnustep-packager.ps1"

    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
    . (Join-Path $script:repoRoot "backends\\appimage\\lib\\appimage.ps1")

    & $script:toolScript -Command build -Manifest $script:manifestPath
    & $script:toolScript -Command stage -Manifest $script:manifestPath

    $script:packageContext = Get-GpManifestContext -Path $script:manifestPath
    $script:packageConfig = Get-GpAppImageConfig -Context $script:packageContext
    $script:packageLogPath = Join-Path $script:packageConfig.OutputPaths.LogRoot "pester-appimage-package.log"
    $script:packageResult = Invoke-GpAppImagePackage -Context $script:packageContext -LogPath $script:packageLogPath
    $script:validationLogPath = Join-Path $script:packageConfig.OutputPaths.ValidationRoot "pester-appimage-validate.log"
    $script:validationResult = Invoke-GpAppImageValidation -Context $script:packageContext -RunSmoke -LogPath $script:validationLogPath
  }

  Context "Manifest resolution" {
    It "resolves enabled backend and artifact naming defaults" {
      $context = Get-GpManifestContext -Path $script:manifestPath
      $config = Get-GpAppImageConfig -Context $context

      Assert-GpEqual -Actual @(Get-GpEnabledBackends -Manifest $context.Manifest) -Expected @("appimage") -Message "Linux fixture should only enable the AppImage backend."
      Assert-GpEqual -Actual $config.ArtifactPlan.ArtifactName -Expected "SampleGNUstepLinuxApp-0.1.0-x86_64.AppImage" -Message "AppImage artifact name should use the default naming pattern."
      Assert-GpEqual -Actual $config.DesktopEntryName -Expected "sample-gnustep-linux.desktop" -Message "AppImage desktop entry name should come from the manifest."
    }

    It "keeps the shared launch contract backend-neutral" {
      $launch = Get-GpLaunchContract -Context $script:packageContext

      Assert-GpEqual -Actual $launch.EntryRelativePath -Expected "app/SampleGNUstepLinuxApp.app/SampleGNUstepLinuxApp" -Message "Launch contract should describe the staged entry path."
      Assert-GpEqual -Actual @($launch.PathPrepend) -Expected @("runtime/bin") -Message "GUI profile should still feed the shared PATH contract on Linux."
    }
  }

  Context "Packaging" {
    It "emits the AppImage artifact and sidecars" {
      Assert-GpTrue -Condition (Test-Path $script:packageResult.ArtifactPath) -Message "AppImage artifact should be created."
      Assert-GpTrue -Condition (Test-Path $script:packageResult.MetadataPath) -Message "AppImage metadata sidecar should be written."
      Assert-GpTrue -Condition (Test-Path $script:packageResult.DiagnosticsPath) -Message "AppImage diagnostics sidecar should be written."
    }

    It "builds an AppDir with launcher, desktop file, icon, and MIME metadata" {
      Assert-GpTrue -Condition (Test-Path $script:packageResult.AppRunPath) -Message "AppRun should be generated."
      Assert-GpTrue -Condition (Test-Path $script:packageResult.DesktopEntryPath) -Message "Desktop entry should be generated."
      Assert-GpTrue -Condition (Test-Path $script:packageResult.IconPath) -Message "AppImage icon should be copied into the AppDir."
      Assert-GpTrue -Condition (Test-Path $script:packageResult.DirIconPath) -Message ".DirIcon should be present at the AppDir root."
      Assert-GpTrue -Condition (Test-Path $script:packageResult.MimePackagePath) -Message "Generated MIME metadata should exist for extension associations."
      Assert-GpTrue -Condition (Test-Path $script:packageResult.NoticeReportPath) -Message "Notice report should be generated inside the AppDir."
    }

    It "renders desktop metadata and generated MIME types" {
      $desktopText = Get-Content -Raw -Path $script:packageResult.DesktopEntryPath
      $mimeText = Get-Content -Raw -Path $script:packageResult.MimePackagePath

      Assert-GpMatch -Actual $desktopText -Pattern "Name=Sample GNUstep Linux App" -Message "Desktop entry should use the package display name."
      Assert-GpMatch -Actual $desktopText -Pattern "Exec=AppRun %F" -Message "Desktop entry should route launches through AppRun."
      Assert-GpMatch -Actual $desktopText -Pattern "MimeType=application/x-samplegnusteplinuxapp-samplelinux;" -Message "Desktop entry should include the generated MIME type."
      Assert-GpMatch -Actual $mimeText -Pattern "glob pattern='\*\.samplelinux'" -Message "Generated MIME package should describe the staged extension association."
    }
  }

  Context "Validation" {
    It "extracts the AppImage and validates the mounted structure" {
      Assert-GpTrue -Condition (Test-Path $script:validationResult.ExpandedRoot) -Message "Validation should extract the AppImage contents."
      Assert-GpTrue -Condition (Test-Path (Join-Path $script:validationResult.ExpandedRoot "AppRun")) -Message "Extracted AppImage should contain AppRun."
      Assert-GpTrue -Condition (Test-Path (Join-Path $script:validationResult.ExpandedRoot "sample-gnustep-linux.desktop")) -Message "Extracted AppImage should contain the desktop entry."
    }

    It "runs the smoke path through the packaged AppImage" {
      $smokeMarkerPath = Join-Path (Split-Path -Parent $script:validationLogPath) "smoke-marker.txt"
      $smokeMarkerText = Get-Content -Raw -Path $smokeMarkerPath

      Assert-GpTrue -Condition (Test-Path $smokeMarkerPath) -Message "Smoke validation should create the marker file."
      Assert-GpMatch -Actual $smokeMarkerText -Pattern "fixture=sample-linux" -Message "The packaged fixture should write its smoke marker."
      Assert-GpMatch -Actual $smokeMarkerText -Pattern "gnustep=" -Message "The packaged fixture should capture GNUstep-related environment output."
    }
  }
}
