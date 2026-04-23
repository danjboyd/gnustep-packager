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

    function New-GpSiblingManifest {
      param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Customize
      )

      $manifest = Get-GpJsonFile -Path $script:manifestPath
      & $Customize $manifest

      $manifestDirectory = Split-Path -Parent $script:manifestPath
      $tempManifestPath = Join-Path $manifestDirectory ("pester-appimage-" + [guid]::NewGuid().ToString("N") + ".json")
      $manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $tempManifestPath -Encoding utf8
      return $tempManifestPath
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
    $script:launchOnlySmokeLogText = Get-Content -Raw -Path $script:validationResult.SmokeLog
  }

  Context "Manifest resolution" {
    It "resolves enabled backend and artifact naming defaults" {
      $context = Get-GpManifestContext -Path $script:manifestPath
      $config = Get-GpAppImageConfig -Context $context

      Assert-GpEqual -Actual @(Get-GpEnabledBackends -Manifest $context.Manifest) -Expected @("appimage") -Message "Linux fixture should only enable the AppImage backend."
      Assert-GpEqual -Actual $config.ArtifactPlan.ArtifactName -Expected "SampleGNUstepLinuxApp-0.1.0-x86_64.AppImage" -Message "AppImage artifact name should use the default naming pattern."
      Assert-GpEqual -Actual $config.DesktopEntryName -Expected "sample-gnustep-linux.desktop" -Message "AppImage desktop entry name should come from the manifest."
      Assert-GpEqual -Actual $config.Smoke.Mode -Expected "launch-only" -Message "Linux fixture should default to launch-only AppImage smoke validation."
    }

    It "keeps the shared launch contract backend-neutral" {
      $launch = Get-GpLaunchContract -Context $script:packageContext

      Assert-GpEqual -Actual $launch.EntryRelativePath -Expected "app/SampleGNUstepLinuxApp.app/SampleGNUstepLinuxApp" -Message "Launch contract should describe the staged entry path."
      Assert-GpEqual -Actual @($launch.PathPrepend) -Expected @("runtime/bin") -Message "GUI profile should still feed the shared PATH contract on Linux."
      Assert-GpEqual -Actual $launch.Environment["GSTheme"]["policy"] -Expected "ifUnset" -Message "Launch contract should preserve conditional environment defaults on Linux too."
    }

    It "normalizes packaged app-domain defaults for AppImage rendering" {
      $packagedDefaults = Get-GpPackagedDefaults -Manifest $script:packageContext.Manifest

      Assert-GpEqual -Actual $packagedDefaults.AppDomain.Domain -Expected "com.example.SampleGNUstepLinuxApp" -Message "App-domain defaults should default to package.id on Linux too."
      Assert-GpEqual -Actual @($packagedDefaults.AppDomain.Entries | ForEach-Object { $_.Type }) -Expected @("bool", "integer", "string") -Message "App-domain defaults should preserve scalar types for AppImage rendering."
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

    It "renders conditional launch defaults into AppRun" {
      $appRunText = Get-Content -Raw -Path $script:packageResult.AppRunPath

      Assert-GpMatch -Actual $appRunText -Pattern 'if \[ -z "\$\{GSTheme\+x\}" \]; then' -Message "AppRun should only seed GSTheme when the user has not already set it."
      Assert-GpMatch -Actual $appRunText -Pattern 'export GSTheme="Adwaita"' -Message "AppRun should preserve the configured default theme value."
      Assert-GpMatch -Actual $appRunText -Pattern 'APP_DEFAULTS_TOOL="\$RUNTIME_ROOT/bin/defaults"' -Message "AppRun should look for a bundled defaults tool when app-domain defaults are declared."
      Assert-GpMatch -Actual $appRunText -Pattern 'read "com\.example\.SampleGNUstepLinuxApp" "GSTheme"' -Message "AppRun should seed GSTheme through GNUstep defaults as well as the env fallback."
      Assert-GpMatch -Actual $appRunText -Pattern 'write "com\.example\.SampleGNUstepLinuxApp" "GSTheme" "\\"Adwaita\\""' -Message "AppRun should serialize the packaged theme as a GNUstep defaults write."
      Assert-GpMatch -Actual $appRunText -Pattern 'read "com\.example\.SampleGNUstepLinuxApp" "SampleFirstRunComplete"' -Message "AppRun should seed the configured defaults domain."
      Assert-GpMatch -Actual $appRunText -Pattern 'write "com\.example\.SampleGNUstepLinuxApp" "SamplePreferredWidth" "800"' -Message "AppRun should serialize integer app-domain defaults."
      Assert-GpMatch -Actual $appRunText -Pattern 'write "com\.example\.SampleGNUstepLinuxApp" "SampleWelcomeText" "\\"Packaged sample\\""' -Message "AppRun should serialize string app-domain defaults as GNUstep literals."
    }

    It "satisfies the semantic AppImage package contract in the AppDir" {
      $contract = Invoke-GpPackageContractAssertions -Context $script:packageContext -Scope "package" -Backend "appimage" -RootPath $script:packageResult.AppDirRoot

      Assert-GpEqual -Actual $contract.HasIssues -Expected $false -Message "The AppDir should satisfy the declared package contract."
      Assert-GpMatch -Actual ([string]::Join("`n", @($contract.Lines))) -Pattern "defaultTheme" -Message "The AppImage package contract should include declarative packaged defaults."
      Assert-GpMatch -Actual ([string]::Join("`n", @($contract.Lines))) -Pattern "bundled-theme" -Message "The AppImage package contract should include semantic bundled theme assertions."
      Assert-GpMatch -Actual ([string]::Join("`n", @($contract.Lines))) -Pattern "Adwaita\.theme" -Message "Bundled-theme diagnostics should include the concrete theme path candidate."
    }

    It "renders desktop metadata and generated MIME types" {
      $desktopText = Get-Content -Raw -Path $script:packageResult.DesktopEntryPath
      $mimeText = Get-Content -Raw -Path $script:packageResult.MimePackagePath

      Assert-GpMatch -Actual $desktopText -Pattern "Name=Sample GNUstep Linux App" -Message "Desktop entry should use the package display name."
      Assert-GpMatch -Actual $desktopText -Pattern "Exec=AppRun %F" -Message "Desktop entry should route launches through AppRun."
      Assert-GpMatch -Actual $desktopText -Pattern "MimeType=application/x-samplegnusteplinuxapp-samplelinux;" -Message "Desktop entry should include the generated MIME type."
      Assert-GpMatch -Actual $mimeText -Pattern "glob pattern='\*\.samplelinux'" -Message "Generated MIME package should describe the staged extension association."
    }

    It "can emit updater metadata and a feed sidecar when updates are enabled" {
      $manifestPath = New-GpSiblingManifest {
        param($manifest)
        $manifest["updates"] = @{
          enabled = $true
          provider = "github-release-feed"
          channel = "stable"
          github = @{
            owner = "example-org"
            repo = "sample-gnustep-linux-app"
            tagPattern = "v{version}"
          }
        }
        $manifest["backends"]["appimage"]["updates"] = @{
          feedUrl = "https://example.invalid/updates/linux/stable.json"
          embedUpdateInformation = $true
          releaseSelector = "latest"
        }
      }

      try {
        $context = Get-GpManifestContext -Path $manifestPath
        $logPath = Join-Path $script:packageConfig.OutputPaths.LogRoot "pester-appimage-package-updates.log"
        $result = Invoke-GpAppImagePackage -Context $context -LogPath $logPath
        $metadata = Get-GpJsonFile -Path $result.MetadataPath

        Assert-GpTrue -Condition (Test-Path $result.UpdateRuntimeConfigPath) -Message "Update-enabled AppImage packaging should bundle a runtime updater config."
        Assert-GpTrue -Condition (Test-Path $result.UpdateFeedPath) -Message "Update-enabled AppImage packaging should emit an update feed sidecar."
        Assert-GpMatch -Actual $metadata["updates"]["appimage"]["updateInformation"] -Pattern "^gh-releases-zsync\|" -Message "AppImage metadata should record the embedded AppImage update information."
        Assert-GpEqual -Actual $metadata["updates"]["feedUrl"] -Expected "https://example.invalid/updates/linux/stable.json" -Message "AppImage metadata should record the resolved feed URL."
        Assert-GpEqual -Actual $metadata["updates"]["appimage"]["zsyncArtifactName"] -Expected "SampleGNUstepLinuxApp-0.1.0-x86_64.AppImage.zsync" -Message "AppImage metadata should preserve the configured zsync artifact name even when the active appimagetool build omits the sidecar."
      } finally {
        if (Test-Path $manifestPath) {
          Remove-Item -Force $manifestPath
        }
      }
    }
  }

  Context "Validation" {
    It "extracts the AppImage and validates the mounted structure" {
      Assert-GpTrue -Condition (Test-Path $script:validationResult.ExpandedRoot) -Message "Validation should extract the AppImage contents."
      Assert-GpTrue -Condition (Test-Path (Join-Path $script:validationResult.ExpandedRoot "AppRun")) -Message "Extracted AppImage should contain AppRun."
      Assert-GpTrue -Condition (Test-Path (Join-Path $script:validationResult.ExpandedRoot "sample-gnustep-linux.desktop")) -Message "Extracted AppImage should contain the desktop entry."
      Assert-GpEqual -Actual $script:validationResult.RuntimeClosureMode -Expected "strict" -Message "AppImage validation should enable strict runtime-closure checks by default."
      Assert-GpTrue -Condition (Test-Path $script:validationResult.RuntimeClosureLog) -Message "AppImage validation should emit a runtime-closure log."
    }

    It "satisfies the installed-result contract against the extracted AppImage" {
      $contract = Invoke-GpPackageContractAssertions -Context $script:packageContext -Scope "installed" -Backend "appimage" -RootPath $script:validationResult.ExpandedRoot

      Assert-GpEqual -Actual $contract.HasIssues -Expected $false -Message "Extracted AppImage contents should satisfy the declared installed-result contract."
      Assert-GpMatch -Actual ([string]::Join("`n", @($contract.Lines))) -Pattern "bundled-theme" -Message "Installed-result assertions should include bundled theme checks."
    }

    It "runs the launch-only smoke path through the packaged AppImage" {
      Assert-GpEqual -Actual $script:validationResult.SmokeMode -Expected "launch-only" -Message "The default Linux fixture should use launch-only smoke validation."
      Assert-GpMatch -Actual $script:validationResult.SmokeOutcome -Pattern "process-" -Message "Launch-only smoke validation should succeed through process startup behavior."
      Assert-GpMatch -Actual $script:launchOnlySmokeLogText -Pattern "Sample GNUstep Linux fixture running" -Message "Smoke validation should capture packaged app output."
      Assert-GpTrue -Condition ([string]::IsNullOrWhiteSpace([string]$script:validationResult.SmokeMarkerPath)) -Message "Launch-only smoke validation should not require a marker file."
    }

    It "seeds AppImage app-domain defaults on first launch and preserves later user overrides" {
      $tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-appimage-defaults-home-" + [guid]::NewGuid().ToString("N"))
      $defaultsRoot = Join-Path $tempHome "GNUstep/Defaults"
      $domainPath = Join-Path $defaultsRoot "com.example.SampleGNUstepLinuxApp.defaults"

      try {
        New-Item -ItemType Directory -Force -Path $defaultsRoot | Out-Null

        $firstRun = Invoke-GpAppImageCapturedTool -FilePath $script:packageResult.AppRunPath -ArgumentList @() -Environment @{
          HOME = $tempHome
        }

        Assert-GpEqual -Actual $firstRun.ExitCode -Expected 0 -Message "AppRun should succeed when seeding packaged app-domain defaults."
        Assert-GpTrue -Condition (Test-Path $domainPath) -Message "First launch should create a persistent app-domain defaults file."
        Assert-GpMatch -Actual (Get-Content -Raw -Path $domainPath) -Pattern 'GSTheme="Adwaita"' -Message "First launch should seed the packaged default theme through GNUstep defaults."
        Assert-GpMatch -Actual (Get-Content -Raw -Path $domainPath) -Pattern 'SampleFirstRunComplete=YES' -Message "First launch should seed boolean defaults."
        Assert-GpMatch -Actual (Get-Content -Raw -Path $domainPath) -Pattern 'SamplePreferredWidth=800' -Message "First launch should seed integer defaults."
        Assert-GpMatch -Actual (Get-Content -Raw -Path $domainPath) -Pattern 'SampleWelcomeText="Packaged sample"' -Message "First launch should seed string defaults."
        Assert-GpMatch -Actual $firstRun.Text -Pattern 'defaults:GSTheme="Adwaita"' -Message "Fixture output should reflect the seeded theme default."
        Assert-GpMatch -Actual $firstRun.Text -Pattern 'defaults:SampleWelcomeText="Packaged sample"' -Message "Fixture output should reflect the seeded app-domain defaults."

        Set-Content -Path $domainPath -Value @(
          'GSTheme="UserTheme"'
          'SampleFirstRunComplete=YES'
          'SamplePreferredWidth=1024'
          'SampleWelcomeText="User override"'
        )

        $secondRun = Invoke-GpAppImageCapturedTool -FilePath $script:packageResult.AppRunPath -ArgumentList @() -Environment @{
          HOME = $tempHome
        }

        Assert-GpEqual -Actual $secondRun.ExitCode -Expected 0 -Message "AppRun should still succeed after the user has already stored defaults."
        Assert-GpMatch -Actual (Get-Content -Raw -Path $domainPath) -Pattern 'GSTheme="UserTheme"' -Message "Second launch should preserve an existing user-selected theme."
        Assert-GpMatch -Actual (Get-Content -Raw -Path $domainPath) -Pattern 'SamplePreferredWidth=1024' -Message "Second launch should preserve existing user overrides."
        Assert-GpMatch -Actual (Get-Content -Raw -Path $domainPath) -Pattern 'SampleWelcomeText="User override"' -Message "Second launch should not overwrite existing string defaults."
        Assert-GpMatch -Actual $secondRun.Text -Pattern 'defaults:GSTheme="UserTheme"' -Message "Fixture output should reflect the preserved user-selected theme."
        Assert-GpMatch -Actual $secondRun.Text -Pattern 'defaults:SampleWelcomeText="User override"' -Message "Fixture output should reflect the preserved user override."
      } finally {
        if (Test-Path $tempHome) {
          Remove-Item -Recurse -Force $tempHome
        }
      }
    }
  }

  Context "Smoke modes" {
    It "builds a marker-file smoke plan with compatibility marker plumbing" {
      $manifestPath = New-GpSiblingManifest {
        param($manifest)
        $manifest["backends"]["appimage"]["smoke"] = @{
          mode = "marker-file"
        }
      }

      try {
        $context = Get-GpManifestContext -Path $manifestPath
        $config = Get-GpAppImageConfig -Context $context
        $plan = Get-GpAppImageSmokePlan -Context $context -Config $config -ValidationRoot $config.OutputPaths.ValidationRoot

        Assert-GpEqual -Actual $plan.Mode -Expected "marker-file" -Message "Marker-file smoke mode should resolve from the manifest."
        Assert-GpMatch -Actual $plan.MarkerPath -Pattern "smoke-marker\.txt$" -Message "Marker-file smoke mode should allocate a smoke marker path."
        Assert-GpEqual -Actual $plan.Environment["GP_APPIMAGE_SMOKE_MARKER_PATH"] -Expected $plan.MarkerPath -Message "Marker-file smoke mode should expose the marker path through an environment variable."
        Assert-GpEqual -Actual @($plan.Arguments) -Expected @($plan.MarkerPath) -Message "Marker-file smoke mode should preserve the compatibility positional marker argument."
      } finally {
        if (Test-Path $manifestPath) {
          Remove-Item -Force $manifestPath
        }
      }
    }

    It "supports marker-file smoke validation as an explicit opt-in mode" {
      $manifestPath = New-GpSiblingManifest {
        param($manifest)
        $manifest["backends"]["appimage"]["smoke"] = @{
          mode = "marker-file"
        }
      }

      try {
        $context = Get-GpManifestContext -Path $manifestPath
        $validationPath = Join-Path $script:packageConfig.OutputPaths.ValidationRoot "pester-appimage-validate-marker.log"
        $result = Invoke-GpAppImageValidation -Context $context -RunSmoke -LogPath $validationPath
        $markerText = Get-Content -Raw -Path $result.SmokeMarkerPath

        Assert-GpEqual -Actual $result.SmokeMode -Expected "marker-file" -Message "Marker-file smoke validation should report its configured mode."
        Assert-GpTrue -Condition (Test-Path $result.SmokeMarkerPath) -Message "Marker-file smoke validation should create the requested marker."
        Assert-GpMatch -Actual $markerText -Pattern "fixture=sample-linux" -Message "Marker-file smoke validation should preserve the fixture marker behavior."
      } finally {
        if (Test-Path $manifestPath) {
          Remove-Item -Force $manifestPath
        }
      }
    }

    It "supports open-file smoke validation with a staged document path" {
      $manifestPath = New-GpSiblingManifest {
        param($manifest)
        $manifest["backends"]["appimage"]["smoke"] = @{
          mode = "open-file"
          documentStageRelativePath = "metadata/smoke/smoke-document.md"
          environment = @{
            GP_FIXTURE_EXPECT_ARG0_BASENAME = "smoke-document.md"
          }
        }
      }

      try {
        $context = Get-GpManifestContext -Path $manifestPath
        $validationPath = Join-Path $script:packageConfig.OutputPaths.ValidationRoot "pester-appimage-validate-open-file.log"
        $result = Invoke-GpAppImageValidation -Context $context -RunSmoke -LogPath $validationPath

        Assert-GpEqual -Actual $result.SmokeMode -Expected "open-file" -Message "Open-file smoke validation should report its configured mode."
        Assert-GpMatch -Actual $result.SmokeDocumentPath -Pattern "metadata[/\\\\]smoke[/\\\\]smoke-document\.md$" -Message "Open-file smoke validation should resolve the staged document path."
      } finally {
        if (Test-Path $manifestPath) {
          Remove-Item -Force $manifestPath
        }
      }
    }

    It "supports custom-arguments smoke validation" {
      $manifestPath = New-GpSiblingManifest {
        param($manifest)
        $manifest["backends"]["appimage"]["smoke"] = @{
          mode = "custom-arguments"
          arguments = @("--smoke-arg")
          environment = @{
            GP_FIXTURE_EXPECT_ARG0 = "--smoke-arg"
          }
        }
      }

      try {
        $context = Get-GpManifestContext -Path $manifestPath
        $validationPath = Join-Path $script:packageConfig.OutputPaths.ValidationRoot "pester-appimage-validate-custom-args.log"
        $result = Invoke-GpAppImageValidation -Context $context -RunSmoke -LogPath $validationPath

        Assert-GpEqual -Actual $result.SmokeMode -Expected "custom-arguments" -Message "Custom-arguments smoke validation should report its configured mode."
        Assert-GpMatch -Actual (Get-Content -Raw -Path $result.SmokeLog) -Pattern "--smoke-arg" -Message "Custom-arguments smoke validation should pass the configured argument to the packaged app."
      } finally {
        if (Test-Path $manifestPath) {
          Remove-Item -Force $manifestPath
        }
      }
    }
  }

  Context "Runtime closure validation" {
    It "can fail strict validation when host-resolved libraries are outside the allowlist" {
      $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-appimage-runtime-" + [guid]::NewGuid().ToString("N"))
      $expandedRoot = Join-Path $tempRoot "squashfs-root"
      $binRoot = Join-Path $expandedRoot "usr/bin"
      $logPath = Join-Path $tempRoot "runtime-closure.log"

      New-Item -ItemType Directory -Force -Path $binRoot | Out-Null
      Copy-Item -Force "/bin/ls" (Join-Path $binRoot "fixture-ls")

      $config = [pscustomobject]@{
        Validation = [pscustomobject]@{
          RuntimeClosure = "strict"
          AllowedSystemLibraries = @("libc.so.6")
          AllowedExternalRunpaths = @()
        }
      }

      $threw = $false
      try {
        try {
          Invoke-GpAppImageRuntimeClosureValidation -Config $config -ExpandedRoot $expandedRoot -LogPath $logPath | Out-Null
        } catch {
          $threw = $true
          Assert-GpMatch -Actual $_.Exception.Message -Pattern "runtime-closure validation failed" -Message "Strict runtime validation should fail when external host libraries are not allowlisted."
        }

        Assert-GpTrue -Condition $threw -Message "Strict runtime validation should reject non-allowlisted host libraries."
        Assert-GpMatch -Actual (Get-Content -Raw -Path $logPath) -Pattern "external host library not allowlisted" -Message "Runtime validation logs should explain which host dependency caused the failure."
      } finally {
        if (Test-Path $tempRoot) {
          Remove-Item -Recurse -Force $tempRoot
        }
      }
    }
  }
}
