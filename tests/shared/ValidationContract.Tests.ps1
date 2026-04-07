Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Describe "Shared validation contract" {
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
      $tempManifestPath = Join-Path $manifestDirectory ("pester-validation-" + [guid]::NewGuid().ToString("N") + ".json")
      $manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $tempManifestPath -Encoding utf8
      return $tempManifestPath
    }

    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    $script:manifestPath = Join-Path $script:repoRoot "examples\\sample-gui\\package.manifest.json"

    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
  }

  It "accepts glob entries in validation.smoke.requiredPaths and logs matched paths" {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-validation-glob-" + [guid]::NewGuid().ToString("N"))
    $stageRoot = Join-Path $tempRoot "stage"
    $appPath = Join-Path $stageRoot "app\\SampleGNUstepApp.app\\SampleGNUstepApp.exe"
    $resourcePath = Join-Path $stageRoot "app\\SampleGNUstepApp.app\\Resources\\Info-gnustep.plist"
    $runtimeBinPath = Join-Path $stageRoot "runtime\\bin\\defaults.exe"
    $bundlePath = Join-Path $stageRoot "runtime\\lib\\GNUstep\\Bundles\\libgnustep-back-032.bundle\\libgnustep-back-032.dll"
    $metadataPath = Join-Path $stageRoot "metadata\\icons\\sample-icon.txt"
    $manifestPath = $null

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $appPath) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resourcePath) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $runtimeBinPath) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $bundlePath) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $metadataPath) | Out-Null
    Set-Content -Path $appPath -Value "fixture"
    Set-Content -Path $resourcePath -Value "fixture"
    Set-Content -Path $runtimeBinPath -Value "fixture"
    Set-Content -Path $bundlePath -Value "fixture"
    Set-Content -Path $metadataPath -Value "fixture"

    try {
      $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:manifestPath -Customize {
        param($manifest)
        $manifest["payload"]["stageRoot"] = $stageRoot
        $manifest["outputs"]["root"] = (Join-Path $tempRoot "dist")
        $manifest["outputs"]["packageRoot"] = (Join-Path $tempRoot "dist\\packages")
        $manifest["outputs"]["logRoot"] = (Join-Path $tempRoot "dist\\logs")
        $manifest["outputs"]["tempRoot"] = (Join-Path $tempRoot "dist\\tmp")
        $manifest["outputs"]["validationRoot"] = (Join-Path $tempRoot "dist\\validation")
        $manifest["validation"]["smoke"]["requiredPaths"] = @(
          "runtime/lib/GNUstep/Bundles/libgnustep-back-*.bundle/libgnustep-back-*.dll"
        )
      }

      $context = Get-GpManifestContext -Path $manifestPath
      $result = Invoke-GpSharedValidation -Context $context
      $logText = Get-Content -Raw -Path $result.LogPath

      Assert-GpTrue -Condition (Test-Path $result.LogPath) -Message "Shared validation should write a validation log."
      Assert-GpMatch -Actual $logText -Pattern "smoke:runtime/lib/GNUstep/Bundles/libgnustep-back-\*\.bundle/libgnustep-back-\*\.dll" -Message "The validation log should preserve the original glob pattern."
      Assert-GpMatch -Actual $logText -Pattern "MATCH.+libgnustep-back-032\.bundle.+libgnustep-back-032\.dll" -Message "The validation log should report the matched concrete path."
    } finally {
      if ($null -ne $manifestPath -and (Test-Path $manifestPath)) {
        Remove-Item -Force $manifestPath
      }
      if (Test-Path $tempRoot) {
        Remove-Item -Recurse -Force $tempRoot
      }
    }
  }

  It "fails glob validation when no required path matches" {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-validation-glob-miss-" + [guid]::NewGuid().ToString("N"))
    $stageRoot = Join-Path $tempRoot "stage"
    $appPath = Join-Path $stageRoot "app\\SampleGNUstepApp.app\\SampleGNUstepApp.exe"
    $resourcePath = Join-Path $stageRoot "app\\SampleGNUstepApp.app\\Resources\\Info-gnustep.plist"
    $runtimeBinPath = Join-Path $stageRoot "runtime\\bin\\defaults.exe"
    $metadataPath = Join-Path $stageRoot "metadata\\icons\\sample-icon.txt"
    $manifestPath = $null
    $threw = $false

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $appPath) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resourcePath) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $runtimeBinPath) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $metadataPath) | Out-Null
    Set-Content -Path $appPath -Value "fixture"
    Set-Content -Path $resourcePath -Value "fixture"
    Set-Content -Path $runtimeBinPath -Value "fixture"
    Set-Content -Path $metadataPath -Value "fixture"

    try {
      $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:manifestPath -Customize {
        param($manifest)
        $manifest["payload"]["stageRoot"] = $stageRoot
        $manifest["outputs"]["root"] = (Join-Path $tempRoot "dist")
        $manifest["outputs"]["packageRoot"] = (Join-Path $tempRoot "dist\\packages")
        $manifest["outputs"]["logRoot"] = (Join-Path $tempRoot "dist\\logs")
        $manifest["outputs"]["tempRoot"] = (Join-Path $tempRoot "dist\\tmp")
        $manifest["outputs"]["validationRoot"] = (Join-Path $tempRoot "dist\\validation")
        $manifest["validation"]["smoke"]["requiredPaths"] = @(
          "runtime/lib/GNUstep/Bundles/libgnustep-back-*.bundle/libgnustep-back-*.dll"
        )
      }

      $context = Get-GpManifestContext -Path $manifestPath
      try {
        Invoke-GpSharedValidation -Context $context | Out-Null
      } catch {
        $threw = $true
        Assert-GpMatch -Actual $_.Exception.Message -Pattern "Shared validation failed" -Message "Missing glob matches should fail shared validation."
      }

      Assert-GpTrue -Condition $threw -Message "Shared validation should fail when a required glob has no matches."
    } finally {
      if ($null -ne $manifestPath -and (Test-Path $manifestPath)) {
        Remove-Item -Force $manifestPath
      }
      if (Test-Path $tempRoot) {
        Remove-Item -Recurse -Force $tempRoot
      }
    }
  }
}
