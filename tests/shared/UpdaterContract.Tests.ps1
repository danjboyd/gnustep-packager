Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Describe "Updater contract" {
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
      $tempManifestPath = Join-Path $manifestDirectory ("pester-updates-" + [guid]::NewGuid().ToString("N") + ".json")
      $manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $tempManifestPath -Encoding utf8
      return $tempManifestPath
    }

    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    $script:linuxManifestPath = Join-Path $script:repoRoot "examples/sample-linux/package.manifest.json"

    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
  }

  It "validates and resolves shared plus backend-specific update settings" {
    $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:linuxManifestPath -Customize {
      param($manifest)
      $manifest["updates"] = @{
        enabled = $true
        provider = "github-release-feed"
        channel = "stable"
        minimumCheckIntervalHours = 12
        startupDelaySeconds = 5
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
      $schemaIssues = @(Test-GpManifestSchema -Path $manifestPath)
      $context = Get-GpManifestContext -Path $manifestPath
      $issues = @(Test-GpManifest -Manifest $context.Manifest)
      $settings = Get-GpUpdateSettings -Context $context -Backend "appimage"

      Assert-GpEqual -Actual $schemaIssues.Count -Expected 0 -Message "Update-enabled manifests should satisfy the documented schema."
      Assert-GpEqual -Actual $issues.Count -Expected 0 -Message "Update-enabled manifests should satisfy custom manifest validation."
      Assert-GpTrue -Condition $settings.Enabled -Message "Shared updates should resolve as enabled."
      Assert-GpEqual -Actual $settings.Channel -Expected "stable" -Message "The shared update channel should resolve from the manifest."
      Assert-GpEqual -Actual $settings.GitHub.Tag -Expected "v0.1.0" -Message "Release tags should resolve from updates.github.tagPattern and package.version."
      Assert-GpEqual -Actual $settings.FeedUrl -Expected "https://example.invalid/updates/linux/stable.json" -Message "Backend-specific feed URLs should override shared update feed settings."
      Assert-GpEqual -Actual $settings.Platform -Expected "linux-x64" -Message "Update platform resolution should follow the selected backend."
      Assert-GpEqual -Actual $settings.RuntimeConfigRelativePath -Expected (Join-Path "metadata" "updates/gnustep-packager-update.json") -Message "Runtime config should live under the packaged metadata tree."
    } finally {
      if (Test-Path $manifestPath) {
        Remove-Item -Force $manifestPath
      }
    }
  }

  It "writes a packaged runtime config for updater clients" {
    $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:linuxManifestPath -Customize {
      param($manifest)
      $manifest["updates"] = @{
        enabled = $true
        provider = "github-release-feed"
        channel = "beta"
        minimumCheckIntervalHours = 6
        startupDelaySeconds = 3
        github = @{
          owner = "example-org"
          repo = "sample-gnustep-linux-app"
          tagPattern = "v{version}"
        }
      }
      $manifest["backends"]["appimage"]["updates"] = @{
        feedUrl = "https://example.invalid/updates/linux/beta.json"
      }
    }

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-updater-config-" + [guid]::NewGuid().ToString("N"))
    $metadataRoot = Join-Path $tempRoot "metadata"

    try {
      $context = Get-GpManifestContext -Path $manifestPath
      $configPath = Write-GpUpdateRuntimeConfig -Context $context -Backend "appimage" -MetadataRoot $metadataRoot
      $config = Get-GpJsonFile -Path $configPath

      Assert-GpTrue -Condition (Test-Path $configPath) -Message "Packaging should emit a runtime updater config when updates are enabled."
      Assert-GpEqual -Actual $config["package"]["backend"] -Expected "appimage" -Message "The runtime config should record the current backend."
      Assert-GpEqual -Actual $config["updates"]["channel"] -Expected "beta" -Message "The runtime config should preserve the configured channel."
      Assert-GpEqual -Actual $config["updates"]["feedUrl"] -Expected "https://example.invalid/updates/linux/beta.json" -Message "The runtime config should expose the resolved feed URL."
      Assert-GpEqual -Actual $config["updates"]["github"]["tag"] -Expected "v0.1.0" -Message "The runtime config should preserve the resolved release tag."
    } finally {
      if (Test-Path $manifestPath) {
        Remove-Item -Force $manifestPath
      }
      if (Test-Path $tempRoot) {
        Remove-Item -Recurse -Force $tempRoot
      }
    }
  }

  It "writes a release feed sidecar for downstream publishing" {
    $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:linuxManifestPath -Customize {
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
      }
    }

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-update-feed-" + [guid]::NewGuid().ToString("N"))
    $artifactPath = Join-Path $tempRoot "SampleGNUstepLinuxApp-0.1.0-x86_64.AppImage"
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    Set-Content -Path $artifactPath -Value "placeholder"

    try {
      $context = Get-GpManifestContext -Path $manifestPath
      $feedPath = Write-GpUpdateFeedDocument -Context $context -Backend "appimage" -ArtifactPath $artifactPath -Assets @(
        [ordered]@{
          backend = "appimage"
          platform = "linux-x64"
          kind = "appimage"
          name = "SampleGNUstepLinuxApp-0.1.0-x86_64.AppImage"
          url = "https://github.com/example-org/sample-gnustep-linux-app/releases/download/v0.1.0/SampleGNUstepLinuxApp-0.1.0-x86_64.AppImage"
          sha256 = "placeholder"
          sizeBytes = 11
        }
      )
      $feed = Get-GpJsonFile -Path $feedPath

      Assert-GpTrue -Condition (Test-Path $feedPath) -Message "Packaging should emit a backend-specific update feed sidecar."
      Assert-GpEqual -Actual $feed["channel"] -Expected "stable" -Message "The update feed should preserve the configured channel."
      Assert-GpEqual -Actual $feed["package"]["id"] -Expected "com.example.SampleGNUstepLinuxApp" -Message "The update feed should preserve package identity."
      Assert-GpEqual -Actual $feed["releases"][0]["tag"] -Expected "v0.1.0" -Message "The update feed should preserve the resolved release tag."
      Assert-GpEqual -Actual $feed["releases"][0]["assets"][0]["backend"] -Expected "appimage" -Message "The update feed should preserve backend-specific asset metadata."
    } finally {
      if (Test-Path $manifestPath) {
        Remove-Item -Force $manifestPath
      }
      if (Test-Path $tempRoot) {
        Remove-Item -Recurse -Force $tempRoot
      }
    }
  }

  It "requires a feed URL for every enabled backend when updates are enabled" {
    $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:linuxManifestPath -Customize {
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
        embedUpdateInformation = $true
      }
    }

    try {
      $context = Get-GpManifestContext -Path $manifestPath
      $issues = @(Test-GpManifest -Manifest $context.Manifest)

      Assert-GpTrue -Condition ($issues.Count -gt 0) -Message "Update-enabled manifests without a feed URL should fail validation."
      Assert-GpTrue -Condition (($issues -join "`n") -match [regex]::Escape("A feed URL is required for backend 'appimage' when updates.enabled is true.")) -Message "Validation should explain how to configure the missing feed URL."
    } finally {
      if (Test-Path $manifestPath) {
        Remove-Item -Force $manifestPath
      }
    }
  }
}
