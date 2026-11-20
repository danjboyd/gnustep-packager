Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Two themeInputs for one backend: one default, one only installed (Workforce
# bundles Gumdrop next to Adwaita and WinUITheme). Both must be built and
# staged, the report and the AppImage theme metadata must list both with the
# right default flag, the default must be the one seeded, and each required
# theme gets its own bundled-theme contract check.
Describe "Two theme inputs on one backend" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
    . (Join-Path $script:repoRoot "scripts\lib\core.ps1")
    . (Join-Path $script:repoRoot "backends\appimage\lib\appimage.ps1")

    function New-GpFixtureTheme {
      param([string]$Workspace, [string]$Name)
      $bundle = Join-Path $Workspace "$Name.theme"
      $resources = Join-Path $bundle "Resources"
      New-Item -ItemType Directory -Force -Path $resources | Out-Null
      Set-Content -Path (Join-Path $bundle $Name) -Value "fixture executable"
      Set-Content -Path (Join-Path $resources "Info-gnustep.plist") -Value "{ NSExecutable = $Name; NSPrincipalClass = $Name; CFBundleIdentifier = org.example.$Name; }"
    }
  }

  BeforeEach {
    $script:tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-two-themes-" + [guid]::NewGuid().ToString("N"))
    $script:manifestPath = $null
  }

  AfterEach {
    if ($null -ne $script:manifestPath -and (Test-Path $script:manifestPath)) {
      Remove-Item -Force $script:manifestPath
    }
    if (Test-Path $script:tempRoot) {
      Remove-Item -Recurse -Force $script:tempRoot
    }
  }

  It "stages both, reports both, and seeds only the default" {
    # The fixture builds with a PowerShell no-op through the manifest's own
    # shell, which is how an AppImage theme input builds on a Linux host.
    if ($IsWindows) { return }

    $tempRoot = $script:tempRoot
    $primaryWorkspace = Join-Path $tempRoot "PrimarySource"
    $extraWorkspace = Join-Path $tempRoot "ExtraSource"
    New-GpFixtureTheme -Workspace $primaryWorkspace -Name "PrimaryTheme"
    New-GpFixtureTheme -Workspace $extraWorkspace -Name "ExtraTheme"

    $baseManifestPath = Join-Path $script:repoRoot "examples/sample-gui/package.manifest.json"
    $manifest = Get-GpJsonFile -Path $baseManifestPath
    $manifest.Remove("packagedDefaults")
    if ($manifest["launch"].Contains("env") -and ($manifest["launch"]["env"] -is [System.Collections.IDictionary])) {
      $manifest["launch"]["env"].Remove("GSTheme")
    }
    $manifest["payload"]["stageRoot"] = (Join-Path $tempRoot "stage")
    $manifest["outputs"]["root"] = (Join-Path $tempRoot "dist")
    $manifest["outputs"]["packageRoot"] = (Join-Path $tempRoot "dist/packages")
    $manifest["outputs"]["logRoot"] = (Join-Path $tempRoot "dist/logs")
    $manifest["outputs"]["tempRoot"] = (Join-Path $tempRoot "dist/tmp")
    $manifest["outputs"]["validationRoot"] = (Join-Path $tempRoot "dist/validation")
    # Only the theme inputs' own checks: sample-gui's contract names files
    # this fixture doesn't stage.
    $manifest["validation"]["packageContract"] = @{ requiredContent = @() }
    $manifest["themeInputs"] = @(
      @{ name = "PrimaryTheme"; workspacePath = $primaryWorkspace; platforms = @("appimage"); required = $true; default = $true; build = @{ command = "Write-Host primary-build" } },
      @{ name = "ExtraTheme"; workspacePath = $extraWorkspace; platforms = @("appimage"); required = $true; default = $false; build = @{ command = "Write-Host extra-build" } }
    )
    $script:manifestPath = Join-Path (Split-Path -Parent $baseManifestPath) ("pester-two-themes-" + [guid]::NewGuid().ToString("N") + ".json")
    $manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $script:manifestPath -Encoding utf8

    $context = Get-GpManifestContext -Path $script:manifestPath -Backend "appimage"
    $themeIssues = @(@(Test-GpManifest -Manifest $context.Manifest) | Where-Object { $_ -match "theme" })
    $themeIssues.Count | Should -Be 0 -Because ("a default and a non-default theme input on one backend are valid: " + ($themeIssues -join "; "))
    $context.Manifest["packagedDefaults"]["defaultTheme"] | Should -Be "PrimaryTheme" -Because "the input marked default supplies the default theme"

    $stageRoot = Resolve-GpManifestPath -Context $context -RelativePath $context.Manifest["payload"]["stageRoot"]
    foreach ($dir in @("app", "runtime", "metadata")) {
      New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot $dir) | Out-Null
    }

    $result = Invoke-GpThemeProvisioning -Context $context -Backend "appimage"
    @($result.Themes.Name) | Should -Be @("PrimaryTheme", "ExtraTheme")

    $themesRoot = Join-Path $stageRoot (Get-GpThemeStageRelativeRoot -Context $context -Backend "appimage")
    Test-Path (Join-Path $themesRoot "PrimaryTheme.theme/Resources/Info-gnustep.plist") | Should -BeTrue
    Test-Path (Join-Path $themesRoot "ExtraTheme.theme/Resources/Info-gnustep.plist") | Should -BeTrue -Because "a non-default theme input is installed beside the default"

    $report = Get-GpJsonFile -Path $result.ReportPath
    $byName = @{}
    foreach ($theme in @($report["themes"])) { $byName[[string]$theme["name"]] = $theme }
    $byName.Count | Should -Be 2
    $byName["PrimaryTheme"]["default"] | Should -BeTrue
    $byName["ExtraTheme"]["default"] | Should -BeFalse

    # The AppImage's theme metadata (the .themes.json sidecar's source) over
    # an AppDir whose usr/ is this stage.
    $appDir = Join-Path $tempRoot "AppDir"
    New-Item -ItemType Directory -Force -Path $appDir | Out-Null
    Copy-Item -Recurse -Path $stageRoot -Destination (Join-Path $appDir "usr")
    $themeReport = New-GpAppImageThemeReport -PayloadRoot $appDir -ExistingReport $report `
      -Package ([ordered]@{ id = "org.example.Two"; name = "Two"; version = "1.0.0" }) -EntryRelativePath "app/Foo.app/Foo"
    $sidecarThemes = @($themeReport["themes"])
    @($sidecarThemes | ForEach-Object { [string]$_["name"] }) | Sort-Object | Should -Be @("ExtraTheme", "PrimaryTheme")
    @($sidecarThemes | Where-Object { $_["default"] } | ForEach-Object { [string]$_["name"] }) | Should -Be @("PrimaryTheme") -Because "only the default theme input is flagged default"

    $bundled = @(@(Get-GpPackageContractDeclarations -Context $context -Backend "appimage") | Where-Object { [string]$_.Kind -eq "bundled-theme" } | ForEach-Object { [string]$_.Name })
    $bundled | Should -Contain "PrimaryTheme"
    $bundled | Should -Contain "ExtraTheme" -Because "a required non-default theme is still checked in the installed package"

    $stageContract = Invoke-GpPackageContractAssertions -Context $context -Scope stage -Backend "appimage" -LogPath (Join-Path $tempRoot "contract.log")
    $stageContract.HasIssues | Should -BeFalse -Because ("both staged themes should satisfy the contract: " + ([string]::Join("; ", @($stageContract.Lines))))
  }
}
