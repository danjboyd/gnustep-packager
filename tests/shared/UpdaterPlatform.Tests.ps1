Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Builds tests/fixtures/updater/asset-select-probe.m against GPUpdaterCore.
# "select" runs the asset choice for any platform; "check" runs a whole check
# on this machine's platform against a file feed. Off Windows only, with
# gnustep-config and make; skipped elsewhere.
Describe "Updater platform selection" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
    $script:probePath = $null

    if (-not $IsWindows -and (Get-Command gnustep-config -ErrorAction SilentlyContinue) -and (Get-Command make -ErrorAction SilentlyContinue)) {
      $buildRoot = Join-Path $script:repoRoot "dist/test-updater-platform"
      if (Test-Path $buildRoot) { Remove-Item -Recurse -Force $buildRoot }
      Ensure-GpDirectory -Path $buildRoot | Out-Null
      Copy-Item -Recurse -Path (Join-Path $script:repoRoot "updater/objc") -Destination $buildRoot
      $coreDirectory = Join-Path $buildRoot "objc/GPUpdaterCore"
      $output = & make -C $coreDirectory 2>&1
      if ($LASTEXITCODE -ne 0) { throw "GPUpdaterCore did not build:`n$($output -join "`n")" }

      # The probe finds its configuration beside it, as an installed app does.
      $script:appRoot = Ensure-GpDirectory -Path (Join-Path $buildRoot "app")
      $script:probePath = Join-Path $script:appRoot "asset-select-probe"
      $arguments = @((& gnustep-config --objc-flags) -split '\s+' | Where-Object { $_ }) + @(
        "-I", (Join-Path $coreDirectory "Headers"),
        "-o", $script:probePath,
        (Join-Path $script:repoRoot "tests/fixtures/updater/asset-select-probe.m"),
        (Join-Path $coreDirectory "libGPUpdaterCore.a")
      ) + @((& gnustep-config --base-libs) -split '\s+' | Where-Object { $_ })
      $output = & clang @arguments 2>&1
      if ($LASTEXITCODE -ne 0) { throw "asset-select-probe did not build:`n$($output -join "`n")" }

      $configDirectory = Ensure-GpDirectory -Path (Join-Path $script:appRoot "metadata/updates")
      [System.IO.File]::WriteAllText((Join-Path $configDirectory "gnustep-packager-update.json"), ([ordered]@{
        package = [ordered]@{ id = "com.example.MyGNUstepApp"; name = "MyGNUstepApp"; version = "1.2.2"; backend = "appimage" }
        updates = [ordered]@{ channel = "stable"; feedUrl = "https://example.invalid/updates/stable.json" }
      } | ConvertTo-Json -Depth 8))

      $libraryDirectories = @(
        foreach ($variable in @("GNUSTEP_USER_LIBRARIES", "GNUSTEP_LOCAL_LIBRARIES", "GNUSTEP_SYSTEM_LIBRARIES")) {
          & gnustep-config "--variable=$variable"
        }
      ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
      $gnustepRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Get-Command gnustep-config).Source))
      $libraryDirectories += @(
        Get-ChildItem -Path $gnustepRoot -Recurse -Filter "libdispatch.so*" -ErrorAction SilentlyContinue |
          ForEach-Object { $_.DirectoryName } | Select-Object -Unique
      )
      if (-not [string]::IsNullOrWhiteSpace($env:LD_LIBRARY_PATH)) { $libraryDirectories += $env:LD_LIBRARY_PATH }
      $script:libraryPath = $libraryDirectories -join ":"
    }

    function New-GpTestAsset {
      param([string]$Name, [string]$Platform, [string]$Backend = "appimage")
      $asset = [ordered]@{ backend = $Backend; kind = $Backend; name = $Name; url = "https://example.invalid/$Name" }
      if ($Platform) { $asset["platform"] = $Platform }
      return $asset
    }

    # Runs the probe with a private GNUstep home, so a check's last-check time
    # never reaches the real user defaults.
    function Invoke-GpPlatformProbe {
      param([string[]]$ArgumentList, [string]$FeedPath)
      $gnustepHome = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-platform-home-" + [guid]::NewGuid().ToString("N"))
      New-Item -ItemType Directory -Force -Path $gnustepHome | Out-Null
      try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new($script:probePath)
        foreach ($argument in $ArgumentList) { $startInfo.ArgumentList.Add($argument) }
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.WorkingDirectory = $script:appRoot
        $startInfo.Environment["LD_LIBRARY_PATH"] = $script:libraryPath
        $startInfo.Environment["GNUSTEP_HOME"] = $gnustepHome
        $startInfo.Environment["HOME"] = $gnustepHome
        $startInfo.Environment.Remove("GP_UPDATER_FEED_URL") | Out-Null
        if ($FeedPath) { $startInfo.Environment["GP_UPDATER_FEED_URL"] = ([System.Uri]::new($FeedPath)).AbsoluteUri }
        $process = [System.Diagnostics.Process]::Start($startInfo)
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $null = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "asset-select-probe exited with $($process.ExitCode)" }
        return $stdout.Result.Trim()
      } finally {
        Remove-Item -Recurse -Force $gnustepHome -ErrorAction SilentlyContinue
      }
    }

    function Invoke-GpSelect {
      param([string]$Platform, [object[]]$Assets, [string]$Backend = "appimage")
      $path = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-release-" + [guid]::NewGuid().ToString("N") + ".json")
      try {
        [System.IO.File]::WriteAllText($path, ([ordered]@{ version = "1.2.3"; assets = @($Assets) } | ConvertTo-Json -Depth 8))
        return Invoke-GpPlatformProbe -ArgumentList @("select", $Backend, $Platform, $path)
      } finally {
        Remove-Item -Force $path -ErrorAction SilentlyContinue
      }
    }

    function Invoke-GpCheck {
      param([object[]]$Releases)
      $path = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-feed-" + [guid]::NewGuid().ToString("N") + ".json")
      try {
        [System.IO.File]::WriteAllText($path, ([ordered]@{ formatVersion = 1; channel = "stable"; releases = @($Releases) } | ConvertTo-Json -Depth 10))
        return Invoke-GpPlatformProbe -ArgumentList @("check") -FeedPath $path
      } finally {
        Remove-Item -Force $path -ErrorAction SilentlyContinue
      }
    }
  }

  It "picks the asset for the machine's platform, wherever it is in the feed" {
    if ($null -eq $script:probePath) { Set-ItResult -Skipped -Because "GPUpdaterCore can't be built here"; return }
    $assets = @(
      (New-GpTestAsset -Name "App-arm64.AppImage" -Platform "linux-arm64"),
      (New-GpTestAsset -Name "App-x86_64.AppImage" -Platform "linux-x64")
    )
    Invoke-GpSelect -Platform "linux-x64" -Assets $assets | Should -Be "App-x86_64.AppImage"
    Invoke-GpSelect -Platform "linux-arm64" -Assets $assets | Should -Be "App-arm64.AppImage"
  }

  It "treats an asset with no platform as x64 only" {
    if ($null -eq $script:probePath) { Set-ItResult -Skipped -Because "GPUpdaterCore can't be built here"; return }
    $oldFeed = @((New-GpTestAsset -Name "App.AppImage" -Platform ""))
    Invoke-GpSelect -Platform "linux-x64" -Assets $oldFeed | Should -Be "App.AppImage" -Because "feeds before v0.1.9 had no platform and were x64"
    Invoke-GpSelect -Platform "linux-arm64" -Assets $oldFeed | Should -Be "none" -Because "an arm64 machine must not install an x64 build"
  }

  It "matches the backend as well as the platform" {
    if ($null -eq $script:probePath) { Set-ItResult -Skipped -Because "GPUpdaterCore can't be built here"; return }
    $assets = @((New-GpTestAsset -Name "App.msi" -Platform "linux-x64" -Backend "msi"))
    Invoke-GpSelect -Platform "linux-x64" -Assets $assets | Should -Be "none"
  }

  It "reports this machine's platform" {
    if ($null -eq $script:probePath) { Set-ItResult -Skipped -Because "GPUpdaterCore can't be built here"; return }
    $expected = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture) {
      "X64" { "linux-x64" }
      "Arm64" { "linux-arm64" }
      default { "linux-unknown" }
    }
    Invoke-GpPlatformProbe -ArgumentList @("platform") | Should -Be $expected
  }

  It "offers this machine's build when another platform's is listed first" {
    if ($null -eq $script:probePath) { Set-ItResult -Skipped -Because "GPUpdaterCore can't be built here"; return }
    $other = if ((Invoke-GpPlatformProbe -ArgumentList @("platform")) -eq "linux-x64") { "linux-arm64" } else { "linux-x64" }
    $mine = Invoke-GpPlatformProbe -ArgumentList @("platform")
    $result = Invoke-GpCheck -Releases @([ordered]@{
      version = "1.2.3"
      assets = @((New-GpTestAsset -Name "App-other.AppImage" -Platform $other), (New-GpTestAsset -Name "App-mine.AppImage" -Platform $mine))
    })
    $result | Should -Be "update App-mine.AppImage"
  }

  It "says a newer version has no build for this machine instead of reporting up to date" {
    if ($null -eq $script:probePath) { Set-ItResult -Skipped -Because "GPUpdaterCore can't be built here"; return }
    $mine = Invoke-GpPlatformProbe -ArgumentList @("platform")
    $other = if ($mine -eq "linux-x64") { "linux-arm64" } else { "linux-x64" }
    $result = Invoke-GpCheck -Releases @([ordered]@{ version = "1.2.3"; assets = @((New-GpTestAsset -Name "App-other.AppImage" -Platform $other)) })
    $result | Should -Match "^error Version 1\.2\.3 is available, but has no download for this computer \($([regex]::Escape($mine))\)\.$"
  }

  It "still offers an older matching release when only the newest lacks this machine's build" {
    if ($null -eq $script:probePath) { Set-ItResult -Skipped -Because "GPUpdaterCore can't be built here"; return }
    $mine = Invoke-GpPlatformProbe -ArgumentList @("platform")
    $other = if ($mine -eq "linux-x64") { "linux-arm64" } else { "linux-x64" }
    $result = Invoke-GpCheck -Releases @(
      [ordered]@{ version = "1.2.4"; assets = @((New-GpTestAsset -Name "App-1.2.4-other.AppImage" -Platform $other)) },
      [ordered]@{ version = "1.2.3"; assets = @((New-GpTestAsset -Name "App-1.2.3-mine.AppImage" -Platform $mine)) }
    )
    $result | Should -Be "update App-1.2.3-mine.AppImage"
  }
}
