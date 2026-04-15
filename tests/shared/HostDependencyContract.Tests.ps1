Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Describe "Host dependency contract" {
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
      $tempManifestPath = Join-Path $manifestDirectory ("pester-host-deps-" + [guid]::NewGuid().ToString("N") + ".json")
      $manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $tempManifestPath -Encoding utf8
      return $tempManifestPath
    }

    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    $script:manifestPath = Join-Path $script:repoRoot "examples\\sample-gui\\package.manifest.json"

    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
  }

  It "resolves manifest-declared Windows and Linux host dependency lists" {
    $manifestPath = $null

    try {
      $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:manifestPath -Customize {
        param($manifest)
        $manifest["hostDependencies"] = @{
          windows = @{
            msys2Packages = @("mingw-w64-clang-x86_64-cmark")
          }
          linux = @{
            aptPackages = @("libcmark-dev")
          }
        }
      }

      $context = Get-GpManifestContext -Path $manifestPath
      $dependencies = Get-GpHostDependencies -Context $context

      Assert-GpEqual -Actual @($dependencies.Groups.ProviderId) -Expected @("windows-msys2", "linux-apt") -Message "Resolved host dependency groups should track the active internal providers."
      Assert-GpEqual -Actual @($dependencies.WindowsMsys2Packages) -Expected @("mingw-w64-clang-x86_64-cmark") -Message "Resolved manifest should preserve declared Windows MSYS2 host dependencies."
      Assert-GpEqual -Actual @($dependencies.LinuxAptPackages) -Expected @("libcmark-dev") -Message "Resolved manifest should preserve declared Linux apt host dependencies."
    } finally {
      if ($null -ne $manifestPath -and (Test-Path $manifestPath)) {
        Remove-Item -Force $manifestPath
      }
    }
  }

  It "layers reusable host dependency profiles without changing the manifest shape" {
    $manifestPath = $null

    try {
      $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:manifestPath -Customize {
        param($manifest)
        $manifest["profiles"] = @("gnustep-gui", "gnustep-cmark")
        $manifest["hostDependencies"] = @{
          windows = @{
            msys2Packages = @("mingw-w64-clang-x86_64-libxml2")
          }
          linux = @{
            aptPackages = @("libxml2-dev")
          }
        }
      }

      $context = Get-GpManifestContext -Path $manifestPath
      $dependencies = Get-GpHostDependencies -Context $context

      Assert-GpEqual -Actual @($dependencies.WindowsMsys2Packages) -Expected @("mingw-w64-clang-x86_64-libxml2") -Message "Manifest values should still override reusable host dependency profile defaults."
      Assert-GpEqual -Actual @($dependencies.LinuxAptPackages) -Expected @("libxml2-dev") -Message "Manifest values should still win after reusable host dependency profiles are layered in."
    } finally {
      if ($null -ne $manifestPath -and (Test-Path $manifestPath)) {
        Remove-Item -Force $manifestPath
      }
    }
  }

  It "builds workflow host setup plans from shared manifest data" {
    $manifestPath = $null

    try {
      $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:manifestPath -Customize {
        param($manifest)
        $manifest["profiles"] = @("gnustep-gui", "gnustep-cmark")
      }

      $context = Get-GpManifestContext -Path $manifestPath
      $plan = Get-GpWorkflowHostSetupPlan -Context $context -Backend "msi" -AdditionalMsys2Packages "make mingw-w64-clang-x86_64-cmark"

      Assert-GpEqual -Actual $plan.HostSetupMode -Expected "install-and-verify" -Message "Hosted workflow runs should report install-and-verify mode."
      Assert-GpEqual -Actual $plan.ManifestMsys2PackageText -Expected "mingw-w64-clang-x86_64-cmark" -Message "Workflow planning should reuse manifest-driven MSYS2 packages."
      Assert-GpEqual -Actual $plan.ResolvedMsys2PackageText -Expected "make mingw-w64-clang-x86_64-cmark" -Message "Workflow planning should deduplicate additive and manifest-provided MSYS2 packages."
      Assert-GpEqual -Actual @($plan.Errors) -Expected @() -Message "Hosted workflow plans should not surface self-hosted additive-input errors."
    } finally {
      if ($null -ne $manifestPath -and (Test-Path $manifestPath)) {
        Remove-Item -Force $manifestPath
      }
    }
  }

  It "rejects workflow-only additive package inputs on verify-only self-hosted runs" {
    $manifestPath = $null

    try {
      $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:manifestPath -Customize {
        param($manifest)
        $manifest["profiles"] = @("gnustep-gui")
      }

      $context = Get-GpManifestContext -Path $manifestPath
      $plan = Get-GpWorkflowHostSetupPlan -Context $context -Backend "appimage" -SkipDefaultHostSetup -AdditionalAptPackages "libcmark-dev"

      Assert-GpEqual -Actual $plan.HostSetupMode -Expected "verify-only" -Message "Self-hosted workflow runs should report verify-only mode when default setup is disabled."
      Assert-GpTrue -Condition (@($plan.Errors).Count -eq 1) -Message "Self-hosted workflow planning should reject additive apt inputs that would otherwise be ignored."
      Assert-GpMatch -Actual $plan.Errors[0] -Pattern "appimage-apt-packages" -Message "Self-hosted workflow planning should explain which additive input is invalid in verify-only mode."
    } finally {
      if ($null -ne $manifestPath -and (Test-Path $manifestPath)) {
        Remove-Item -Force $manifestPath
      }
    }
  }

  It "fails early when declared Windows MSYS2 packages are missing and install mode is disabled" {
    $manifestPath = $null
    $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-host-deps-" + [guid]::NewGuid().ToString("N") + ".log")
    $originalGetPlatform = ${function:Get-GpHostPlatform}
    $originalGetMissingMsys2 = ${function:Get-GpMissingMsys2Packages}
    $threw = $false

    try {
      $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:manifestPath -Customize {
        param($manifest)
        $manifest["hostDependencies"] = @{
          windows = @{
            msys2Packages = @("mingw-w64-clang-x86_64-cmark")
          }
        }
      }
      ${function:Get-GpHostPlatform} = { return "windows" }
      ${function:Get-GpMissingMsys2Packages} = {
        param([string[]]$Packages)
        return @($Packages)
      }

      $context = Get-GpManifestContext -Path $manifestPath
      try {
        Invoke-GpHostDependencyPreflight -Context $context -LogPath $logPath | Out-Null
      } catch {
        $threw = $true
        Assert-GpMatch -Actual $_.Exception.Message -Pattern "Missing declared msys2 host dependencies" -Message "Missing Windows host dependencies should fail preflight with a precise message."
        Assert-GpMatch -Actual $_.Exception.Message -Pattern "mingw-w64-clang-x86_64-cmark" -Message "The missing package name should be included in the preflight failure."
      }

      Assert-GpTrue -Condition $threw -Message "Host dependency preflight should fail when declared Windows packages are missing and install mode is disabled."
      Assert-GpMatch -Actual (Get-Content -Raw -Path $logPath) -Pattern "MISSING mingw-w64-clang-x86_64-cmark" -Message "Preflight logs should record the missing Windows package."
    } finally {
      ${function:Get-GpHostPlatform} = $originalGetPlatform
      ${function:Get-GpMissingMsys2Packages} = $originalGetMissingMsys2
      if ($null -ne $manifestPath -and (Test-Path $manifestPath)) {
        Remove-Item -Force $manifestPath
      }
      if (Test-Path $logPath) {
        Remove-Item -Force $logPath
      }
    }
  }

  It "installs declared Linux apt packages during preflight when install mode is enabled" {
    $manifestPath = $null
    $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-host-deps-" + [guid]::NewGuid().ToString("N") + ".log")
    $originalGetPlatform = ${function:Get-GpHostPlatform}
    $originalGetMissingApt = ${function:Get-GpMissingAptPackages}
    $originalInstallApt = ${function:Install-GpAptPackages}
    $script:installedPackages = @()

    try {
      $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:manifestPath -Customize {
        param($manifest)
        $manifest["hostDependencies"] = @{
          linux = @{
            aptPackages = @("libcmark-dev")
          }
        }
      }
      ${function:Get-GpHostPlatform} = { return "linux" }
      ${function:Get-GpMissingAptPackages} = {
        param([string[]]$Packages)
        return @($Packages)
      }
      ${function:Install-GpAptPackages} = {
        param([string[]]$Packages)
        $script:installedPackages = @($Packages)
      }

      $context = Get-GpManifestContext -Path $manifestPath
      $result = Invoke-GpHostDependencyPreflight -Context $context -LogPath $logPath -InstallMissing
      $logText = Get-Content -Raw -Path $logPath

      Assert-GpEqual -Actual $result.HostPlatform -Expected "linux" -Message "Preflight should report the active Linux host platform."
      Assert-GpEqual -Actual @($script:installedPackages) -Expected @("libcmark-dev") -Message "Install mode should pass missing Linux apt packages to the installer hook."
      Assert-GpMatch -Actual $logText -Pattern "INSTALL libcmark-dev" -Message "Preflight logs should record the Linux package installation step."
    } finally {
      ${function:Get-GpHostPlatform} = $originalGetPlatform
      ${function:Get-GpMissingAptPackages} = $originalGetMissingApt
      ${function:Install-GpAptPackages} = $originalInstallApt
      if ($null -ne $manifestPath -and (Test-Path $manifestPath)) {
        Remove-Item -Force $manifestPath
      }
      if (Test-Path $logPath) {
        Remove-Item -Force $logPath
      }
    }
  }
}
