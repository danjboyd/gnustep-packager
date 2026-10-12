Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Describe "Platform overrides and DMG manifest contract" {
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

    function New-GpSiblingManifest {
      param(
        [Parameter(Mandatory = $true)]
        [string]$BaseManifestPath,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Customize
      )

      $manifest = Get-GpJsonFile -Path $BaseManifestPath
      & $Customize $manifest

      $manifestDirectory = Split-Path -Parent $BaseManifestPath
      $tempManifestPath = Join-Path $manifestDirectory ("pester-platform-" + [guid]::NewGuid().ToString("N") + ".json")
      $manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $tempManifestPath -Encoding utf8
      $script:tempManifests += @($tempManifestPath)
      return $tempManifestPath
    }

    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    $script:linuxManifestPath = Join-Path $script:repoRoot "examples/sample-linux/package.manifest.json"
    $script:macosManifestPath = Join-Path $script:repoRoot "examples/sample-macos/package.manifest.json"
    $script:tempManifests = @()

    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
    . (Join-Path $script:repoRoot "backends\\dmg\\lib\\dmg.ps1")

    # A Linux GNUstep manifest that also ships a native macOS bundle: the macos
    # overlay swaps the pipeline and payload expectations and drops the
    # GNUstep-only settings that do not apply to a native app bundle.
    $script:dualManifestPath = New-GpSiblingManifest -BaseManifestPath $script:linuxManifestPath -Customize {
      param($manifest)
      $manifest["backends"]["dmg"] = @{
        enabled = $true
        signing = @{ identity = "-" }
        notarization = @{ enabled = $false; keychainProfileEnvVar = "GP_TEST_NOTARY_PROFILE" }
      }
      $manifest["platformOverrides"] = @{
        macos = @{
          profiles = @()
          pipeline = @{
            build = @{ command = "make -C macos" }
            stage = @{ command = "./scripts/stage-macos.sh dist/stage"; outputRoot = "dist/stage" }
          }
          launch = @{
            entryRelativePath = "app/SampleGNUstepLinuxApp.app/Contents/MacOS/SampleGNUstepLinuxApp"
            workingDirectory = "app"
            env = $null
          }
          packagedDefaults = $null
          validation = @{
            smoke = @{ requiredPaths = @("app/SampleGNUstepLinuxApp.app/Contents/Info.plist") }
            packageContract = $null
            installedResult = @{ requiredContent = @(); requiredPaths = @() }
          }
        }
      }
    }
  }

  AfterAll {
    foreach ($path in @($script:tempManifests)) {
      if (Test-Path $path) {
        Remove-Item -Force $path
      }
    }
  }

  It "applies the overlay for the requested platform only" {
    $linux = Get-GpManifestContext -Path $script:dualManifestPath -Platform linux
    $macos = Get-GpManifestContext -Path $script:dualManifestPath -Platform macos

    Assert-GpEqual -Actual $linux.TargetPlatform -Expected "linux" -Message "Explicit -Platform should win."
    Assert-GpEqual -Actual $linux.PlatformOverrideApplied -Expected $false -Message "No linux overlay is declared."
    Assert-GpEqual -Actual $linux.Manifest["pipeline"]["build"]["command"] -Expected "./scripts/build-fixture.sh out/build" -Message "Linux keeps the base pipeline."
    Assert-GpEqual -Actual $linux.Manifest["launch"]["env"]["GSTheme"]["value"] -Expected "Adwaita" -Message "Linux keeps the GNUstep launch environment."
    Assert-GpEqual -Actual @($linux.Manifest["launch"]["pathPrepend"]) -Expected @("runtime/bin") -Message "Linux keeps the gnustep-gui profile."

    Assert-GpEqual -Actual $macos.PlatformOverrideApplied -Expected $true -Message "The macos overlay should be applied."
    Assert-GpEqual -Actual $macos.Manifest["pipeline"]["build"]["command"] -Expected "make -C macos" -Message "macOS should use the overlay build command."
    Assert-GpEqual -Actual $macos.Manifest["pipeline"]["shell"]["kind"] -Expected "bash" -Message "Objects merge: the base shell survives."
    Assert-GpEqual -Actual @($macos.Manifest["launch"]["env"].Keys).Count -Expected 0 -Message "A null overlay value removes the key; defaults then supply an empty env."
    Assert-GpEqual -Actual @($macos.Manifest["launch"]["pathPrepend"]).Count -Expected 0 -Message "Dropping the profile drops its pathPrepend."
    Assert-GpTrue -Condition (-not $macos.Manifest.Contains("packagedDefaults")) -Message "packagedDefaults should be removed for macos."
    Assert-GpTrue -Condition (-not $macos.Manifest["validation"].Contains("packageContract")) -Message "validation.packageContract should be removed for macos."
    Assert-GpEqual -Actual @($macos.Manifest["validation"]["smoke"]["requiredPaths"]) -Expected @("app/SampleGNUstepLinuxApp.app/Contents/Info.plist") -Message "Arrays replace."
    Assert-GpEqual -Actual @(Test-GpManifest -Manifest $macos.Manifest).Count -Expected 0 -Message "The macos view should be a valid manifest."
    Assert-GpEqual -Actual @(Test-GpManifest -Manifest $linux.Manifest).Count -Expected 0 -Message "The linux view should be a valid manifest."
  }

  It "derives the target platform from the requested backend" {
    Assert-GpEqual -Actual (Get-GpManifestContext -Path $script:dualManifestPath -Backend dmg).TargetPlatform -Expected "macos" -Message "dmg targets macos."
    Assert-GpEqual -Actual (Get-GpManifestContext -Path $script:dualManifestPath -Backend appimage).TargetPlatform -Expected "linux" -Message "appimage targets linux."
    Assert-GpEqual -Actual (Get-GpManifestContext -Path $script:dualManifestPath -Backend msi).TargetPlatform -Expected "windows" -Message "msi targets windows."
    Assert-GpEqual -Actual (Get-GpManifestContext -Path $script:dualManifestPath).TargetPlatform -Expected (Get-GpHostEnvironment).Platform -Message "Without -Backend or -Platform the host platform applies."
    Assert-GpEqual -Actual @(Get-GpEnabledBackends -Manifest (Get-GpManifestContext -Path $script:dualManifestPath -Platform linux).Manifest) -Expected @("appimage", "dmg") -Message "Both backends stay enabled; each is selected with -Backend."
  }

  It "accepts platformOverrides in the schema and rejects identity overrides" {
    Assert-GpEqual -Actual @(Test-GpManifestSchema -Path $script:dualManifestPath).Count -Expected 0 -Message "The overlay manifest should satisfy the schema."

    $badPath = New-GpSiblingManifest -BaseManifestPath $script:dualManifestPath -Customize {
      param($manifest)
      $manifest["platformOverrides"]["macos"]["package"] = @{ version = "9.9.9" }
      $manifest["platformOverrides"]["beos"] = @{}
    }
    Assert-GpTrue -Condition (@(Test-GpManifestSchema -Path $badPath).Count -gt 0) -Message "Schema should reject package overrides and unknown platforms."
    $raw = Get-GpJsonFile -Path $badPath
    $issues = @(Test-GpManifest -Manifest $raw)
    Assert-GpTrue -Condition (@($issues | Where-Object { $_ -like "*must not override package*" }).Count -eq 1) -Message "Semantic validation should reject package overrides. Issues: $([string]::Join('; ', $issues))"
    Assert-GpTrue -Condition (@($issues | Where-Object { $_ -like "platformOverrides keys must be one of*" }).Count -eq 1) -Message "Semantic validation should reject unknown platforms."
  }

  It "validates the DMG fixture manifest and its backend settings" {
    Assert-GpEqual -Actual @(Test-GpManifestSchema -Path $script:macosManifestPath).Count -Expected 0 -Message "The macOS fixture manifest should satisfy the schema."
    $context = Get-GpManifestContext -Path $script:macosManifestPath -Backend dmg
    Assert-GpEqual -Actual @(Test-GpManifest -Manifest $context.Manifest).Count -Expected 0 -Message "The macOS fixture manifest should pass semantic validation."
    Assert-GpEqual -Actual $context.Manifest["backends"]["dmg"]["artifactNamePattern"] -Expected "{name}-{version}-macos-{arch}.dmg" -Message "DMG defaults should supply the artifact pattern."
    Assert-GpEqual -Actual $context.Manifest["backends"]["dmg"]["filesystem"] -Expected "APFS" -Message "APFS is the default filesystem."
    Assert-GpEqual -Actual $context.Manifest["backends"]["dmg"]["format"] -Expected "UDZO" -Message "UDZO is the default format."
    Assert-GpEqual -Actual $context.Manifest["backends"]["dmg"]["notarization"]["required"] -Expected $false -Message "Notarization is never required by default."
    Assert-GpEqual -Actual (Get-GpNoticeReportRelativePath -Manifest $context.Manifest -Backend dmg) -Expected "THIRD-PARTY-NOTICES.txt" -Message "The DMG notice report sits at the volume root."

    $badPath = New-GpSiblingManifest -BaseManifestPath $script:macosManifestPath -Customize {
      param($manifest)
      $manifest["backends"]["dmg"]["format"] = "UDBZ"
      $manifest["backends"]["dmg"]["filesystem"] = "FAT32"
      $manifest["backends"]["dmg"]["appBundleName"] = "SampleMacApp"
      $manifest["backends"]["dmg"]["notarization"]["keychainProfileEnvVar"] = "my profile secret"
    }
    Assert-GpTrue -Condition (@(Test-GpManifestSchema -Path $badPath).Count -gt 0) -Message "Schema should reject unsupported DMG settings."
    $issues = @(Test-GpManifest -Manifest (Get-GpManifestContext -Path $badPath -Backend dmg).Manifest)
    foreach ($expected in @("backends.dmg.format", "backends.dmg.filesystem", "backends.dmg.appBundleName", "keychainProfileEnvVar must be an environment variable name")) {
      Assert-GpTrue -Condition (@($issues | Where-Object { $_ -like "*$expected*" }).Count -ge 1) -Message "Expected an issue mentioning '$expected'. Issues: $([string]::Join('; ', $issues))"
    }
  }

  It "maps lipo architectures to the artifact arch token" {
    Assert-GpEqual -Actual (Get-GpDmgArchToken -Archs @("x86_64", "arm64")) -Expected "universal" -Message "Two slices make a universal build."
    Assert-GpEqual -Actual (Get-GpDmgArchToken -Archs @("arm64")) -Expected "arm64" -Message "A single slice keeps its name."
    Assert-GpEqual -Actual (Get-GpDmgArchToken -Archs @("x86_64")) -Expected "x86_64" -Message "A single slice keeps its name."
    Assert-GpEqual -Actual (Get-GpDmgArchToken -Archs @()) -Expected "unknown" -Message "Missing executables yield 'unknown'."
  }
}
