Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Describe "Theme input contract" {
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
        [string]$BaseManifestPath,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Customize
      )

      $manifest = Get-GpJsonFile -Path $BaseManifestPath
      & $Customize $manifest

      $manifestDirectory = Split-Path -Parent $BaseManifestPath
      $tempManifestPath = Join-Path $manifestDirectory ("pester-theme-inputs-" + [guid]::NewGuid().ToString("N") + ".json")
      $manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $tempManifestPath -Encoding utf8
      return $tempManifestPath
    }

    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    $script:manifestPath = Join-Path $script:repoRoot "examples\\sample-gui\\package.manifest.json"
    $script:downstreamGuiTemplatePath = Join-Path $script:repoRoot "examples\\downstream\\manifest-gnustep-gui.template.json"

    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
  }

  It "normalizes declared theme inputs and derives packagedDefaults.defaultTheme" {
    $manifestPath = $null

    try {
      $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:manifestPath -Customize {
        param($manifest)
        $manifest.Remove("packagedDefaults")
        $manifest["themeInputs"] = @(
          @{
            name = "WinUITheme"
            repo = "https://example.invalid/WinUITheme.git"
            ref = "v0.1.0"
            platforms = @("windows")
            required = $true
            default = $true
          }
        )
      }

      $context = Get-GpManifestContext -Path $manifestPath
      $themes = @(Get-GpThemeInputs -Manifest $context.Manifest -Backend "msi" -ActiveOnly)

      Assert-GpEqual -Actual $context.Manifest["packagedDefaults"]["defaultTheme"] -Expected "WinUITheme" -Message "A single default theme input should derive packagedDefaults.defaultTheme."
      Assert-GpEqual -Actual @($themes.Name) -Expected @("WinUITheme") -Message "Windows theme inputs should apply to the MSI backend."
      Assert-GpTrue -Condition $themes[0].Required -Message "The required flag should be preserved."
    } finally {
      if ($null -ne $manifestPath -and (Test-Path $manifestPath)) {
        Remove-Item -Force $manifestPath
      }
    }
  }

  It "rejects contradictory declared theme defaults" {
    $manifestPath = $null

    try {
      $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:manifestPath -Customize {
        param($manifest)
        $manifest["packagedDefaults"]["defaultTheme"] = "OtherTheme"
        $manifest["themeInputs"] = @(
          @{
            name = "WinUITheme"
            repo = "https://example.invalid/WinUITheme.git"
            platforms = @("windows")
            required = $true
            default = $true
          }
        )
      }

      $context = Get-GpManifestContext -Path $manifestPath
      $issues = @(Test-GpManifest -Manifest $context.Manifest)

      Assert-GpMatch -Actual ([string]::Join("`n", $issues)) -Pattern "packagedDefaults\.defaultTheme must match" -Message "Conflicting default theme declarations should fail manifest validation."
    } finally {
      if ($null -ne $manifestPath -and (Test-Path $manifestPath)) {
        Remove-Item -Force $manifestPath
      }
    }
  }

  It "adds automatic bundled-theme package contract declarations for required themes" {
    $manifestPath = $null

    try {
      $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:manifestPath -Customize {
        param($manifest)
        $manifest.Remove("packagedDefaults")
        $manifest["validation"]["packageContract"] = @{
          requiredContent = @()
        }
        $manifest["themeInputs"] = @(
          @{
            name = "WinUITheme"
            repo = "https://example.invalid/WinUITheme.git"
            platforms = @("windows")
            required = $true
            default = $false
          }
        )
      }

      $context = Get-GpManifestContext -Path $manifestPath
      $contracts = @(Get-GpPackageContractDeclarations -Context $context -SectionName "packageContract" -Backend "msi")

      Assert-GpEqual -Actual @($contracts.Kind) -Expected @("bundled-theme") -Message "Required theme inputs should create bundled-theme assertions automatically."
      Assert-GpEqual -Actual $contracts[0].Name -Expected "WinUITheme" -Message "The automatic bundled-theme assertion should name the declared theme."
    } finally {
      if ($null -ne $manifestPath -and (Test-Path $manifestPath)) {
        Remove-Item -Force $manifestPath
      }
    }
  }

  It "reports theme provisioning plans without network or build work in dry-run mode" {
    $manifestPath = $null
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-theme-inputs-" + [guid]::NewGuid().ToString("N"))

    try {
      $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:manifestPath -Customize {
        param($manifest)
        $manifest.Remove("packagedDefaults")
        $manifest["outputs"]["root"] = (Join-Path $tempRoot "dist")
        $manifest["outputs"]["packageRoot"] = (Join-Path $tempRoot "dist\\packages")
        $manifest["outputs"]["logRoot"] = (Join-Path $tempRoot "dist\\logs")
        $manifest["outputs"]["tempRoot"] = (Join-Path $tempRoot "dist\\tmp")
        $manifest["outputs"]["validationRoot"] = (Join-Path $tempRoot "dist\\validation")
        $manifest["themeInputs"] = @(
          @{
            name = "WinUITheme"
            repo = "https://example.invalid/WinUITheme.git"
            ref = "v0.1.0"
            platforms = @("windows")
            required = $true
            default = $true
          }
        )
      }

      $context = Get-GpManifestContext -Path $manifestPath
      $result = Invoke-GpThemeProvisioning -Context $context -Backend "msi" -DryRun
      $logText = Get-Content -Raw -Path $result.LogPath

      Assert-GpEqual -Actual @($result.Themes.Name) -Expected @("WinUITheme") -Message "Dry-run provisioning should report the active theme input."
      Assert-GpMatch -Actual $logText -Pattern "REPO\s+https://example\.invalid/WinUITheme\.git" -Message "Provisioning logs should include the theme source."
      Assert-GpMatch -Actual $logText -Pattern "BUILD\s+make clean; make; make install GNUSTEP_INSTALLATION_DOMAIN=USER" -Message "Provisioning logs should include the default build/install command."
    } finally {
      if ($null -ne $manifestPath -and (Test-Path $manifestPath)) {
        Remove-Item -Force $manifestPath
      }
      if (Test-Path $tempRoot) {
        Remove-Item -Recurse -Force $tempRoot
      }
    }
  }

  It "stages complete theme bundles and writes a theme payload report" {
    $manifestPath = $null
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-theme-report-" + [guid]::NewGuid().ToString("N"))
    $workspace = Join-Path $tempRoot "ReportThemeSource"
    $themeBundle = Join-Path $workspace "ReportTheme.theme"
    $themeResources = Join-Path $themeBundle "Resources"
    $themeImages = Join-Path $themeResources "ThemeImages"

    New-Item -ItemType Directory -Force -Path $themeImages | Out-Null
    Set-Content -Path (Join-Path $themeBundle "ReportTheme.dll") -Value "fixture executable"
    Set-Content -Path (Join-Path $themeImages "Button.png") -Value "fixture image"
    Set-Content -Path (Join-Path $themeResources "Info-gnustep.plist") -Value @"
{
  NSExecutable = ReportTheme;
  NSPrincipalClass = ReportTheme;
  GSThemeImages = ( "ThemeImages/Button.png" );
}
"@

    try {
      $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:manifestPath -Customize {
        param($manifest)
        $manifest.Remove("packagedDefaults")
        $manifest["payload"]["stageRoot"] = (Join-Path $tempRoot "stage")
        $manifest["outputs"]["root"] = (Join-Path $tempRoot "dist")
        $manifest["outputs"]["packageRoot"] = (Join-Path $tempRoot "dist\\packages")
        $manifest["outputs"]["logRoot"] = (Join-Path $tempRoot "dist\\logs")
        $manifest["outputs"]["tempRoot"] = (Join-Path $tempRoot "dist\\tmp")
        $manifest["outputs"]["validationRoot"] = (Join-Path $tempRoot "dist\\validation")
        $manifest["pipeline"]["build"]["command"] = "Write-Host build"
        $manifest["themeInputs"] = @(
          @{
            name = "ReportTheme"
            workspacePath = $workspace
            platforms = @("linux")
            required = $true
            default = $false
            build = @{
              command = "Write-Host theme-build"
            }
          }
        )
        $manifest["validation"]["packageContract"] = @{
          requiredContent = @(
            @{
              kind = "theme-resource"
              theme = "ReportTheme"
              path = "Resources/ThemeImages/Button.png"
            }
          )
        }
      }

      $context = Get-GpManifestContext -Path $manifestPath
      $stageRoot = Resolve-GpManifestPath -Context $context -RelativePath $context.Manifest["payload"]["stageRoot"]
      New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot "app\\SampleGNUstepApp.app") | Out-Null
      New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot "runtime") | Out-Null
      New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot "metadata") | Out-Null

      $result = Invoke-GpThemeProvisioning -Context $context
      $stagedTheme = Join-Path $stageRoot "runtime/lib/GNUstep/Themes/ReportTheme.theme"
      $report = Get-GpJsonFile -Path $result.ReportPath
      $contract = Invoke-GpPackageContractAssertions -Context $context -Scope stage -LogPath (Join-Path $tempRoot "theme-contract.log")
      $contractText = [string]::Join("`n", @($contract.Lines))

      Assert-GpTrue -Condition (Test-Path (Join-Path $stagedTheme "Resources/Info-gnustep.plist")) -Message "Theme staging should preserve Info-gnustep.plist."
      Assert-GpTrue -Condition (Test-Path (Join-Path $stagedTheme "Resources/ThemeImages/Button.png")) -Message "Theme staging should preserve resource directories."
      Assert-GpTrue -Condition (Test-Path $result.ReportPath) -Message "Theme provisioning should emit a payload report."
      Assert-GpEqual -Actual $report["themes"][0]["name"] -Expected "ReportTheme" -Message "The theme report should include the staged theme name."
      Assert-GpMatch -Actual ([string]::Join("`n", @($report["themes"][0]["resources"]))) -Pattern "Resources/ThemeImages/Button\.png" -Message "The theme report should include resource inventory."
      Assert-GpTrue -Condition (-not $contract.HasIssues) -Message "A complete theme bundle and declared theme resource should pass package contract checks."
      Assert-GpMatch -Actual $contractText -Pattern "theme-resource:ReportTheme:Resources/ThemeImages/Button\.png" -Message "Theme-resource diagnostics should identify the asserted resource."
    } finally {
      if ($null -ne $manifestPath -and (Test-Path $manifestPath)) {
        Remove-Item -Force $manifestPath
      }
      if (Test-Path $tempRoot) {
        Remove-Item -Recurse -Force $tempRoot
      }
    }
  }

  It "fails structural validation when referenced theme images are missing" {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-theme-structure-" + [guid]::NewGuid().ToString("N"))
    $stageRoot = Join-Path $tempRoot "stage"
    $themeBundle = Join-Path $stageRoot "runtime/lib/GNUstep/Themes/BrokenTheme.theme"
    $resources = Join-Path $themeBundle "Resources"
    $manifestPath = $null

    New-Item -ItemType Directory -Force -Path $resources | Out-Null
    Set-Content -Path (Join-Path $themeBundle "BrokenTheme.dll") -Value "fixture executable"
    Set-Content -Path (Join-Path $resources "Info-gnustep.plist") -Value @"
{
  NSExecutable = BrokenTheme;
  GSThemeImages = ( "ThemeImages/Missing.png" );
}
"@

    try {
      $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:manifestPath -Customize {
        param($manifest)
        $manifest.Remove("packagedDefaults")
        $manifest["payload"]["stageRoot"] = $stageRoot
        $manifest["outputs"]["root"] = (Join-Path $tempRoot "dist")
        $manifest["outputs"]["packageRoot"] = (Join-Path $tempRoot "dist\\packages")
        $manifest["outputs"]["logRoot"] = (Join-Path $tempRoot "dist\\logs")
        $manifest["outputs"]["tempRoot"] = (Join-Path $tempRoot "dist\\tmp")
        $manifest["outputs"]["validationRoot"] = (Join-Path $tempRoot "dist\\validation")
        $manifest["validation"]["packageContract"] = @{
          requiredContent = @(
            @{
              kind = "bundled-theme"
              name = "BrokenTheme"
            }
          )
        }
      }

      $context = Get-GpManifestContext -Path $manifestPath
      $contract = Invoke-GpPackageContractAssertions -Context $context -Scope stage -Backend "msi" -LogPath (Join-Path $tempRoot "broken-theme-contract.log")
      $contractText = [string]::Join("`n", @($contract.Lines))

      Assert-GpTrue -Condition $contract.HasIssues -Message "Bundled-theme validation should fail when GSThemeImages references are missing."
      Assert-GpMatch -Actual $contractText -Pattern "GSThemeImages resource is missing: ThemeImages/Missing\.png" -Message "Structural diagnostics should identify the missing referenced image."
    } finally {
      if ($null -ne $manifestPath -and (Test-Path $manifestPath)) {
        Remove-Item -Force $manifestPath
      }
      if (Test-Path $tempRoot) {
        Remove-Item -Recurse -Force $tempRoot
      }
    }
  }

  It "ships the downstream GNUstep GUI template with a required default WinUITheme input" {
    $context = Get-GpManifestContext -Path $script:downstreamGuiTemplatePath
    $issues = @()
    $issues += @(Test-GpManifestSchema -Path $context.ManifestPath)
    $issues += @(Test-GpManifest -Manifest $context.Manifest)
    $themes = @(Get-GpThemeInputs -Manifest $context.Manifest -Backend "msi" -ActiveOnly)
    $contracts = @(Get-GpPackageContractDeclarations -Context $context -SectionName "packageContract" -Backend "msi" | Where-Object { $_.Kind -eq "bundled-theme" })

    Assert-GpEqual -Actual @($issues) -Expected @() -Message "The downstream GUI manifest template should remain schema-valid."
    Assert-GpEqual -Actual $context.Manifest["packagedDefaults"]["defaultTheme"] -Expected "WinUITheme" -Message "The downstream GUI template should make WinUITheme the packaged default."
    Assert-GpEqual -Actual @($themes.Name) -Expected @("WinUITheme") -Message "The downstream GUI template should declare a Windows WinUITheme input."
    Assert-GpTrue -Condition $themes[0].Required -Message "The downstream GUI template should require the WinUITheme input."
    Assert-GpTrue -Condition $themes[0].Default -Message "The downstream GUI template should mark WinUITheme as the default input."
    Assert-GpEqual -Actual @($contracts.Name) -Expected @("WinUITheme") -Message "Required theme inputs should provide bundled-theme contracts without repeated template assertions."
  }
}
