Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# packagedDefaults.defaultTheme and appDomain.values are seeded into the domain
# the app reads: its CFBundleIdentifier, or its process name when it has none
# (+[NSUserDefaults initialize] in gnustep-base). Seeding package.id instead
# missed every app whose identifier differs, such as Adwaita's ThemeDemo, which
# has no CFBundleIdentifier and reads the domain "ThemeDemo".
Describe "Resolve-GpPackagedDefaultsDomain" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
    . (Join-Path $script:repoRoot "backends\\appimage\\lib\\theme-metadata.ps1")

    $script:workRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-defaults-domain-" + [guid]::NewGuid().ToString("N"))

    # A manifest context whose stage holds app/Demo.app/Demo, with the given
    # Resources/Info-gnustep.plist text (-NoPlist: none; -NoApp: nothing staged).
    function New-GpDomainContext {
      param([string]$Name, [string]$InfoPlist, [switch]$NoPlist, [switch]$NoApp, [hashtable]$PackagedDefaults)
      $root = Join-Path $script:workRoot $Name
      $stage = Join-Path $root "stage"
      New-Item -ItemType Directory -Force -Path $stage | Out-Null
      if (-not $NoApp) {
        $app = New-Item -ItemType Directory -Force -Path (Join-Path $stage "app/Demo.app/Resources")
        Set-Content -Path (Join-Path $stage "app/Demo.app/Demo") -Value "#!/bin/sh"
        if (-not $NoPlist) {
          Set-Content -Path (Join-Path $app.FullName "Info-gnustep.plist") -Value $InfoPlist
        }
      }
      if ($null -eq $PackagedDefaults) { $PackagedDefaults = @{ defaultTheme = "Adwaita" } }
      $manifest = [ordered]@{
        package = [ordered]@{ id = "io.example.DemoPackage" }
        payload = [ordered]@{ stageRoot = $stage }
        launch = [ordered]@{ entryRelativePath = "app/Demo.app/Demo"; workingDirectory = "app/Demo.app" }
        packagedDefaults = $PackagedDefaults
      }
      return [pscustomobject]@{
        Manifest = $manifest
        ManifestPath = (Join-Path $root "package.manifest.json")
        ManifestRoot = $root
        TargetPlatform = "linux"
      }
    }
  }

  AfterAll {
    if ($script:workRoot -and (Test-Path $script:workRoot)) {
      Remove-Item -Recurse -Force $script:workRoot
    }
  }

  It "uses the app's CFBundleIdentifier" {
    $context = New-GpDomainContext -Name "bundle-id" -InfoPlist '{ CFBundleIdentifier = "io.example.Demo"; NSExecutable = "Demo"; }'
    $result = Resolve-GpPackagedDefaultsDomain -Context $context
    $result.Domain | Should -Be "io.example.Demo"
    $result.Source | Should -Be "bundleIdentifier"
  }

  It "uses the process name when the Info plist has no CFBundleIdentifier, as gnustep-base does" {
    $context = New-GpDomainContext -Name "no-bundle-id" -InfoPlist '{ NSExecutable = "Demo"; NSPrincipalClass = "NSApplication"; }'
    $result = Resolve-GpPackagedDefaultsDomain -Context $context
    $result.Domain | Should -Be "Demo"
    $result.Source | Should -Be "processName"
  }

  It "uses the process name when the app has no Info plist" {
    $context = New-GpDomainContext -Name "no-plist" -NoPlist
    (Resolve-GpPackagedDefaultsDomain -Context $context).Domain | Should -Be "Demo"
  }

  It "keeps packagedDefaults.appDomain.domain when the manifest names one" {
    $context = New-GpDomainContext -Name "explicit" -InfoPlist '{ CFBundleIdentifier = "io.example.Demo"; }' -PackagedDefaults @{
      defaultTheme = "Adwaita"
      appDomain = @{ domain = "io.example.Chosen"; values = @{ FirstRun = $true } }
    }
    $result = Resolve-GpPackagedDefaultsDomain -Context $context
    $result.Domain | Should -Be "io.example.Chosen"
    $result.Source | Should -Be "manifest"
  }

  It "falls back to package.id when the Info plist can't be parsed" {
    $context = New-GpDomainContext -Name "malformed" -InfoPlist "not a plist {"
    $result = Resolve-GpPackagedDefaultsDomain -Context $context
    $result.Domain | Should -Be "io.example.DemoPackage"
    $result.Source | Should -Be "packageId"
  }

  It "falls back to package.id when the app isn't staged" {
    $context = New-GpDomainContext -Name "unstaged" -NoApp
    (Resolve-GpPackagedDefaultsDomain -Context $context).Source | Should -Be "packageId"
  }
}
