Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Describe "AppImage architecture" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")

    function New-GpArchManifest {
      param([string]$Architecture)
      return @{
        package = @{ name = "App"; version = "1.2.3"; id = "com.example.App" }
        backends = @{ appimage = $(if ($Architecture) { @{ architecture = $Architecture } } else { @{} }) }
      }
    }
  }

  It "defaults to the build host's architecture" {
    $hostArch = Get-GpHostArchitecture
    $hostArch | Should -BeIn @("x86_64", "aarch64")
    Get-GpBackendArchitecture -Backend appimage -Manifest (New-GpArchManifest) | Should -Be $hostArch
    Get-GpBackendArchitecture -Backend appimage | Should -Be $hostArch
  }

  It "takes backends.appimage.architecture and maps it to the feed platform" {
    Get-GpBackendArchitecture -Backend appimage -Manifest (New-GpArchManifest -Architecture aarch64) | Should -Be "aarch64"
    Get-GpBackendArchitecture -Backend appimage -Manifest (New-GpArchManifest -Architecture x86_64) | Should -Be "x86_64"
    Get-GpUpdatePlatform -Backend appimage -Architecture (Get-GpBackendArchitecture -Backend appimage -Manifest (New-GpArchManifest -Architecture aarch64)) | Should -Be "linux-arm64"
    Get-GpBackendArchitecture -Backend msi -Manifest (New-GpArchManifest -Architecture aarch64) | Should -Be "x64" -Because "the MSI is x64 only"
  }

  It "refuses an architecture it can't build" {
    { Get-GpBackendArchitecture -Backend appimage -Manifest (New-GpArchManifest -Architecture riscv64) } | Should -Throw "*x86_64 or aarch64*"
  }

  It "names artifacts, zsync files and appimagetool by architecture through {arch}" {
    $defaults = Get-Content -Raw (Join-Path $script:repoRoot "defaults/backends/appimage/defaults.json") | ConvertFrom-Json -AsHashtable
    $appimage = $defaults["backends"]["appimage"]
    $appimage["artifactNamePattern"] | Should -Be "{name}-{version}-{arch}.AppImage"
    $appimage["updates"]["zsyncArtifactNamePattern"] | Should -Be "{name}-{version}-{arch}.AppImage.zsync"
    $appimage["downloadUrl"] | Should -BeLike "*/appimagetool-{arch}.AppImage"
    foreach ($arch in @("x86_64", "aarch64")) {
      Resolve-GpPatternTokens -Pattern $appimage["artifactNamePattern"] -Tokens @{ name = "App"; version = "1.2.3"; arch = $arch } | Should -Be "App-1.2.3-$arch.AppImage"
    }
    # An x86_64 build is named exactly as before {arch} existed.
    Resolve-GpPatternTokens -Pattern $appimage["downloadUrl"] -Tokens @{ arch = "x86_64" } | Should -Be "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
  }

  It "accepts the architecture in the schema" {
    $schema = Get-Content -Raw (Join-Path $script:repoRoot "schemas/gnustep-packager.schema.json") | ConvertFrom-Json -AsHashtable
    $schema["properties"]["backends"]["properties"]["appimage"]["properties"]["architecture"]["enum"] | Should -Be @("x86_64", "aarch64")
  }
}
