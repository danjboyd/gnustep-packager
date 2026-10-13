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
      Assert-GpMatch -Actual $appRunText -Pattern ([regex]::Escape('export XDG_DATA_DIRS="${RUNTIME_ROOT}/share:${GP_HOST_XDG_DATA_DIRS:-/usr/local/share:/usr/share}"')) -Message "AppRun should prepend packaged data dirs to the host's, with the XDG default when the host has none."
      Assert-GpMatch -Actual $appRunText -Pattern ([regex]::Escape('export GP_HOST_XDG_DATA_DIRS="${XDG_DATA_DIRS:-}"')) -Message "AppRun should remember the host's value at the first launch, so relaunches don't stack entries."
      Assert-GpMatch -Actual $appRunText -Pattern ([regex]::Escape('export GP_FIXTURE_SEARCH_PATH="${RUNTIME_ROOT}/lib${GP_HOST_GP_FIXTURE_SEARCH_PATH:+:${GP_HOST_GP_FIXTURE_SEARCH_PATH}}"')) -Message "AppRun should prepend to a host value only when there is one."
      Assert-GpMatch -Actual $appRunText -Pattern 'APP_DEFAULTS_TOOL="\$RUNTIME_ROOT/bin/defaults"' -Message "AppRun should look for a bundled defaults tool when app-domain defaults are declared."
      Assert-GpMatch -Actual $appRunText -Pattern 'read "com\.example\.SampleGNUstepLinuxApp" "GSTheme"' -Message "AppRun should seed GSTheme through GNUstep defaults as well as the env fallback."
      Assert-GpMatch -Actual $appRunText -Pattern 'write "com\.example\.SampleGNUstepLinuxApp" "GSTheme" "\\"Adwaita\\""' -Message "AppRun should serialize the packaged theme as a GNUstep defaults write."
      Assert-GpMatch -Actual $appRunText -Pattern 'read "com\.example\.SampleGNUstepLinuxApp" "SampleFirstRunComplete"' -Message "AppRun should seed the configured defaults domain."
      Assert-GpMatch -Actual $appRunText -Pattern 'write "com\.example\.SampleGNUstepLinuxApp" "SamplePreferredWidth" "800"' -Message "AppRun should serialize integer app-domain defaults."
      Assert-GpMatch -Actual $appRunText -Pattern 'write "com\.example\.SampleGNUstepLinuxApp" "SampleWelcomeText" "\\"Packaged sample\\""' -Message "AppRun should serialize string app-domain defaults as GNUstep literals."
    }

    It "writes a relocatable GNUstep.conf that points into the bundled runtime" {
      Assert-GpTrue -Condition (Test-Path $script:packageResult.GnustepConfigPath) -Message "The AppDir should carry a GNUstep.conf."
      Assert-GpTrue -Condition (Test-Path $script:packageResult.GnustepThemedConfigPath) -Message "A default theme should add a second GNUstep.conf."
      $configText = Get-Content -Raw -Path $script:packageResult.GnustepConfigPath
      Assert-GpMatch -Actual $configText -Pattern '(?m)^GNUSTEP_SYSTEM_LIBRARY=\.\./\.\./System/Library$' -Message "GNUSTEP_SYSTEM_LIBRARY should be relative to the config file."
      Assert-GpMatch -Actual $configText -Pattern '(?m)^GNUSTEP_SYSTEM_TOOLS=\.\./\.\./System/Tools$' -Message "GNUSTEP_SYSTEM_TOOLS should point at the bundled tools (gdnc, gpbs)."
      Assert-GpMatch -Actual $configText -Pattern '(?m)^GNUSTEP_LOCAL_LIBRARY=\.\./\.\./System/Library$' -Message "The LOCAL domain should not fall back to the host's /usr/GNUstep/Local."
      Assert-GpTrue -Condition ($configText -notmatch '/usr/GNUstep') -Message "GNUstep.conf should name no host path."
      $themedDir = Split-Path -Parent $script:packageResult.GnustepThemedConfigPath
      $themedDefaults = Get-Content -Raw -Path (Join-Path $themedDir "GlobalDefaults.plist")
      Assert-GpMatch -Actual $themedDefaults -Pattern '"GSTheme" = "Adwaita";' -Message "The themed config should default GSTheme through GlobalDefaults.plist."
      Assert-GpMatch -Actual $themedDefaults -Pattern '"GSX11HandlesWindowDecorations" = NO;' -Message "The themed config should carry the theme's own defaults."
      Assert-GpMatch -Actual $themedDefaults -Pattern '"GSFirstCommandKey" = "Control_R";' -Message "A theme default should override a global default with the same key."
      Assert-GpTrue -Condition ($themedDefaults -notmatch 'Control_L') -Message "The overridden global value should not also appear in the themed config."
      $plainDefaults = Get-Content -Raw -Path (Join-Path (Split-Path -Parent $script:packageResult.GnustepConfigPath) "GlobalDefaults.plist")
      Assert-GpMatch -Actual $plainDefaults -Pattern '"GSFirstCommandKey" = "Control_L";' -Message "The plain config should carry the manifest's global defaults."
      Assert-GpTrue -Condition ($plainDefaults -notmatch 'GSTheme') -Message "The plain config should set no theme."
      Assert-GpTrue -Condition ($plainDefaults -notmatch 'GSX11HandlesWindowDecorations') -Message "The theme's own defaults should not apply without the theme."
      $mode = (& stat -c '%a' $script:packageResult.GnustepConfigPath).Trim()
      Assert-GpEqual -Actual $mode -Expected "644" -Message "gnustep-base ignores a GNUstep.conf that others can write."

      $appRunText = Get-Content -Raw -Path $script:packageResult.AppRunPath
      Assert-GpMatch -Actual $appRunText -Pattern ([regex]::Escape('GP_GNUSTEP_CONFIG_FILE="${USR}/runtime/etc/GNUstep/GNUstep.conf"')) -Message "AppRun should default to the plain bundled config."
      Assert-GpMatch -Actual $appRunText -Pattern ([regex]::Escape('*:GNOME:*) GP_GNUSTEP_CONFIG_FILE="${USR}/runtime/etc/GNUstep-default-theme/GNUstep.conf" ;;')) -Message "AppRun should pick the themed config on the named desktops."
      Assert-GpMatch -Actual $appRunText -Pattern ([regex]::Escape('export GNUSTEP_CONFIG_FILE="$GP_GNUSTEP_CONFIG_FILE"')) -Message "AppRun should export GNUSTEP_CONFIG_FILE."
    }

    It "launches against the bundled GNUstep tree from any location, with the theme only on the named desktops" {
      $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-appimage-gnustep-config-" + [guid]::NewGuid().ToString("N"))
      try {
        # A copy elsewhere stands in for a different AppImage mount point.
        $relocated = Join-Path $tempRoot "mnt/AppDir"
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $relocated) | Out-Null
        & cp -a $script:packageResult.AppDirRoot $relocated
        $appRun = Join-Path $relocated "AppRun"
        $expectedLibrary = Join-Path $relocated "usr/runtime/System/Library"

        foreach ($case in @(
          @{ Desktop = "ubuntu:GNOME"; Config = "usr/runtime/etc/GNUstep-default-theme/GNUstep.conf"; Theme = "Adwaita" },
          @{ Desktop = "KDE"; Config = "usr/runtime/etc/GNUstep/GNUstep.conf"; Theme = "" }
        )) {
          $marker = Join-Path $tempRoot ("marker-" + [guid]::NewGuid().ToString("N") + ".txt")
          $run = Invoke-GpAppImageCapturedTool -FilePath $appRun -ArgumentList @() -Environment @{
            HOME = $tempRoot
            XDG_CURRENT_DESKTOP = $case.Desktop
            GNUSTEP_CONFIG_FILE = "/etc/GNUstep/GNUstep.conf"
            GP_APPIMAGE_SMOKE_MARKER_PATH = $marker
            GP_FIXTURE_EXPECT_GNUSTEP_CONFIG = "1"
          }
          Assert-GpEqual -Actual $run.ExitCode -Expected 0 -Message "AppRun should reach the bundled System/Library on $($case.Desktop). Output: $($run.Text)"
          $markerText = Get-Content -Raw -Path $marker
          Assert-GpMatch -Actual $markerText -Pattern ("(?m)^gnustep_config=" + [regex]::Escape((Join-Path $relocated $case.Config)) + "$") -Message "AppRun should override a host GNUSTEP_CONFIG_FILE with the bundled one on $($case.Desktop)."
          Assert-GpMatch -Actual $markerText -Pattern ("(?m)^gnustep_system_library=" + [regex]::Escape($expectedLibrary) + "$") -Message "GNUstep.conf should resolve into the relocated AppDir."
          Assert-GpMatch -Actual $markerText -Pattern ("(?m)^gnustep_theme=" + [regex]::Escape($case.Theme) + "$") -Message "The default theme should apply only on the named desktops."
        }
      } finally {
        if (Test-Path $tempRoot) {
          Remove-Item -Recurse -Force $tempRoot
        }
      }
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

    It "packages an app that declares no file associations" {
      $manifestPath = New-GpSiblingManifest {
        param($manifest)
        $manifest["integrations"]["fileAssociations"] = @()
      }

      try {
        $context = Get-GpManifestContext -Path $manifestPath
        $logPath = Join-Path $script:packageConfig.OutputPaths.LogRoot "pester-appimage-package-no-associations.log"
        $result = Invoke-GpAppImagePackage -Context $context -LogPath $logPath
        $desktopText = Get-Content -Raw -Path $result.DesktopEntryPath
        $metadata = Get-GpJsonFile -Path $result.MetadataPath

        Assert-GpTrue -Condition (Test-Path $result.ArtifactPath) -Message "An app without file associations should still produce an AppImage."
        Assert-GpTrue -Condition ([string]::IsNullOrWhiteSpace([string]$result.MimePackagePath)) -Message "No MIME package should be generated without file associations."
        Assert-GpMatch -Actual $desktopText -Pattern "(?m)^Exec=AppRun\r?$" -Message "Without associations the desktop entry should not take file arguments."
        Assert-GpTrue -Condition ($desktopText -notmatch "(?m)^MimeType=") -Message "Without associations the desktop entry should omit MimeType."
        Assert-GpEqual -Actual @($metadata["desktop"]["mimeTypes"] | Where-Object { $_ }).Count -Expected 0 -Message "AppImage metadata should record no MIME types."
      } finally {
        if (Test-Path $manifestPath) {
          Remove-Item -Force $manifestPath
        }
      }
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
        Assert-GpMatch -Actual $markerText -Pattern "(?m)^path=(\S*/usr/runtime/bin:)?/usr/bin:/bin$" -Message "The smoke launch should get a minimal PATH (after AppRun's own runtime/bin), not the caller's."
        Assert-GpMatch -Actual $markerText -Pattern "(?m)^home=.*smoke-env/home$" -Message "The smoke launch should get a fresh HOME under the validation output."
        Assert-GpMatch -Actual $markerText -Pattern "(?m)^dbus=unix:path=.*no-session-bus$" -Message "The smoke launch should not reach the caller's session bus."
        Assert-GpMatch -Actual $markerText -Pattern "(?m)^gnustep_home=.*smoke-env/home$" -Message "The smoke launch should give GNUstep a fresh home too: gnustep-base ignores HOME."
        if (-not [string]::IsNullOrWhiteSpace($env:DISPLAY)) {
          Assert-GpMatch -Actual $markerText -Pattern "(?m)^wayland=$" -Message "With an X display, the smoke launch should not get the caller's WAYLAND_DISPLAY."
        }
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

  Context "Smoke failure detection" {
    It "fails the smoke launch when the app logs a missing GNUstep tool and keeps running" {
      $manifestPath = New-GpSiblingManifest {
        param($manifest)
        $manifest["backends"]["appimage"]["smoke"] = @{
          mode = "launch-only"
          environment = @{
            GP_FIXTURE_STDERR_LINE = "Unable to find the make_services tool."
          }
        }
      }

      try {
        $context = Get-GpManifestContext -Path $manifestPath
        $validationPath = Join-Path $script:packageConfig.OutputPaths.ValidationRoot "pester-appimage-validate-tool-missing.log"
        $message = $null
        try {
          Invoke-GpAppImageValidation -Context $context -RunSmoke -LogPath $validationPath | Out-Null
        } catch {
          $message = $_.Exception.Message
        }

        Assert-GpTrue -Condition ($null -ne $message) -Message "Smoke validation should fail when the app logs a missing GNUstep tool."
        Assert-GpMatch -Actual $message -Pattern "could not find a runtime component: Unable to find the make_services tool" -Message "The failure should name the reason and the logged line."
      } finally {
        if (Test-Path $manifestPath) {
          Remove-Item -Force $manifestPath
        }
      }
    }

    It "recognizes GNUstep exception and loader failures in smoke output" {
      foreach ($line in @(
        "*** NSTimer ignoring exception 'NSInternalInconsistencyException' (reason 'x') raised during posting of timer",
        "Problem posting <GSNotification: 0x1> Name: NSApplicationDidFinishLaunchingNotification: <NSException: 0x2> NAME:NSInternalInconsistencyException",
        "Terminating app due to uncaught exception NSRangeException",
        "./app: error while loading shared libraries: libgnustep-gui.so.0.32: cannot open shared object file",
        "Unable to find backend back-0_31"
      )) {
        Assert-GpTrue -Condition ($null -ne (Get-GpAppImageSmokeFailure -Output ("ok`n" + $line + "`nmore"))) -Message "Smoke output should count as a failure: $line"
      }
      Assert-GpTrue -Condition ($null -eq (Get-GpAppImageSmokeFailure -Output "Sample GNUstep Linux fixture running`nFailed to get _NET_WORKAREA")) -Message "Ordinary GNUstep noise should not fail the smoke launch."
    }

    It "reports no alert panels as an empty list, not as a skipped check" {
      if ([string]::IsNullOrWhiteSpace($env:DISPLAY) -or -not (Get-Command xwininfo -ErrorAction SilentlyContinue)) {
        Set-ItResult -Skipped -Because "it needs an X display and xwininfo"
        return
      }

      $process = Start-Process -FilePath "sleep" -ArgumentList @("5") -PassThru
      try {
        $alerts = Get-GpAppImageSmokeAlertWindows -Process $process -Environment @{ DISPLAY = $env:DISPLAY }
        Assert-GpTrue -Condition ($null -ne $alerts) -Message "A check that ran should return a list, even an empty one."
        Assert-GpEqual -Actual @($alerts).Count -Expected 0 -Message "A process with no windows has no alert panels."
      } finally {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
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
