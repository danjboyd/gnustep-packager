Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Runs a real gp-update-helper. Set GP_UPDATE_HELPER_PATH to a built helper
# (on Windows, with the GNUstep runtime DLLs reachable on Path). Otherwise,
# off Windows, the test builds a copy of updater/objc under dist/ when
# gnustep-config and make are available, and is skipped when they are not.
# On Windows the helper has to be built in an MSYS2 CLANG64 shell, so there
# the test runs only with GP_UPDATE_HELPER_PATH.
Describe "Updater helper runtime" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")

    function Get-GpTestHelperPath {
      if (-not [string]::IsNullOrWhiteSpace($env:GP_UPDATE_HELPER_PATH)) {
        return $env:GP_UPDATE_HELPER_PATH
      }

      if ($IsWindows) {
        return $null
      }

      if (-not (Get-Command gnustep-config -ErrorAction SilentlyContinue) -or -not (Get-Command make -ErrorAction SilentlyContinue)) {
        return $null
      }

      $buildRoot = Join-Path $script:repoRoot "dist/test-updater-helper"
      if (Test-Path $buildRoot) {
        Remove-Item -Recurse -Force $buildRoot
      }
      Ensure-GpDirectory -Path $buildRoot | Out-Null
      Copy-Item -Recurse -Path (Join-Path $script:repoRoot "updater/objc") -Destination $buildRoot

      $helperDirectory = Join-Path $buildRoot "objc/gp-update-helper"
      $output = & make -C $helperDirectory 2>&1
      if ($LASTEXITCODE -ne 0) {
        throw "gp-update-helper did not build:`n$($output -join "`n")"
      }

      foreach ($name in @("gp-update-helper.exe", "gp-update-helper")) {
        $candidate = Join-Path $helperDirectory $name
        if (Test-Path $candidate) {
          return $candidate
        }
      }

      throw "gp-update-helper was built but not found in $helperDirectory"
    }

    $script:helperPath = Get-GpTestHelperPath
  }

  It "verifies a download when run outside the system directory with Windows' Path spelling" {
    if ($null -eq $script:helperPath) {
      Set-ItResult -Skipped -Because "GP_UPDATE_HELPER_PATH is not set and the helper can't be built here"
      return
    }

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-helper-test-" + [guid]::NewGuid().ToString("N"))
    $workingDirectory = Join-Path $root "cwd"
    $workingRoot = Join-Path $root "work"
    Ensure-GpDirectory -Path $workingDirectory | Out-Null
    Ensure-GpDirectory -Path $workingRoot | Out-Null

    try {
      $assetPath = Join-Path $root "MyGNUstepApp-1.2.3.msi"
      [System.IO.File]::WriteAllText($assetPath, "not really an installer")
      $sha256 = (Get-FileHash -Algorithm SHA256 -Path $assetPath).Hash.ToLowerInvariant()

      $planPath = Join-Path $root "plan.json"
      $statePath = Join-Path $root "update-state.json"
      $plan = [ordered]@{
        formatVersion = 1
        package = [ordered]@{
          id = "com.example.MyGNUstepApp"
          name = "MyGNUstepApp"
          displayName = "My GNUstep App"
          currentVersion = "1.2.2"
          backend = "msi"
        }
        asset = [ordered]@{
          backend = "msi"
          kind = "msi"
          name = "MyGNUstepApp-1.2.3.msi"
          url = ([System.Uri]::new($assetPath)).AbsoluteUri
          sha256 = $sha256
        }
        execution = [ordered]@{
          stateFile = $statePath
          workingRoot = $workingRoot
        }
      }
      [System.IO.File]::WriteAllText($planPath, ($plan | ConvertTo-Json -Depth 8))

      $startInfo = [System.Diagnostics.ProcessStartInfo]::new($script:helperPath)
      foreach ($argument in @("--mode", "prepare", "--plan", $planPath, "--state-file", $statePath)) {
        $startInfo.ArgumentList.Add($argument)
      }
      $startInfo.UseShellExecute = $false
      $startInfo.WorkingDirectory = $workingDirectory
      if ($IsWindows) {
        # A process the MSI launcher starts sees "Path", not "PATH".
        $pathValue = $startInfo.Environment["PATH"]
        $startInfo.Environment.Remove("PATH") | Out-Null
        $startInfo.Environment.Add("Path", $pathValue)
      } elseif (Get-Command gnustep-config -ErrorAction SilentlyContinue) {
        # GNUstep's libraries need not be on the default search path.
        $libraryDirectories = @(
          foreach ($variable in @("GNUSTEP_USER_LIBRARIES", "GNUSTEP_LOCAL_LIBRARIES", "GNUSTEP_SYSTEM_LIBRARIES")) {
            & gnustep-config "--variable=$variable"
          }
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        if (-not [string]::IsNullOrWhiteSpace($env:LD_LIBRARY_PATH)) {
          $libraryDirectories += $env:LD_LIBRARY_PATH
        }
        $startInfo.Environment["LD_LIBRARY_PATH"] = ($libraryDirectories -join ":")
      }

      $process = [System.Diagnostics.Process]::Start($startInfo)
      if (-not $process.WaitForExit(120000)) {
        $process.Kill()
        throw "gp-update-helper did not finish within two minutes."
      }

      $state = Get-GpJsonFile -Path $statePath
      $errorMessage = ""
      if ($state.Contains("error")) {
        $errorMessage = $state["error"]["message"]
      }
      if ($state["status"] -ne "readyToApply") {
        throw "Expected readyToApply, got $($state["status"]): $($state["message"]) $errorMessage"
      }
      if ($state["apply"]["mode"] -ne "msi-install") {
        throw "Expected the msi-install apply mode, got $($state["apply"]["mode"])"
      }
      if ($process.ExitCode -ne 0) {
        throw "gp-update-helper exited with $($process.ExitCode)"
      }
    } finally {
      Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
    }
  }
}
