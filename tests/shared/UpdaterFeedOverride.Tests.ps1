Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Builds tests/fixtures/updater/feed-override-probe.m against GPUpdaterCore
# and runs it beside a packaged updater configuration, with GP_UPDATER_FEED_URL
# set. Like the helper runtime test, it builds only off Windows, with
# gnustep-config and make, and is skipped elsewhere.
Describe "Updater feed override" {
  BeforeAll {
    function Assert-GpEqual {
      param(
        [object]$Actual,
        [object]$Expected,
        [string]$Message
      )

      if ($Actual -ne $Expected) {
        throw "$Message Expected: $Expected Actual: $Actual"
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

    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")

    $script:packagedFeed = "https://example.invalid/updates/stable.json"
    $script:appRoot = $null
    $script:probePath = $null
    $script:libraryPath = $null

    if (-not $IsWindows -and (Get-Command gnustep-config -ErrorAction SilentlyContinue) -and (Get-Command make -ErrorAction SilentlyContinue)) {
      $buildRoot = Join-Path $script:repoRoot "dist/test-updater-feed-override"
      if (Test-Path $buildRoot) {
        Remove-Item -Recurse -Force $buildRoot
      }
      Ensure-GpDirectory -Path $buildRoot | Out-Null
      Copy-Item -Recurse -Path (Join-Path $script:repoRoot "updater/objc") -Destination $buildRoot

      $coreDirectory = Join-Path $buildRoot "objc/GPUpdaterCore"
      $output = & make -C $coreDirectory 2>&1
      if ($LASTEXITCODE -ne 0) {
        throw "GPUpdaterCore did not build:`n$($output -join "`n")"
      }

      # The probe finds the configuration the way an installed app does,
      # beside its executable.
      $script:appRoot = Ensure-GpDirectory -Path (Join-Path $buildRoot "app")
      $script:probePath = Join-Path $script:appRoot "feed-override-probe"
      $objcFlags = @((& gnustep-config --objc-flags) -split '\s+' | Where-Object { $_ })
      $baseLibs = @((& gnustep-config --base-libs) -split '\s+' | Where-Object { $_ })
      $arguments = @($objcFlags) + @(
        "-I", (Join-Path $coreDirectory "Headers"),
        "-o", $script:probePath,
        (Join-Path $script:repoRoot "tests/fixtures/updater/feed-override-probe.m"),
        (Join-Path $coreDirectory "libGPUpdaterCore.a")
      ) + @($baseLibs)
      $output = & clang @arguments 2>&1
      if ($LASTEXITCODE -ne 0) {
        throw "feed-override-probe did not build:`n$($output -join "`n")"
      }

      $configDirectory = Ensure-GpDirectory -Path (Join-Path $script:appRoot "metadata/updates")
      [System.IO.File]::WriteAllText((Join-Path $configDirectory "gnustep-packager-update.json"), ([ordered]@{
        package = [ordered]@{ id = "com.example.MyGNUstepApp"; name = "MyGNUstepApp"; version = "1.2.2"; backend = "appimage" }
        updates = [ordered]@{ channel = "stable"; feedUrl = $script:packagedFeed }
      } | ConvertTo-Json -Depth 8))

      # GNUstep's libraries need not be on the default search path.
      $libraryDirectories = @(
        foreach ($variable in @("GNUSTEP_USER_LIBRARIES", "GNUSTEP_LOCAL_LIBRARIES", "GNUSTEP_SYSTEM_LIBRARIES")) {
          & gnustep-config "--variable=$variable"
        }
      ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
      $gnustepRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Get-Command gnustep-config).Source))
      $libraryDirectories += @(
        Get-ChildItem -Path $gnustepRoot -Recurse -Filter "libdispatch.so*" -ErrorAction SilentlyContinue |
          ForEach-Object { $_.DirectoryName } |
          Select-Object -Unique
      )
      if (-not [string]::IsNullOrWhiteSpace($env:LD_LIBRARY_PATH)) {
        $libraryDirectories += $env:LD_LIBRARY_PATH
      }
      $script:libraryPath = $libraryDirectories -join ":"
    }

    # The probe's feed URL (stdout) and log (stderr), with GP_UPDATER_FEED_URL
    # set to the given value, or unset.
    function Invoke-GpFeedProbe {
      param([string]$FeedOverride)

      $startInfo = [System.Diagnostics.ProcessStartInfo]::new($script:probePath)
      $startInfo.UseShellExecute = $false
      $startInfo.RedirectStandardOutput = $true
      $startInfo.RedirectStandardError = $true
      $startInfo.WorkingDirectory = $script:appRoot
      $startInfo.Environment["LD_LIBRARY_PATH"] = $script:libraryPath
      $startInfo.Environment.Remove("GP_UPDATER_FEED_URL") | Out-Null
      if (-not [string]::IsNullOrEmpty($FeedOverride)) {
        $startInfo.Environment["GP_UPDATER_FEED_URL"] = $FeedOverride
      }

      $process = [System.Diagnostics.Process]::Start($startInfo)
      $stdoutTask = $process.StandardOutput.ReadToEndAsync()
      $stderrTask = $process.StandardError.ReadToEndAsync()
      $process.WaitForExit()
      if ($process.ExitCode -ne 0) {
        throw "feed-override-probe exited with $($process.ExitCode): $($stderrTask.Result)"
      }

      return [pscustomobject]@{
        FeedUrl = $stdoutTask.Result.Trim()
        Log = $stderrTask.Result
      }
    }
  }

  It "uses the packaged feed without an override" {
    if ($null -eq $script:probePath) {
      Set-ItResult -Skipped -Because "GPUpdaterCore can't be built here (it needs gnustep-config and make, off Windows)"
      return
    }

    $result = Invoke-GpFeedProbe
    Assert-GpEqual -Actual $result.FeedUrl -Expected $script:packagedFeed -Message "Without GP_UPDATER_FEED_URL the packaged feed should be used."
  }

  It "takes an https feed, or an http feed on this machine, and logs it as a test feed" {
    if ($null -eq $script:probePath) {
      Set-ItResult -Skipped -Because "GPUpdaterCore can't be built here (it needs gnustep-config and make, off Windows)"
      return
    }

    foreach ($feed in @(
      "https://staging.example.invalid/updates/stable.json",
      "http://127.0.0.1:8000/stable.json",
      "http://localhost:8000/stable.json",
      "http://[::1]:8000/stable.json",
      "file:///tmp/gp-test-feed/stable.json"
    )) {
      $result = Invoke-GpFeedProbe -FeedOverride $feed
      Assert-GpEqual -Actual $result.FeedUrl -Expected $feed -Message "GP_UPDATER_FEED_URL=$feed should replace the packaged feed."
      Assert-GpMatch -Actual $result.Log -Pattern "TESTING: the update feed is overridden by GP_UPDATER_FEED_URL" -Message "Using the override should be logged."
    }
  }

  It "ignores, and logs, an override that isn't https or local" {
    if ($null -eq $script:probePath) {
      Set-ItResult -Skipped -Because "GPUpdaterCore can't be built here (it needs gnustep-config and make, off Windows)"
      return
    }

    foreach ($feed in @(
      "http://updates.example.invalid/stable.json",
      "http://127.0.0.1.example.invalid/stable.json",
      "ftp://example.invalid/stable.json",
      "not a url"
    )) {
      $result = Invoke-GpFeedProbe -FeedOverride $feed
      Assert-GpEqual -Actual $result.FeedUrl -Expected $script:packagedFeed -Message "GP_UPDATER_FEED_URL=$feed should be ignored."
      Assert-GpMatch -Actual $result.Log -Pattern "ignoring the test feed in GP_UPDATER_FEED_URL" -Message "Ignoring the override should be logged."
    }
  }
}
