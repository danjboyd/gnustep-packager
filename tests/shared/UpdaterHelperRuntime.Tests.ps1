Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Runs a real gp-update-helper. Set GP_UPDATE_HELPER_PATH to a built helper
# (on Windows, with the GNUstep runtime DLLs reachable on Path). Otherwise,
# off Windows, the test builds a copy of updater/objc under dist/ when
# gnustep-config and make are available, and is skipped when they are not.
# On Windows the helper has to be built in an MSYS2 CLANG64 shell, so there
# the test runs only with GP_UPDATE_HELPER_PATH.
#
# The install-outcome cases also build tests/fixtures/updater/apply-outcome-probe.m
# against GPUpdaterCore, and run only off Windows, where the helper finds a
# stand-in msiexec on PATH and writes apply-appimage.sh.
Describe "Updater helper runtime" {
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

    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")

    function Get-GpTestBuildRoot {
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

      $output = & make -C (Join-Path $buildRoot "objc/gp-update-helper") 2>&1
      if ($LASTEXITCODE -ne 0) {
        throw "gp-update-helper did not build:`n$($output -join "`n")"
      }

      return $buildRoot
    }

    function Get-GpTestHelperPath {
      if (-not [string]::IsNullOrWhiteSpace($env:GP_UPDATE_HELPER_PATH)) {
        return $env:GP_UPDATE_HELPER_PATH
      }

      if ($null -eq $script:buildRoot) {
        return $null
      }

      $helperDirectory = Join-Path $script:buildRoot "objc/gp-update-helper"
      foreach ($name in @("gp-update-helper.exe", "gp-update-helper")) {
        $candidate = Join-Path $helperDirectory $name
        if (Test-Path $candidate) {
          return $candidate
        }
      }

      throw "gp-update-helper was built but not found in $helperDirectory"
    }

    function Get-GpTestProbePath {
      if ($null -eq $script:buildRoot) {
        return $null
      }

      $coreDirectory = Join-Path $script:buildRoot "objc/GPUpdaterCore"
      $probePath = Join-Path $script:buildRoot "apply-outcome-probe"
      $objcFlags = @((& gnustep-config --objc-flags) -split '\s+' | Where-Object { $_ })
      $baseLibs = @((& gnustep-config --base-libs) -split '\s+' | Where-Object { $_ })
      $arguments = @($objcFlags) + @(
        "-I", (Join-Path $coreDirectory "Headers"),
        "-o", $probePath,
        (Join-Path $script:repoRoot "tests/fixtures/updater/apply-outcome-probe.m"),
        (Join-Path $coreDirectory "libGPUpdaterCore.a")
      ) + @($baseLibs)
      $output = & clang @arguments 2>&1
      if ($LASTEXITCODE -ne 0) {
        throw "apply-outcome-probe did not build:`n$($output -join "`n")"
      }

      return $probePath
    }

    # GNUstep's libraries need not be on the default search path.
    function Get-GpTestLibraryPath {
      if ($IsWindows -or -not (Get-Command gnustep-config -ErrorAction SilentlyContinue)) {
        return $null
      }

      $libraryDirectories = @(
        foreach ($variable in @("GNUSTEP_USER_LIBRARIES", "GNUSTEP_LOCAL_LIBRARIES", "GNUSTEP_SYSTEM_LIBRARIES")) {
          & gnustep-config "--variable=$variable"
        }
      ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
      # libgnustep-base needs libdispatch, which a managed install may keep
      # elsewhere under its root (gnustep-config is in <root>/System/Tools).
      $gnustepRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Get-Command gnustep-config).Source))
      $libraryDirectories += @(
        Get-ChildItem -Path $gnustepRoot -Recurse -Filter "libdispatch.so*" -ErrorAction SilentlyContinue |
          ForEach-Object { $_.DirectoryName } |
          Select-Object -Unique
      )
      if (-not [string]::IsNullOrWhiteSpace($env:LD_LIBRARY_PATH)) {
        $libraryDirectories += $env:LD_LIBRARY_PATH
      }
      return ($libraryDirectories -join ":")
    }

    # Runs a tool to completion and returns its exit code and standard output.
    function Invoke-GpTestTool {
      param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory,
        [hashtable]$Environment = @{},
        [switch]$WindowsPathSpelling
      )

      $startInfo = [System.Diagnostics.ProcessStartInfo]::new($FilePath)
      foreach ($argument in $ArgumentList) {
        $startInfo.ArgumentList.Add($argument)
      }
      $startInfo.UseShellExecute = $false
      $startInfo.RedirectStandardOutput = $true
      if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $startInfo.WorkingDirectory = $WorkingDirectory
      }
      if ($IsWindows -and $WindowsPathSpelling) {
        # A process the MSI launcher starts sees "Path", not "PATH".
        $pathValue = $startInfo.Environment["PATH"]
        $startInfo.Environment.Remove("PATH") | Out-Null
        $startInfo.Environment.Add("Path", $pathValue)
      }
      if ($null -ne $script:libraryPath) {
        $startInfo.Environment["LD_LIBRARY_PATH"] = $script:libraryPath
      }
      foreach ($name in $Environment.Keys) {
        $startInfo.Environment[$name] = [string]$Environment[$name]
      }

      $process = [System.Diagnostics.Process]::Start($startInfo)
      $outputTask = $process.StandardOutput.ReadToEndAsync()
      if (-not $process.WaitForExit(120000)) {
        $process.Kill()
        throw "$FilePath did not finish within two minutes."
      }
      $process.WaitForExit()

      return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Output = $outputTask.Result.Trim()
      }
    }

    function Get-GpTestOutcome {
      param(
        [Parameter(Mandatory = $true)]
        [string]$Directory
      )

      $result = Invoke-GpTestTool -FilePath $script:probePath -ArgumentList @("outcome", $Directory)
      if ($result.ExitCode -ne 0) {
        throw "apply-outcome-probe outcome exited with $($result.ExitCode)"
      }
      if ($result.Output -eq "null") {
        return $null
      }
      return ($result.Output | ConvertFrom-Json -AsHashtable)
    }

    function New-GpTestRoot {
      $root = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-helper-test-" + [guid]::NewGuid().ToString("N"))
      Ensure-GpDirectory -Path $root | Out-Null
      return $root
    }

    function Get-GpTestStateError {
      param([System.Collections.IDictionary]$State)

      if ($State.Contains("error")) {
        return $State["error"]["message"]
      }
      return ""
    }

    $script:buildRoot = Get-GpTestBuildRoot
    $script:helperPath = Get-GpTestHelperPath
    $script:probePath = Get-GpTestProbePath
    $script:libraryPath = Get-GpTestLibraryPath
  }

  It "verifies a download when run outside the system directory with Windows' Path spelling" {
    if ($null -eq $script:helperPath) {
      Set-ItResult -Skipped -Because "GP_UPDATE_HELPER_PATH is not set and the helper can't be built here"
      return
    }

    $root = New-GpTestRoot
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

      $result = Invoke-GpTestTool -FilePath $script:helperPath -ArgumentList @("--mode", "prepare", "--plan", $planPath, "--state-file", $statePath) -WorkingDirectory $workingDirectory -WindowsPathSpelling

      $state = Get-GpJsonFile -Path $statePath
      if ($state["status"] -ne "readyToApply") {
        throw "Expected readyToApply, got $($state["status"]): $($state["message"]) $(Get-GpTestStateError -State $state)"
      }
      if ($state["apply"]["mode"] -ne "msi-install") {
        throw "Expected the msi-install apply mode, got $($state["apply"]["mode"])"
      }
      if ($result.ExitCode -ne 0) {
        throw "gp-update-helper exited with $($result.ExitCode)"
      }
    } finally {
      Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
    }
  }

  It "reports a failed MSI install, with msiexec's exit code, at the next launch" {
    if ($null -eq $script:helperPath -or $null -eq $script:probePath) {
      Set-ItResult -Skipped -Because "it needs the helper and GPUpdaterCore built here, which happens only off Windows"
      return
    }

    $root = New-GpTestRoot
    try {
      # A stand-in msiexec that fails. Exit codes off Windows have 8 bits,
      # so it can't return 1625 itself; the next test covers that code.
      $toolDirectory = Ensure-GpDirectory -Path (Join-Path $root "tools")
      $msiexecPath = Join-Path $toolDirectory "msiexec"
      [System.IO.File]::WriteAllText($msiexecPath, "#!/bin/sh`nexit 89`n")
      & chmod +x $msiexecPath

      $packagePath = Join-Path $root "MyGNUstepApp-1.2.3.msi"
      [System.IO.File]::WriteAllText($packagePath, "not really an installer")
      $planPath = Join-Path $root "update-plan.json"
      $statePath = Join-Path $root "update-state.json"
      [System.IO.File]::WriteAllText($planPath, ([ordered]@{
        formatVersion = 1
        execution = [ordered]@{ stateFile = $statePath; workingRoot = $root }
      } | ConvertTo-Json -Depth 8))
      [System.IO.File]::WriteAllText($statePath, ([ordered]@{
        formatVersion = 1
        status = "readyToApply"
        downloadedPath = $packagePath
        apply = [ordered]@{ mode = "msi-install" }
      } | ConvertTo-Json -Depth 8))

      # What the app records as it quits to install.
      $downloadUrl = "https://example.invalid/releases/MyGNUstepApp-1.2.3.msi"
      $record = Invoke-GpTestTool -FilePath $script:probePath -ArgumentList @("record", $root, "1.2.3", "msi", $downloadUrl)
      Assert-GpEqual -Actual $record.ExitCode -Expected 0 -Message "The install request should be recorded."
      $pending = Get-GpTestOutcome -Directory $root
      Assert-GpTrue -Condition ($null -ne $pending -and -not [bool]$pending["failed"]) -Message "Before the install runs, the update is only ready to apply, not failed."

      $apply = Invoke-GpTestTool -FilePath $script:helperPath -ArgumentList @("--mode", "apply", "--plan", $planPath, "--state-file", $statePath) -Environment @{
        PATH = "${toolDirectory}:$env:PATH"
      }
      Assert-GpEqual -Actual $apply.ExitCode -Expected 1 -Message "The helper should fail when msiexec does."
      $state = Get-GpJsonFile -Path $statePath
      Assert-GpEqual -Actual $state["status"] -Expected "failed" -Message "The state should record the failed install."
      Assert-GpEqual -Actual $state["error"]["exitCode"] -Expected 89 -Message "The state should keep msiexec's exit code as a number."

      $outcome = Get-GpTestOutcome -Directory $root
      Assert-GpTrue -Condition ($null -ne $outcome) -Message "The next launch should find the failed install."
      Assert-GpTrue -Condition ([bool]$outcome["failed"]) -Message "The outcome should be a failure."
      Assert-GpEqual -Actual $outcome["installerExitCode"] -Expected 89 -Message "The outcome should carry msiexec's exit code."
      Assert-GpMatch -Actual $outcome["failureReason"] -Pattern "Windows Installer reported error 89" -Message "An unlisted code should still be named."
      Assert-GpEqual -Actual $outcome["downloadUrl"] -Expected $downloadUrl -Message "The outcome should offer the installer's download."
      Assert-GpEqual -Actual $outcome["version"] -Expected "1.2.3" -Message "The outcome should name the version that wasn't installed."

      Invoke-GpTestTool -FilePath $script:probePath -ArgumentList @("clear", $root) | Out-Null
      Assert-GpTrue -Condition ($null -eq (Get-GpTestOutcome -Directory $root)) -Message "Once shown, the failure should not be reported again."
      foreach ($name in @("apply-request.json", "update-state.json", "update-plan.json")) {
        Assert-GpTrue -Condition (-not (Test-Path (Join-Path $root $name))) -Message "Clearing should remove $name."
      }
    } finally {
      Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
    }
  }

  It "reports an MSI install refused by policy, as apply-msi.cmd records it, in plain words" {
    if ($null -eq $script:probePath) {
      Set-ItResult -Skipped -Because "it needs GPUpdaterCore built here, which happens only off Windows"
      return
    }

    # The line apply-msi.cmd writes for a failed install, taken from the
    # helper's source, with cmd's %CODE% as msiexec returns it under
    # DisableMsi (Windows Server's default).
    $helperSource = Get-Content -Raw -Path (Join-Path $script:repoRoot "updater/objc/gp-update-helper/Source/main.m")
    $match = [regex]::Match($helperSource, '"echo (\{\\"formatVersion\\": 1, \\"status\\": \\"failed\\", \\"message\\": \\"MSI installation failed\.\\".*?)>\\"%STATE%\.tmp\\"')
    Assert-GpTrue -Condition $match.Success -Message "apply-msi.cmd's failure line should be in main.m."
    $stateText = $match.Groups[1].Value.Replace('\"', '"').Replace("%CODE%", "1625")

    $root = New-GpTestRoot
    try {
      [System.IO.File]::WriteAllText((Join-Path $root "update-state.json"), $stateText)
      [System.IO.File]::WriteAllText((Join-Path $root "msiexec.log"), "MSI (s) (00:00): Product: refused by policy")
      Invoke-GpTestTool -FilePath $script:probePath -ArgumentList @("record", $root, "1.2.3", "msi", "https://example.invalid/a.msi") | Out-Null

      $outcome = Get-GpTestOutcome -Directory $root
      Assert-GpTrue -Condition ($null -ne $outcome -and [bool]$outcome["failed"]) -Message "apply-msi.cmd's failure should be found. State: $stateText"
      Assert-GpEqual -Actual $outcome["installerExitCode"] -Expected 1625 -Message "The outcome should carry msiexec's exit code."
      Assert-GpMatch -Actual $outcome["failureReason"] -Pattern "turned off on this computer by policy" -Message "1625 should be explained in plain words."
      Assert-GpMatch -Actual $outcome["logPath"] -Pattern "msiexec\.log$" -Message "The outcome should point at msiexec's log."
    } finally {
      Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
    }
  }

  It "reports an AppImage that could not be replaced at the next launch" {
    if ($null -eq $script:helperPath -or $null -eq $script:probePath) {
      Set-ItResult -Skipped -Because "it needs the helper and GPUpdaterCore built here, which happens only off Windows"
      return
    }

    $root = New-GpTestRoot
    try {
      $assetPath = Join-Path $root "MyGNUstepApp-1.2.3-x86_64.AppImage"
      [System.IO.File]::WriteAllText($assetPath, "not really an AppImage")
      $applications = Ensure-GpDirectory -Path (Join-Path $root "Applications")
      $currentPath = Join-Path $applications "MyGNUstepApp.AppImage"
      [System.IO.File]::WriteAllText($currentPath, "the current AppImage")
      $workingRoot = Ensure-GpDirectory -Path (Join-Path $root "work")
      $planPath = Join-Path $workingRoot "update-plan.json"
      $statePath = Join-Path $workingRoot "update-state.json"
      [System.IO.File]::WriteAllText($planPath, ([ordered]@{
        formatVersion = 1
        package = [ordered]@{ id = "com.example.MyGNUstepApp"; backend = "appimage" }
        asset = [ordered]@{
          backend = "appimage"
          kind = "appimage"
          name = "MyGNUstepApp-1.2.3-x86_64.AppImage"
          url = ([System.Uri]::new($assetPath)).AbsoluteUri
          sha256 = (Get-FileHash -Algorithm SHA256 -Path $assetPath).Hash.ToLowerInvariant()
        }
        execution = [ordered]@{
          stateFile = $statePath
          workingRoot = $workingRoot
          linux = [ordered]@{ currentAppImagePath = $currentPath }
        }
      } | ConvertTo-Json -Depth 8))

      # A PATH without appimageupdatetool, so the helper downloads and replaces.
      $prepare = Invoke-GpTestTool -FilePath $script:helperPath -ArgumentList @("--mode", "prepare", "--plan", $planPath, "--state-file", $statePath) -Environment @{ PATH = "/usr/bin:/bin" }
      $state = Get-GpJsonFile -Path $statePath
      Assert-GpEqual -Actual $state["status"] -Expected "readyToApply" -Message "Prepare should succeed ($($state["message"]) $(Get-GpTestStateError -State $state))."
      Assert-GpEqual -Actual $prepare.ExitCode -Expected 0 -Message "Prepare should exit cleanly."
      $scriptPath = $state["apply"]["script"]
      Assert-GpTrue -Condition (Test-Path $scriptPath) -Message "Prepare should write apply-appimage.sh."

      Invoke-GpTestTool -FilePath $script:probePath -ArgumentList @("record", $workingRoot, "1.2.3", "appimage", "https://example.invalid/MyGNUstepApp-1.2.3-x86_64.AppImage") | Out-Null

      # The AppImage's folder went away after the app quit (an unmounted
      # drive, say), so the new AppImage can't be put next to it.
      Remove-Item -Recurse -Force $applications
      $apply = Invoke-GpTestTool -FilePath "/bin/sh" -ArgumentList @($scriptPath, "")
      Assert-GpEqual -Actual $apply.ExitCode -Expected 1 -Message "The apply script should fail."

      $outcome = Get-GpTestOutcome -Directory $workingRoot
      Assert-GpTrue -Condition ($null -ne $outcome -and [bool]$outcome["failed"]) -Message "The next launch should find the failed AppImage update."
      Assert-GpEqual -Actual $outcome["installerExitCode"] -Expected 0 -Message "An AppImage failure has no installer exit code."
      Assert-GpMatch -Actual $outcome["failureReason"] -Pattern "could not be copied next to the current one" -Message "The reason should be the apply script's own."
      Assert-GpMatch -Actual $outcome["logPath"] -Pattern "apply-appimage\.log$" -Message "The outcome should point at the apply script's log."
    } finally {
      Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
    }
  }

  It "says nothing at launch unless an install the app quit for failed" {
    if ($null -eq $script:probePath) {
      Set-ItResult -Skipped -Because "it needs GPUpdaterCore built here, which happens only off Windows"
      return
    }

    $root = New-GpTestRoot
    try {
      $statePath = Join-Path $root "update-state.json"
      # A failure from preparing, which the app showed at the time.
      [System.IO.File]::WriteAllText($statePath, '{"formatVersion": 1, "status": "failed", "message": "Update download failed."}')
      Assert-GpTrue -Condition ($null -eq (Get-GpTestOutcome -Directory $root)) -Message "Without a recorded install request, nothing should be reported."

      Invoke-GpTestTool -FilePath $script:probePath -ArgumentList @("record", $root, "1.2.3", "msi", "https://example.invalid/a.msi") | Out-Null

      [System.IO.File]::WriteAllText($statePath, '{"formatVersion": 1, "status": "applying", "message": "Applying update..."}')
      Assert-GpTrue -Condition ($null -eq (Get-GpTestOutcome -Directory $root)) -Message "An install still under way should not be reported."

      [System.IO.File]::WriteAllText($statePath, '{"formatVersion": 1, "status": "completed", "message": "MSI installation completed."}')
      $outcome = Get-GpTestOutcome -Directory $root
      Assert-GpTrue -Condition ($null -ne $outcome -and -not [bool]$outcome["failed"]) -Message "A completed install is an outcome, not a failure."
      Assert-GpTrue -Condition (-not $outcome.Contains("failureReason")) -Message "A completed install has no failure reason."
    } finally {
      Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
    }
  }

  It "describes msiexec exit codes in plain words" {
    if ($null -eq $script:probePath) {
      Set-ItResult -Skipped -Because "it needs GPUpdaterCore built here, which happens only off Windows"
      return
    }

    foreach ($case in @(
      @{ Code = "1602"; Pattern = "cancelled" },
      @{ Code = "1603"; Pattern = "fatal error" },
      @{ Code = "1618"; Pattern = "another installation" },
      @{ Code = "1625"; Pattern = "turned off on this computer by policy" },
      @{ Code = "4242"; Pattern = "error 4242" }
    )) {
      $result = Invoke-GpTestTool -FilePath $script:probePath -ArgumentList @("describe", $case.Code)
      Assert-GpMatch -Actual $result.Output -Pattern $case.Pattern -Message "msiexec exit code $($case.Code) should be described."
    }
  }
}
