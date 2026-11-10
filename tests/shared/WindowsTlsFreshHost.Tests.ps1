Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# The failure paths of scripts/ci/windows-tls-fresh-host.ps1: restoring the
# machine when a step throws, cleaning up a case that fails to start or wait,
# and which processes count as the script's own. No Windows APIs are touched;
# the commands they would call are mocked.
Describe "Windows fresh-host TLS helpers" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
    . (Join-Path $script:repoRoot "scripts\ci\windows-tls-fresh-host-helpers.ps1")

    function New-GpFakeProcess {
      param([int]$Id, [string]$Path, [datetime]$StartTime, [string]$Name = "app", [bool]$HasExited = $false)
      return [pscustomobject]@{ Id = $Id; Path = $Path; StartTime = $StartTime; ProcessName = $Name; HasExited = $HasExited; ExitCode = 0 }
    }
  }

  BeforeEach {
    $script:WorkRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-tls-fresh-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $script:WorkRoot | Out-Null
    $script:progressLog = Join-Path $script:WorkRoot "progress.log"
    $script:installRoot = Join-Path $script:WorkRoot "GpTlsFetch"
    New-Item -ItemType Directory -Force -Path $script:installRoot | Out-Null
    $script:installSince = [datetime]"2026-11-10T10:00:00"
    $script:launcherPath = Join-Path $script:installRoot "GpTlsFetch.exe"
    $script:restoreProblems = [System.Collections.Generic.List[string]]::new()
    $script:cleanup = [System.Collections.Generic.List[psobject]]::new()
    $script:removedCerts = [System.Collections.Generic.List[psobject]]::new()
    $script:caseNumber = 0
    Mock Start-Sleep { }
  }

  AfterEach {
    Remove-Item -Recurse -Force -LiteralPath $script:WorkRoot -ErrorAction SilentlyContinue
  }

  Context "restoring the machine" {
    It "still re-adds the certificates and restores every registry value when moving the bundle back throws" {
      $bundle = Join-Path $script:installRoot "ca-certificates.crt"
      $aside = "$bundle.aside"
      Set-Content -Path $aside -Value "x"
      $snaps = @(
        [pscustomobject]@{ Key = "HKLM:\A"; Name = "DontShowUI" },
        [pscustomobject]@{ Key = "HKLM:\A"; Name = "Disabled" },
        [pscustomobject]@{ Key = "HKLM:\B"; Name = "DisableRootAutoUpdate" }
      )
      Mock Move-Item { throw "injected: the bundle is locked" }
      Mock Restore-GpCertificates { }
      Mock Restore-GpRegSnapshot { }

      Invoke-GpRestoreSteps -Steps (New-GpRestoreSteps -Bundle $bundle -BundleAside $aside -RegSnapshots $snaps)

      Should -Invoke Move-Item -Times 1 -Exactly
      Should -Invoke Restore-GpCertificates -Times 1 -Exactly
      Should -Invoke Restore-GpRegSnapshot -Times 3 -Exactly
      foreach ($name in @("DontShowUI", "Disabled", "DisableRootAutoUpdate")) {
        Should -Invoke Restore-GpRegSnapshot -Times 1 -Exactly -ParameterFilter { $Snap.Name -eq $name }
      }
      $script:restoreProblems.Count | Should -Be 1
      $script:restoreProblems[0] | Should -Match "move the CA bundle back.*injected: the bundle is locked"
      (Get-Content -Raw $script:progressLog) | Should -Match "restore: registry HKLM:\\B\\DisableRootAutoUpdate done"
    }

    It "runs the registry steps after the certificate step throws" {
      Mock Restore-GpCertificates { throw "injected: store closed" }
      Mock Restore-GpRegSnapshot { }
      $snaps = @([pscustomobject]@{ Key = "HKLM:\A"; Name = "One" }, [pscustomobject]@{ Key = "HKLM:\A"; Name = "Two" })

      Invoke-GpRestoreSteps -Steps (New-GpRestoreSteps -Bundle "unused" -BundleAside (Join-Path $script:WorkRoot "absent") -RegSnapshots $snaps)

      Should -Invoke Restore-GpRegSnapshot -Times 2 -Exactly
      @($script:restoreProblems | Where-Object { $_ -match "re-add the removed certificates.*store closed" }).Count | Should -Be 1
    }
  }

  Context "a case that fails" {
    It "restores the environment, cleans up and rethrows when the launcher can't be started" {
      [Environment]::SetEnvironmentVariable("GS_TLS_CA_FILE", "before")
      Mock Start-Process { throw "injected: cannot start" }
      Mock Stop-GpCaseProcesses { }

      { Invoke-GpCase -Url "https://example.invalid/" -Environment @{ GS_TLS_CA_FILE = "during" } } | Should -Throw "*injected: cannot start*"

      Should -Invoke Stop-GpCaseProcesses -Times 1 -Exactly -ParameterFilter { $null -eq $Proc -and $Tag -eq "case1" }
      [Environment]::GetEnvironmentVariable("GS_TLS_CA_FILE") | Should -Be "before"
      [Environment]::GetEnvironmentVariable("GP_LAUNCHER_NONINTERACTIVE") | Should -BeNullOrEmpty
      [Environment]::SetEnvironmentVariable("GS_TLS_CA_FILE", $null)
    }

    It "cleans up the started process and keeps the original error when waiting throws" {
      $started = [datetime]"2026-11-10T10:05:00"
      $fake = [pscustomobject]@{ Id = 4242; StartTime = $started }
      $fake | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($ms) throw "injected: wait failed" }
      $fake | Add-Member -MemberType NoteProperty -Name HasExited -Value $false
      Mock Start-Process { $fake }
      Mock Stop-GpCaseProcesses { }

      { Invoke-GpCase -Url "https://example.invalid/" } | Should -Throw "*injected: wait failed*"

      Should -Invoke Stop-GpCaseProcesses -Times 1 -Exactly -ParameterFilter { $Proc.Id -eq 4242 -and $ProcStart -eq $started }
    }

    It "records a cleanup failure without throwing and without a process" {
      Mock Get-GpOwnedProcesses { throw "injected: process list failed" }

      { Stop-GpCaseProcesses -Proc $null -ProcStart $null -Tag "caseX" } | Should -Not -Throw

      $script:cleanup.Count | Should -Be 1
      $script:cleanup[0].CleanupErrors | Should -Match "injected: process list failed"
    }
  }

  Context "which processes are the script's own" {
    It "counts only paths below the install root, not a sibling with the same prefix" {
      Test-GpPathUnderRoot -Path (Join-Path $script:installRoot "app/gp-tls-fetch.exe") -Root $script:installRoot | Should -BeTrue
      Test-GpPathUnderRoot -Path (Join-Path $script:installRoot "runtime/System/Tools/gdnc.exe") -Root $script:installRoot | Should -BeTrue
      Test-GpPathUnderRoot -Path ($script:installRoot + "Old/gp-tls-fetch.exe") -Root $script:installRoot | Should -BeFalse
      Test-GpPathUnderRoot -Path ($script:installRoot + ".bak") -Root $script:installRoot | Should -BeFalse
      Test-GpPathUnderRoot -Path $script:installRoot -Root $script:installRoot | Should -BeFalse
      Test-GpPathUnderRoot -Path $null -Root $script:installRoot | Should -BeFalse
    }

    It "excludes siblings and processes that started before the install" {
      $inRoot = Join-Path $script:installRoot "runtime/System/Tools/gdnc.exe"
      $procs = @(
        (New-GpFakeProcess -Id 1 -Path $inRoot -StartTime ([datetime]"2026-11-10T10:01:00") -Name "gdnc"),
        (New-GpFakeProcess -Id 2 -Path ($script:installRoot + "Old/gdnc.exe") -StartTime ([datetime]"2026-11-10T10:01:00") -Name "gdnc"),
        (New-GpFakeProcess -Id 3 -Path $inRoot -StartTime ([datetime]"2026-11-10T09:00:00") -Name "gdnc"),
        (New-GpFakeProcess -Id 4 -Path $null -StartTime ([datetime]"2026-11-10T10:01:00") -Name "System")
      )
      Mock Get-Process { $procs }

      $owned = Get-GpOwnedProcesses

      @($owned | ForEach-Object { $_.Id }) | Should -Be @(1)
    }

    It "doesn't kill a PID whose start time no longer matches the case's process" {
      $caseStart = [datetime]"2026-11-10T10:05:00"
      $proc = New-GpFakeProcess -Id 4242 -Path $script:launcherPath -StartTime $caseStart
      Mock Get-Process -ParameterFilter { $Id -eq 4242 } { New-GpFakeProcess -Id 4242 -Path "C:\elsewhere\other.exe" -StartTime ([datetime]"2026-11-10T11:00:00") -Name "other" }
      Mock Get-GpOwnedProcesses { ,@() }
      Mock Get-Process -ParameterFilter { $Name } { }
      Mock Invoke-GpTaskKill { [pscustomobject]@{ ExitCode = 0; Output = "" } }

      Stop-GpCaseProcesses -Proc $proc -ProcStart $caseStart -Tag "case1"

      Should -Invoke Invoke-GpTaskKill -Times 0 -Exactly
      $script:cleanup[0].CleanupErrors | Should -Match "no longer the case's process"
    }

    It "kills the case's own process tree when PID and start time match" {
      $caseStart = [datetime]"2026-11-10T10:05:00"
      $proc = New-GpFakeProcess -Id 4242 -Path $script:launcherPath -StartTime $caseStart
      Mock Get-Process -ParameterFilter { $Id -eq 4242 } { New-GpFakeProcess -Id 4242 -Path $script:launcherPath -StartTime $caseStart }
      Mock Get-GpOwnedProcesses { ,@() }
      Mock Get-Process -ParameterFilter { $Name } { }
      Mock Invoke-GpTaskKill { [pscustomobject]@{ ExitCode = 0; Output = "" } }

      Stop-GpCaseProcesses -Proc $proc -ProcStart $caseStart -Tag "case1"

      Should -Invoke Invoke-GpTaskKill -Times 1 -Exactly -ParameterFilter { $ProcessId -eq 4242 }
      $script:cleanup[0].CleanupErrors.Count | Should -Be 0
    }

    It "reports an owned process that survives in the final check" {
      Mock Get-GpOwnedProcesses { ,@((New-GpFakeProcess -Id 7 -Path (Join-Path $script:installRoot "runtime/System/Tools/gdnc.exe") -StartTime ([datetime]"2026-11-10T10:01:00") -Name "gdnc")) }

      $left = Get-GpResidualOwned

      @($left).Count | Should -Be 1
      $left[0] | Should -Match "gdnc\[7\]"
    }
  }
}
