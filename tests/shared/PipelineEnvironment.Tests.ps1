Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Describe "Pipeline command environment" {
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

    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    $script:baseManifestPath = Join-Path $script:repoRoot "examples/sample-linux/package.manifest.json"
    $script:toolScript = Join-Path $script:repoRoot "scripts/gnustep-packager.ps1"
    $script:pwshPath = (Get-Process -Id $PID).Path

    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")

    # A sibling of the sample manifest whose build and stage commands record
    # the package version variables they see, one line per step.
    function New-GpVersionRecordingManifest {
      param(
        [Parameter(Mandatory = $true)]
        [string]$RecordPath
      )

      $manifest = Get-GpJsonFile -Path $script:baseManifestPath
      $quotedPath = $RecordPath.Replace("'", "''")
      $manifest["pipeline"]["shell"] = [ordered]@{ kind = "pwsh"; program = $script:pwshPath; bootstrapCommands = @(); environment = @{} }
      foreach ($step in @("build", "stage")) {
        $manifest["pipeline"][$step]["command"] = "Add-Content -Path '$quotedPath' -Value ('$step|' + `$env:GP_PACKAGE_VERSION + '|' + `$env:GP_PACKAGE_VERSION_OVERRIDE)"
      }

      $manifestPath = Join-Path (Split-Path -Parent $script:baseManifestPath) ("pester-pipeline-env-" + [guid]::NewGuid().ToString("N") + ".json")
      $manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $manifestPath -Encoding utf8
      return $manifestPath
    }

    # Runs build and stage through the CLI, as run-packaging-pipeline.ps1
    # does, in a child pwsh with the given variables set beforehand.
    function Invoke-GpRecordedSteps {
      param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath,
        [string]$PackageVersion,
        [hashtable]$CallerEnvironment = @{}
      )

      foreach ($step in @("build", "stage")) {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new($script:pwshPath)
        foreach ($argument in @("-NoProfile", "-File", $script:toolScript, "-Command", $step, "-Manifest", $ManifestPath)) {
          $startInfo.ArgumentList.Add($argument)
        }
        if (-not [string]::IsNullOrWhiteSpace($PackageVersion)) {
          $startInfo.ArgumentList.Add("-PackageVersion")
          $startInfo.ArgumentList.Add($PackageVersion)
        }
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        foreach ($name in @("GP_PACKAGE_VERSION", "GP_PACKAGE_VERSION_OVERRIDE")) {
          $startInfo.Environment.Remove($name) | Out-Null
        }
        foreach ($name in $CallerEnvironment.Keys) {
          $startInfo.Environment[$name] = [string]$CallerEnvironment[$name]
        }

        $process = [System.Diagnostics.Process]::Start($startInfo)
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
          throw "gnustep-packager $step exited with $($process.ExitCode):`n$($stdoutTask.Result)`n$($stderrTask.Result)"
        }
      }
    }
  }

  It "gives the build and stage commands the -PackageVersion override" {
    $recordPath = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-pipeline-env-" + [guid]::NewGuid().ToString("N") + ".txt")
    $manifestPath = New-GpVersionRecordingManifest -RecordPath $recordPath
    try {
      Invoke-GpRecordedSteps -ManifestPath $manifestPath -PackageVersion "9.9.9"
      $lines = @(Get-Content -Path $recordPath)
      Assert-GpEqual -Actual $lines.Count -Expected 2 -Message "Both steps should have run."
      Assert-GpEqual -Actual $lines[0] -Expected "build|9.9.9|9.9.9" -Message "The build command should see the override as GP_PACKAGE_VERSION and GP_PACKAGE_VERSION_OVERRIDE."
      Assert-GpEqual -Actual $lines[1] -Expected "stage|9.9.9|9.9.9" -Message "The stage command should see the override as GP_PACKAGE_VERSION and GP_PACKAGE_VERSION_OVERRIDE."
    } finally {
      Remove-Item -Force -ErrorAction SilentlyContinue $recordPath, $manifestPath
    }
  }

  It "gives the manifest's version without an override, whatever the caller's environment holds" {
    $recordPath = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-pipeline-env-" + [guid]::NewGuid().ToString("N") + ".txt")
    $manifestPath = New-GpVersionRecordingManifest -RecordPath $recordPath
    $manifestVersion = (Get-GpJsonFile -Path $script:baseManifestPath)["package"]["version"]
    try {
      # GP_PACKAGE_VERSION left over from an earlier run.
      Invoke-GpRecordedSteps -ManifestPath $manifestPath -CallerEnvironment @{ GP_PACKAGE_VERSION = "8.8.8" }
      $lines = @(Get-Content -Path $recordPath)
      Assert-GpEqual -Actual $lines[0] -Expected "build|$manifestVersion|" -Message "Without an override, the build command should see the manifest's version and no override."
      Assert-GpEqual -Actual $lines[1] -Expected "stage|$manifestVersion|" -Message "Without an override, the stage command should see the manifest's version and no override."
    } finally {
      Remove-Item -Force -ErrorAction SilentlyContinue $recordPath, $manifestPath
    }
  }

  It "passes an override given through GP_PACKAGE_VERSION_OVERRIDE on as it is" {
    $recordPath = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-pipeline-env-" + [guid]::NewGuid().ToString("N") + ".txt")
    $manifestPath = New-GpVersionRecordingManifest -RecordPath $recordPath
    try {
      Invoke-GpRecordedSteps -ManifestPath $manifestPath -CallerEnvironment @{ GP_PACKAGE_VERSION_OVERRIDE = "7.7.7" }
      $lines = @(Get-Content -Path $recordPath)
      Assert-GpEqual -Actual $lines[1] -Expected "stage|7.7.7|7.7.7" -Message "The environment's override should reach the stage command."
    } finally {
      Remove-Item -Force -ErrorAction SilentlyContinue $recordPath, $manifestPath
    }
  }
}
