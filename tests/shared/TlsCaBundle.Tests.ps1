Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Describe "TLS CA bundle check" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")

    function New-GpCaContext {
      param(
        [hashtable]$Updates = @{},
        [hashtable]$Validation = @{},
        [hashtable]$LaunchEnv = @{},
        [hashtable]$Backends = @{},
        [hashtable]$PackagedDefaults = @{}
      )

      $launch = @{ env = $LaunchEnv }
      return [pscustomobject]@{
        Manifest = @{
          updates = $Updates
          validation = $Validation
          launch = $launch
          backends = $Backends
          packagedDefaults = $PackagedDefaults
        }
      }
    }

    function New-GpCaFile {
      param([string]$Root, [string]$Content = "-----BEGIN CERTIFICATE-----`nAAAA`n-----END CERTIFICATE-----`n")

      $directory = Join-Path $Root "usr/runtime/lib/gnustep-base/Versions/1.31/Resources/GSTLS"
      New-Item -ItemType Directory -Force -Path $directory | Out-Null
      Set-Content -Path (Join-Path $directory "ca-certificates.crt") -Value $Content
    }
  }

  BeforeEach {
    $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-tls-ca-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $script:root | Out-Null
  }

  AfterEach {
    Remove-Item -Recurse -Force $script:root -ErrorAction SilentlyContinue
  }

  It "says nothing for an app that doesn't fetch https" {
    $status = Get-GpTlsCaBundleStatus -Context (New-GpCaContext) -RootPath $script:root
    $status.Applies | Should -BeFalse
    $status.Warning | Should -BeNullOrEmpty
  }

  It "warns for an app with updates on and nothing to find a CA bundle from" {
    $status = Get-GpTlsCaBundleStatus -Context (New-GpCaContext -Updates @{ enabled = $true }) -RootPath $script:root
    $status.Applies | Should -BeTrue
    $status.Warning | Should -Match "CA bundle"
    $status.Warning | Should -Match "GS_TLS_CA_FILE"
  }

  It "warns for an app that declares it fetches https" {
    $status = Get-GpTlsCaBundleStatus -Context (New-GpCaContext -Validation @{ fetchesHttps = $true }) -RootPath $script:root
    $status.Warning | Should -Match "CA bundle"
  }

  It "lets validation.fetchesHttps false turn the warning off" {
    $status = Get-GpTlsCaBundleStatus -Context (New-GpCaContext -Updates @{ enabled = $true } -Validation @{ fetchesHttps = $false }) -RootPath $script:root
    $status.Applies | Should -BeFalse
  }

  It "finds gnustep-base's bundled file in the package" {
    New-GpCaFile -Root $script:root
    $status = Get-GpTlsCaBundleStatus -Context (New-GpCaContext -Updates @{ enabled = $true }) -RootPath $script:root
    $status.Warning | Should -BeNullOrEmpty
    $status.Source | Should -Match "ca-certificates\.crt"
  }

  It "doesn't count a bundled file with no certificates" {
    New-GpCaFile -Root $script:root -Content "nothing here"
    $status = Get-GpTlsCaBundleStatus -Context (New-GpCaContext -Updates @{ enabled = $true }) -RootPath $script:root
    $status.Warning | Should -Match "CA bundle"
  }

  It "accepts a launch environment setting, by either name" {
    foreach ($name in @("GS_TLS_CA_FILE", "SSL_CERT_FILE")) {
      $status = Get-GpTlsCaBundleStatus -Context (New-GpCaContext -Updates @{ enabled = $true } -LaunchEnv @{ $name = "{@runtimeRoot}/certs.pem" }) -RootPath $script:root
      $status.Warning | Should -BeNullOrEmpty
      $status.Source | Should -Match $name
    }
  }

  It "accepts the GSTLSCAFile default, in the AppImage's global defaults or the app's" {
    $backends = @{ appimage = @{ gnustepConfig = @{ globalDefaults = @{ GSTLSCAFile = "/etc/ssl/certs/ca-certificates.crt" } } } }
    $status = Get-GpTlsCaBundleStatus -Context (New-GpCaContext -Updates @{ enabled = $true } -Backends $backends) -RootPath $script:root
    $status.Warning | Should -BeNullOrEmpty

    $defaults = @{ appDomain = @{ values = @{ GSTLSCAFile = "/etc/ssl/certs/ca-certificates.crt" } } }
    $status = Get-GpTlsCaBundleStatus -Context (New-GpCaContext -Updates @{ enabled = $true } -PackagedDefaults $defaults) -RootPath $script:root
    $status.Warning | Should -BeNullOrEmpty
  }

  It "rejects a validation.fetchesHttps that isn't a boolean" {
    $manifestPath = Join-Path $script:repoRoot "examples/sample-linux/package.manifest.json"
    $manifest = Get-GpJsonFile -Path $manifestPath
    $manifest["validation"]["fetchesHttps"] = "yes"
    @(@(Test-GpManifest -Manifest $manifest) | Where-Object { $_ -like "*fetchesHttps*" }).Count | Should -Be 1
  }
}
