Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Builds tests/fixtures/updater/skip-version-probe.m against GPUpdaterCore and
# runs it with a throwaway GNUstep home. Like the helper runtime test, it builds
# only off Windows, with gnustep-config and make, and is skipped elsewhere.
Describe "Updater defaults" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")

    $script:probePath = $null
    $script:lastCheckProbePath = $null
    $script:startupCheckProbePath = $null
    $script:libraryPath = $null
    if (-not $IsWindows -and (Get-Command gnustep-config -ErrorAction SilentlyContinue) -and (Get-Command make -ErrorAction SilentlyContinue)) {
      $buildRoot = Join-Path $script:repoRoot "dist/test-updater-defaults"
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
      $script:probePath = Join-Path $buildRoot "skip-version-probe"
      $objcFlags = @((& gnustep-config --objc-flags) -split '\s+' | Where-Object { $_ })
      $baseLibs = @((& gnustep-config --base-libs) -split '\s+' | Where-Object { $_ })
      $arguments = @($objcFlags) + @(
        "-I", (Join-Path $coreDirectory "Headers"),
        "-o", $script:probePath,
        (Join-Path $script:repoRoot "tests/fixtures/updater/skip-version-probe.m"),
        (Join-Path $coreDirectory "libGPUpdaterCore.a")
      ) + @($baseLibs)
      $output = & clang @arguments 2>&1
      if ($LASTEXITCODE -ne 0) {
        throw "skip-version-probe did not build:`n$($output -join "`n")"
      }

      $script:lastCheckProbePath = Join-Path $buildRoot "last-check-probe"
      $arguments = @($objcFlags) + @(
        "-I", (Join-Path $coreDirectory "Headers"),
        "-o", $script:lastCheckProbePath,
        (Join-Path $script:repoRoot "tests/fixtures/updater/last-check-probe.m"),
        (Join-Path $coreDirectory "libGPUpdaterCore.a")
      ) + @($baseLibs)
      $output = & clang @arguments 2>&1
      if ($LASTEXITCODE -ne 0) {
        throw "last-check-probe did not build:`n$($output -join "`n")"
      }

      $script:startupCheckProbePath = Join-Path $buildRoot "startup-check-probe"
      $arguments = @($objcFlags) + @(
        "-I", (Join-Path $coreDirectory "Headers"),
        "-o", $script:startupCheckProbePath,
        (Join-Path $script:repoRoot "tests/fixtures/updater/startup-check-probe.m"),
        (Join-Path $coreDirectory "libGPUpdaterCore.a")
      ) + @($baseLibs)
      $output = & clang @arguments 2>&1
      if ($LASTEXITCODE -ne 0) {
        throw "startup-check-probe did not build:`n$($output -join "`n")"
      }

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

    function Invoke-GpSkipProbe {
      param([string]$GnustepHome, [string[]]$ArgumentList, [string]$ProbePath = $script:probePath)

      $startInfo = [System.Diagnostics.ProcessStartInfo]::new($ProbePath)
      foreach ($argument in $ArgumentList) {
        $startInfo.ArgumentList.Add($argument)
      }
      $startInfo.UseShellExecute = $false
      $startInfo.RedirectStandardOutput = $true
      $startInfo.RedirectStandardError = $true
      $startInfo.Environment["LD_LIBRARY_PATH"] = $script:libraryPath
      # gnustep-base takes the home directory from passwd unless GNUSTEP_HOME is set.
      $startInfo.Environment["GNUSTEP_HOME"] = $GnustepHome
      $startInfo.Environment["HOME"] = $GnustepHome
      # West of UTC: gnustep-base reads a stored date back shifted by the offset (see last-check-probe).
      $startInfo.Environment["TZ"] = "America/Chicago"
      $startInfo.Environment["GNUSTEP_TZ"] = "America/Chicago"
      $process = [System.Diagnostics.Process]::Start($startInfo)
      $stdoutTask = $process.StandardOutput.ReadToEndAsync()
      $null = $process.StandardError.ReadToEndAsync()
      $process.WaitForExit()
      return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $stdoutTask.Result.Trim() }
    }
  }

  It "keeps a skipped version when the app exits without -terminate:" {
    if ($null -eq $script:probePath) {
      Set-ItResult -Skipped -Because "GPUpdaterCore can't be built here (it needs gnustep-config and make, off Windows)"
      return
    }

    $gnustepHome = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-updater-defaults-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $gnustepHome | Out-Null
    try {
      $skip = Invoke-GpSkipProbe -GnustepHome $gnustepHome -ArgumentList @("skip", "1.2.3")
      if ($skip.ExitCode -ne 0) {
        throw "skip-version-probe skip exited with $($skip.ExitCode)"
      }
      $read = Invoke-GpSkipProbe -GnustepHome $gnustepHome -ArgumentList @("read")
      if ($read.Output -ne "1.2.3") {
        throw "The skipped version should survive an exit without -terminate:. Read: '$($read.Output)'"
      }
    } finally {
      Remove-Item -Recurse -Force $gnustepHome -ErrorAction SilentlyContinue
    }
  }

  It "keeps the last check time through writes and reads of the defaults, and counts a future or old one as due" {
    if ($null -eq $script:lastCheckProbePath) {
      Set-ItResult -Skipped -Because "GPUpdaterCore can't be built here (it needs gnustep-config and make, off Windows)"
      return
    }

    $gnustepHome = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-updater-defaults-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $gnustepHome | Out-Null
    function Invoke-Probe {
      (Invoke-GpSkipProbe -GnustepHome $gnustepHome -ArgumentList $args -ProbePath $script:lastCheckProbePath).Output
    }
    try {
      $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
      Invoke-Probe set "$now" | Out-Null
      foreach ($cycle in 1..2) {
        Invoke-Probe rewrite | Out-Null
        Invoke-Probe read | Should -Be "$now"
      }
      Invoke-Probe due | Should -Be "no"

      Invoke-Probe set "$($now + 30 * 86400)" | Out-Null
      Invoke-Probe due | Should -Be "yes"
      Invoke-Probe set "$($now - 30 * 86400)" | Out-Null
      Invoke-Probe due | Should -Be "yes"
    } finally {
      Remove-Item -Recurse -Force $gnustepHome -ErrorAction SilentlyContinue
    }
  }

  It "ignores a last check stored as a date, as releases up to v0.1.7 did, so one check is due" {
    if ($null -eq $script:lastCheckProbePath) {
      Set-ItResult -Skipped -Because "GPUpdaterCore can't be built here (it needs gnustep-config and make, off Windows)"
      return
    }

    $gnustepHome = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-updater-defaults-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $gnustepHome | Out-Null
    function Invoke-Probe {
      (Invoke-GpSkipProbe -GnustepHome $gnustepHome -ArgumentList $args -ProbePath $script:lastCheckProbePath).Output
    }
    try {
      $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
      Invoke-Probe legacy "$now" | Out-Null
      Invoke-Probe read | Should -Be "none"
      Invoke-Probe due | Should -Be "yes"
    } finally {
      Remove-Item -Recurse -Force $gnustepHome -ErrorAction SilentlyContinue
    }
  }

  It "doesn't run the launch check too when a check by hand comes first" {
    if ($null -eq $script:startupCheckProbePath) {
      Set-ItResult -Skipped -Because "GPUpdaterCore can't be built here (it needs gnustep-config and make, off Windows)"
      return
    }

    $gnustepHome = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-updater-defaults-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $gnustepHome | Out-Null
    try {
      (Invoke-GpSkipProbe -GnustepHome $gnustepHome -ArgumentList @() -ProbePath $script:startupCheckProbePath).Output | Should -Be "1"
    } finally {
      Remove-Item -Recurse -Force $gnustepHome -ErrorAction SilentlyContinue
    }
  }
}
