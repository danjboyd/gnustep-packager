Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Describe "DMG backend" {
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

    function New-GpSiblingManifest {
      param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Customize
      )

      $manifest = Get-GpJsonFile -Path $script:manifestPath
      & $Customize $manifest

      $manifestDirectory = Split-Path -Parent $script:manifestPath
      $tempManifestPath = Join-Path $manifestDirectory ("pester-dmg-" + [guid]::NewGuid().ToString("N") + ".json")
      $manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $tempManifestPath -Encoding utf8
      $script:tempManifests += @($tempManifestPath)
      return $tempManifestPath
    }

    function Get-GpAttachedImageText {
      return [string]::Join("`n", @(& hdiutil info 2>&1 | ForEach-Object { [string]$_ }))
    }

    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    $script:manifestPath = Join-Path $script:repoRoot "examples/sample-macos/package.manifest.json"
    $script:toolScript = Join-Path $script:repoRoot "scripts\\gnustep-packager.ps1"
    $script:tempManifests = @()

    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
    . (Join-Path $script:repoRoot "backends\\dmg\\lib\\dmg.ps1")

    # The fixture keeps finderLayout off; make sure a developer override does
    # not drive Finder during the test run.
    $script:previousFinderLayout = $env:GP_DMG_FINDER_LAYOUT
    $env:GP_DMG_FINDER_LAYOUT = "off"
    $script:previousNotaryProfile = $env:GP_SAMPLE_NOTARY_PROFILE
    Remove-Item Env:GP_SAMPLE_NOTARY_PROFILE -ErrorAction SilentlyContinue

    & $script:toolScript -Command build -Manifest $script:manifestPath
    & $script:toolScript -Command stage -Manifest $script:manifestPath

    $script:context = Get-GpManifestContext -Path $script:manifestPath -Backend dmg
    $script:config = Get-GpDmgConfig -Context $script:context
    $script:stagedSignatureBefore = (Get-GpDmgSignatureInfo -Path $script:config.StagedAppPath).Raw
    $script:packageLogPath = Join-Path $script:config.OutputPaths.LogRoot "pester-dmg-package.log"
    $script:packageResult = Invoke-GpDmgPackage -Context $script:context -LogPath $script:packageLogPath
    $script:metadata = Get-Content -Raw -Path $script:packageResult.MetadataPath | ConvertFrom-Json
    $script:validationLogPath = Join-Path (Join-Path $script:config.OutputPaths.ValidationRoot "pester-dmg") "validate.log"
    $script:validationResult = Invoke-GpDmgValidation -Context $script:context -RunSmoke -LogPath $script:validationLogPath
  }

  AfterAll {
    foreach ($path in @($script:tempManifests)) {
      if (Test-Path $path) {
        Remove-Item -Force $path
      }
    }
    $env:GP_DMG_FINDER_LAYOUT = $script:previousFinderLayout
    if ($null -ne $script:previousNotaryProfile) {
      $env:GP_SAMPLE_NOTARY_PROFILE = $script:previousNotaryProfile
    }
  }

  Context "Manifest resolution" {
    It "resolves the staged bundle, architecture and artifact name" {
      Assert-GpEqual -Actual @(Get-GpEnabledBackends -Manifest $script:context.Manifest) -Expected @("dmg") -Message "The macOS fixture enables only the DMG backend."
      Assert-GpEqual -Actual $script:config.AppBundleName -Expected "SampleMacApp.app" -Message "appBundleName defaults to {name}.app."
      Assert-GpEqual -Actual $script:config.AppInfo.ArchToken -Expected "universal" -Message "The fixture is built for arm64 and x86_64."
      Assert-GpEqual -Actual $script:config.ArtifactName -Expected "SampleMacApp-0.1.0-macos-universal.dmg" -Message "The artifact name should follow {name}-{version}-macos-{arch}.dmg."
      Assert-GpEqual -Actual $script:config.VolumeName -Expected "Sample Mac App" -Message "The volume name defaults to the display name."
      Assert-GpEqual -Actual $script:config.Signing.Identity -Expected "-" -Message "The default identity is ad-hoc."
    }

    It "reports a dry run without touching the host" {
      $dryRun = Invoke-GpDmgPackage -Context $script:context -DryRun
      Assert-GpEqual -Actual $dryRun.ArtifactPath -Expected $script:config.ArtifactPath -Message "Dry run should report the artifact path."
      Assert-GpEqual -Actual $dryRun.RequiredPlatform -Expected "macos" -Message "The DMG backend requires macOS."
    }
  }

  Context "Packaging" {
    It "emits the DMG and its sidecars" {
      Assert-GpTrue -Condition (Test-Path $script:packageResult.ArtifactPath) -Message "The DMG should exist."
      Assert-GpTrue -Condition (Test-Path $script:packageResult.MetadataPath) -Message "The metadata sidecar should exist."
      Assert-GpTrue -Condition (Test-Path $script:packageResult.DiagnosticsPath) -Message "The diagnostics sidecar should exist."
      Assert-GpEqual -Actual (Split-Path -Leaf $script:packageResult.MetadataPath) -Expected "SampleMacApp-0.1.0-macos-universal.metadata.json" -Message "Sidecars share the artifact base name."
    }

    It "records provenance, signing and notarization state in the metadata" {
      Assert-GpEqual -Actual $script:metadata.backend -Expected "dmg" -Message "Metadata should name the backend."
      Assert-GpEqual -Actual $script:metadata.app.arch -Expected "universal" -Message "Metadata should record the architecture."
      Assert-GpEqual -Actual $script:metadata.artifacts.dmg.format -Expected "UDZO" -Message "Metadata should record the image format."
      Assert-GpEqual -Actual $script:metadata.artifacts.dmg.sha256 -Expected (Get-GpFileSha256 -Path $script:packageResult.ArtifactPath) -Message "Metadata should record the artifact hash."
      Assert-GpEqual -Actual $script:metadata.signing.adHoc -Expected $true -Message "The fixture is ad-hoc signed."
      Assert-GpEqual -Actual $script:metadata.signing.resigned -Expected $false -Message "The existing signature is kept by default."
      Assert-GpEqual -Actual $script:metadata.signing.appSignature.verified -Expected $true -Message "The kept signature should verify."
      Assert-GpEqual -Actual $script:metadata.notarization.status -Expected "skipped-no-credentials" -Message "Notarization without credentials is skipped, not failed."
      Assert-GpEqual -Actual $script:metadata.layout.finderLayoutApplied -Expected $false -Message "Finder layout is off for the fixture."
    }

    It "never mutates the staged payload" {
      $after = (Get-GpDmgSignatureInfo -Path $script:config.StagedAppPath).Raw
      Assert-GpEqual -Actual $after -Expected $script:stagedSignatureBefore -Message "The staged app's signature should be unchanged."
      Assert-GpTrue -Condition (-not (Test-Path (Join-Path $script:config.StageRoot "app/Applications"))) -Message "Volume items belong in the work tree, not the stage."
    }

    It "logs the skipped notarization with the environment variable name" {
      $logText = Get-Content -Raw -Path $script:packageLogPath
      Assert-GpMatch -Actual $logText -Pattern "Notarization skipped: environment variable GP_SAMPLE_NOTARY_PROFILE is not set" -Message "The package log should explain why notarization was skipped."
      Assert-GpMatch -Actual $logText -Pattern "Finder layout skipped: finderLayout is off" -Message "The package log should explain the skipped layout."
    }

    It "leaves no disk image attached" {
      $attached = Get-GpAttachedImageText
      Assert-GpTrue -Condition (-not $attached.Contains($script:packageResult.WorkRoot)) -Message "The read-write image should be detached."
      Assert-GpTrue -Condition (-not (Test-Path (Join-Path $script:packageResult.WorkRoot "readwrite.dmg"))) -Message "The read-write image should be deleted."
    }
  }

  Context "Validation" {
    It "verifies, mounts and smoke-launches the image" {
      $checks = @{}
      foreach ($check in @($script:validationResult.Checks)) {
        $checks[$check.name] = $check.status
      }
      foreach ($name in @("hdiutil-verify", "image-format", "attach", "app-bundle", "applications-link", "background", "codesign-verify", "installed-contract", "launch-smoke")) {
        Assert-GpEqual -Actual $checks[$name] -Expected "pass" -Message "Check '$name' should pass."
      }
      Assert-GpEqual -Actual $checks["gatekeeper"] -Expected "info" -Message "An ad-hoc app is rejected by Gatekeeper; that is recorded, not failed."
      Assert-GpEqual -Actual $script:validationResult.GatekeeperAccepted -Expected $false -Message "Gatekeeper should reject an ad-hoc signature."
      Assert-GpEqual -Actual $script:validationResult.SmokeOutcome -Expected "process-remained-running-through-startup-window" -Message "The faceless fixture keeps running until killed."
    }

    It "writes a validation summary and detaches the image" {
      $summary = Get-Content -Raw -Path $script:validationResult.SummaryPath | ConvertFrom-Json
      Assert-GpEqual -Actual $summary.passed -Expected $true -Message "The summary should record success."
      Assert-GpEqual -Actual $summary.appSignature.adHoc -Expected $true -Message "The summary should record the ad-hoc signature."
      Assert-GpTrue -Condition (-not (Get-GpAttachedImageText).Contains($script:packageResult.ArtifactPath)) -Message "Validation should detach the image."
      Assert-GpEqual -Actual @(Get-ChildItem -Path (Split-Path -Parent $script:validationLogPath) -Directory -Filter "mount-*").Count -Expected 0 -Message "The temporary mount point should be removed."
    }

    It "fails when Gatekeeper acceptance is required, and still detaches" {
      $strictManifest = New-GpSiblingManifest -Customize {
        param($manifest)
        $manifest["backends"]["dmg"]["validation"] = @{ requireGatekeeperAcceptance = $true }
      }
      $strictContext = Get-GpManifestContext -Path $strictManifest -Backend dmg
      $logPath = Join-Path (Join-Path $script:config.OutputPaths.ValidationRoot "pester-dmg-strict") "validate.log"
      $message = $null
      try {
        Invoke-GpDmgValidation -Context $strictContext -LogPath $logPath | Out-Null
      } catch {
        $message = $_.Exception.Message
      }
      Assert-GpTrue -Condition ($null -ne $message) -Message "Validation should fail when Gatekeeper rejects the app."
      Assert-GpMatch -Actual $message -Pattern "gatekeeper" -Message "The failure should name the Gatekeeper check."
      Assert-GpTrue -Condition (-not (Get-GpAttachedImageText).Contains($script:packageResult.ArtifactPath)) -Message "A failed validation should still detach the image."
    }
  }

  Context "Signing and notarization" {
    It "re-signs the app copy with entitlements when resign is true" {
      $entitlementsPath = Join-Path (Split-Path -Parent $script:manifestPath) "dist/tmp/pester-entitlements.plist"
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $entitlementsPath) | Out-Null
      Set-Content -Path $entitlementsPath -Encoding utf8 -Value @'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.cs.disable-library-validation</key><true/></dict></plist>
'@
      $resignManifest = New-GpSiblingManifest -Customize {
        param($manifest)
        $manifest["backends"]["dmg"]["artifactNamePattern"] = "{name}-{version}-macos-{arch}-resigned.dmg"
        $manifest["backends"]["dmg"]["format"] = "ULFO"
        $manifest["backends"]["dmg"]["filesystem"] = "HFS+"
        $manifest["backends"]["dmg"]["signing"] = @{ identity = "-"; resign = $true; entitlementsPath = "dist/tmp/pester-entitlements.plist" }
      }
      $resignContext = Get-GpManifestContext -Path $resignManifest -Backend dmg
      $result = Invoke-GpDmgPackage -Context $resignContext -LogPath (Join-Path $script:config.OutputPaths.LogRoot "pester-dmg-resign.log")
      Assert-GpEqual -Actual (Split-Path -Leaf $result.ArtifactPath) -Expected "SampleMacApp-0.1.0-macos-universal-resigned.dmg" -Message "The custom pattern should be honored."
      $metadata = Get-Content -Raw -Path $result.MetadataPath | ConvertFrom-Json
      Assert-GpEqual -Actual $metadata.signing.resigned -Expected $true -Message "Metadata should record the re-sign."
      Assert-GpEqual -Actual $metadata.artifacts.dmg.format -Expected "ULFO" -Message "The ULFO format should be honored."

      $mount = Mount-GpDmgImage -ImagePath $result.ArtifactPath -MountPoint (Join-Path $result.WorkRoot "inspect")
      try {
        $entitlements = [string]::Join("`n", @(& codesign -d --entitlements - (Join-Path $mount.MountPoint "SampleMacApp.app") 2>&1 | ForEach-Object { [string]$_ }))
        Assert-GpMatch -Actual $entitlements -Pattern "disable-library-validation" -Message "The re-signed app should carry the configured entitlements."
        $hfs = [string]::Join("`n", @(& diskutil info $mount.MountPoint 2>&1 | ForEach-Object { [string]$_ }))
        Assert-GpMatch -Actual $hfs -Pattern "HFS\+" -Message "The HFS+ filesystem option should be honored."
      } finally {
        Dismount-GpDmgImage -Mount $mount | Out-Null
      }

      $validation = Invoke-GpDmgValidation -Context $resignContext -LogPath (Join-Path (Join-Path $script:config.OutputPaths.ValidationRoot "pester-dmg-resign") "validate.log")
      Assert-GpEqual -Actual (@($validation.Checks | Where-Object { $_.name -eq "codesign-verify" })[0].status) -Expected "pass" -Message "The re-signed app should verify."
    }

    It "skips notarization for an ad-hoc identity even when credentials are set" {
      $config = [pscustomobject]@{
        Signing = [pscustomobject]@{ IsAdHoc = $true }
        Notarization = [pscustomobject]@{ Enabled = $true; KeychainProfileEnvVar = "GP_PESTER_NOTARY_PROFILE"; Staple = $true; Required = $false }
      }
      $env:GP_PESTER_NOTARY_PROFILE = "pester-profile"
      try {
        $result = Invoke-GpDmgNotarization -Config $config -ArtifactPath "/nonexistent.dmg"
      } finally {
        Remove-Item Env:GP_PESTER_NOTARY_PROFILE -ErrorAction SilentlyContinue
      }
      Assert-GpEqual -Actual $result.status -Expected "skipped-ad-hoc" -Message "Apple does not notarize ad-hoc code."
    }

    It "fails closed when notarization is required but cannot run" {
      $config = [pscustomobject]@{
        Signing = [pscustomobject]@{ IsAdHoc = $false }
        Notarization = [pscustomobject]@{ Enabled = $true; KeychainProfileEnvVar = "GP_PESTER_UNSET_PROFILE"; Staple = $true; Required = $true }
      }
      $message = $null
      try {
        Invoke-GpDmgNotarization -Config $config -ArtifactPath "/nonexistent.dmg" | Out-Null
      } catch {
        $message = $_.Exception.Message
      }
      Assert-GpMatch -Actual $message -Pattern "GP_PESTER_UNSET_PROFILE is not set.*required is true" -Message "A required notarization without credentials should fail with the env var name."
    }

    It "reports a missing staged bundle clearly" {
      $missingManifest = New-GpSiblingManifest -Customize {
        param($manifest)
        $manifest["backends"]["dmg"]["appBundleName"] = "Missing.app"
      }
      $message = $null
      try {
        Invoke-GpDmgPackage -Context (Get-GpManifestContext -Path $missingManifest -Backend dmg) | Out-Null
      } catch {
        $message = $_.Exception.Message
      }
      Assert-GpMatch -Actual $message -Pattern "Staged app bundle not found: .*Missing\.app" -Message "Packaging should name the missing bundle."
    }
  }
}
