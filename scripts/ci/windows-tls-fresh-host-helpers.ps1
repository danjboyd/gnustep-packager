# Helpers for windows-tls-fresh-host.ps1, dot-sourced by it and by
# tests/shared/WindowsTlsFreshHost.Tests.ps1. They read these script-scope
# values, which the caller sets: WorkRoot, progressLog, installRoot,
# installSince (when the install started) and launcherPath.

function Write-GpStep {
  param([string]$Message)
  $line = "[{0:HH:mm:ss}] {1}" -f (Get-Date), $Message
  Write-Host $line
  if ($script:progressLog) { Add-Content -Path $script:progressLog -Value $line }
}

# --- Certificate helpers ----------------------------------------------------

function Get-GpPemThumbprints {
  param([string]$Path)
  $text = Get-Content -Raw $Path
  $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($m in [regex]::Matches($text, "-----BEGIN CERTIFICATE-----(.+?)-----END CERTIFICATE-----", "Singleline")) {
    $der = [Convert]::FromBase64String(($m.Groups[1].Value -replace "\s", ""))
    $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($der)
    $set.Add($cert.Thumbprint) | Out-Null
  }
  return ,$set
}

# The root the server's chain ends in, as this machine builds it now.
function Get-GpChainRoot {
  param([string]$Url)
  $uri = [Uri]$Url
  $client = [System.Net.Sockets.TcpClient]::new()
  try {
    if (-not $client.ConnectAsync($uri.Host, 443).Wait(20000)) { throw "connect timed out" }
    $client.ReceiveTimeout = 20000
    $client.SendTimeout = 20000
    # No validation callback: a PowerShell script block can't run on the thread
    # .NET calls it from. The probe runs before the root is removed, so the
    # default validation passes. The socket timeouts above bound the handshake.
    $ssl = [System.Net.Security.SslStream]::new($client.GetStream(), $false)
    $ssl.AuthenticateAsClient($uri.Host)
    $leaf = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($ssl.RemoteCertificate)
    $chain = [System.Security.Cryptography.X509Certificates.X509Chain]::new()
    $chain.ChainPolicy.RevocationMode = "NoCheck"
    $chain.ChainPolicy.UrlRetrievalTimeout = [TimeSpan]::FromSeconds(15)
    $null = $chain.Build($leaf)
    $elements = @($chain.ChainElements)
    return $elements[$elements.Count - 1].Certificate
  } finally {
    $client.Dispose()
  }
}

# Everything Remove-GpRoot took out, so Restore-GpCertificates can put it back.
# Each was present before (that's why it was removed), so putting it back is
# the prior state. The runner agent itself may talk to GitHub through this
# store, so it must not be left changed.
$script:removedCerts = [System.Collections.Generic.List[psobject]]::new()
function Restore-GpCertificates {
  foreach ($r in $script:removedCerts) {
    try {
      $store = [System.Security.Cryptography.X509Certificates.X509Store]::new($r.Store, $r.Location)
      $store.Open("ReadWrite")
      $store.Add($r.Certificate)
      $store.Close()
    } catch {
      $script:restoreProblems.Add("could not re-add $($r.Certificate.Thumbprint) to $($r.Location)\$($r.Store): $($_.Exception.Message)") | Out-Null
    }
  }
}
function Test-GpCertificatesRestored {
  $out = @()
  foreach ($r in $script:removedCerts) {
    $store = [System.Security.Cryptography.X509Certificates.X509Store]::new($r.Store, $r.Location)
    $store.Open("ReadOnly")
    $present = @($store.Certificates.Find("FindByThumbprint", $r.Certificate.Thumbprint, $false)).Count -gt 0
    $store.Close()
    $out += [pscustomobject]@{ Store = "$($r.Location)\$($r.Store)"; Thumbprint = $r.Certificate.Thumbprint; Present = $present }
  }
  return ,$out
}

# Registry values this script changes, captured before the change and put
# back exactly: the key's and the value's presence, the value's kind and data.
function Get-GpRegSnapshot {
  param([string]$Key, [string]$Name)
  $snap = [ordered]@{ Key = $Key; Name = $Name; KeyExisted = (Test-Path $Key); ValueExisted = $false; Kind = $null; Data = $null }
  if ($snap.KeyExisted) {
    $k = Get-Item -Path $Key
    if ($k.GetValueNames() -contains $Name) {
      $snap.ValueExisted = $true
      $snap.Kind = $k.GetValueKind($Name).ToString()
      $snap.Data = $k.GetValue($Name, $null, "DoNotExpandEnvironmentNames")
    }
  }
  return [pscustomobject]$snap
}
function Restore-GpRegSnapshot {
  param($Snap)
  try {
    if ($Snap.ValueExisted) {
      Set-ItemProperty -Path $Snap.Key -Name $Snap.Name -Value $Snap.Data -Type $Snap.Kind
    } elseif (Test-Path $Snap.Key) {
      Remove-ItemProperty -Path $Snap.Key -Name $Snap.Name -ErrorAction SilentlyContinue
      # A key this script created goes too, if nothing else was put in it.
      if (-not $Snap.KeyExisted) {
        $k = Get-Item -Path $Snap.Key
        if ($k.ValueCount -eq 0 -and $k.SubKeyCount -eq 0) { Remove-Item -Path $Snap.Key }
      }
    }
  } catch {
    $script:restoreProblems.Add("could not restore $($Snap.Key)\$($Snap.Name): $($_.Exception.Message)") | Out-Null
  }
}
function Test-GpRegRestored {
  param($Snap)
  $now = Get-GpRegSnapshot -Key $Snap.Key -Name $Snap.Name
  $same = ($now.ValueExisted -eq $Snap.ValueExisted) -and ($now.Kind -eq $Snap.Kind) -and ("$($now.Data)" -eq "$($Snap.Data)")
  if (-not $Snap.KeyExisted -and $Snap.ValueExisted -eq $false) { $same = $same -and -not ($now.KeyExisted -and @(Get-Item $Snap.Key).ValueCount -eq 0) }
  return [pscustomobject]@{ Key = $Snap.Key; Name = $Snap.Name; Before = "existed=$($Snap.ValueExisted) kind=$($Snap.Kind) data=$($Snap.Data) keyExisted=$($Snap.KeyExisted)"; After = "existed=$($now.ValueExisted) kind=$($now.Kind) data=$($now.Data) keyExisted=$($now.KeyExisted)"; Restored = $same }
}
$script:restoreProblems = [System.Collections.Generic.List[string]]::new()
$script:cleanup = [System.Collections.Generic.List[psobject]]::new()

function Remove-GpRoot {
  param([string]$Thumbprint)
  $removed = @()
  foreach ($loc in @(@("Root", "LocalMachine"), @("AuthRoot", "LocalMachine"), @("Root", "CurrentUser"))) {
    $storeName = $loc[0]
    $store = [System.Security.Cryptography.X509Certificates.X509Store]::new($storeName, $loc[1])
    $store.Open("ReadWrite")
    foreach ($c in @($store.Certificates.Find("FindByThumbprint", $Thumbprint, $false))) {
      $store.Remove($c)
      $removed += "$($loc[1])\$storeName"
      $script:removedCerts.Add([pscustomobject]@{ Store = $storeName; Location = $loc[1]; Certificate = $c }) | Out-Null
    }
    $store.Close()
  }
  return $removed
}

function Test-GpHostFetch {
  param([string]$Url)
  try {
    $null = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 30
    return "PASS"
  } catch {
    return "FAIL $($_.Exception.Message)"
  }
}

# --- Owned processes ----------------------------------------------------------

# True when Path is inside Root: a whole path component below it, so a sibling
# such as "<Root>Old\x.exe" doesn't count. Windows paths compare without case.
function Test-GpPathUnderRoot {
  param([string]$Path, [string]$Root)
  if ([string]::IsNullOrEmpty($Path) -or [string]::IsNullOrEmpty($Root)) { return $false }
  $sep = [System.IO.Path]::DirectorySeparatorChar
  $full = [System.IO.Path]::GetFullPath($Path)
  $base = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + $sep
  return $full.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-GpProcessStart {
  param($Process)
  if ($null -eq $Process) { return $null }
  try { return $Process.StartTime } catch { return $null }
}

# Ours: running from the install root, and started after the install began.
# A helper an earlier case left (gdnc) is still ours; a process from before
# the install isn't, whatever its path.
function Get-GpOwnedProcesses {
  $found = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $start = Get-GpProcessStart -Process $_
    (Test-GpPathUnderRoot -Path $_.Path -Root $script:installRoot) -and $null -ne $start -and $start -ge $script:installSince
  })
  return ,$found
}

function Invoke-GpTaskKill {
  param([int]$ProcessId)
  $out = & taskkill.exe /T /F /PID $ProcessId 2>&1
  return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = [string]::Join(" ", @($out)) }
}

# Ends what a case started and records what is left. It never throws, so a
# caller's own error isn't replaced by a cleanup error.
function Stop-GpCaseProcesses {
  param($Proc, $ProcStart, [string]$Tag)
  $errors = [System.Collections.Generic.List[string]]::new()
  $owned = @()
  $other = @()
  try {
    if ($null -ne $Proc) {
      $exited = $true
      try { $exited = [bool]$Proc.HasExited } catch { $errors.Add("could not read the exit state of $($Proc.Id): $($_.Exception.Message)") | Out-Null; $exited = $false }
      if (-not $exited) {
        # Only the process this case started: same PID and same start time.
        $current = Get-Process -Id $Proc.Id -ErrorAction SilentlyContinue
        $currentStart = Get-GpProcessStart -Process $current
        if ($null -ne $current -and $null -ne $ProcStart -and $currentStart -eq $ProcStart) {
          $kill = Invoke-GpTaskKill -ProcessId $Proc.Id
          if ($kill.ExitCode -ne 0 -and $null -ne (Get-Process -Id $Proc.Id -ErrorAction SilentlyContinue)) { $errors.Add("taskkill $($Proc.Id): $($kill.Output)") | Out-Null }
        } elseif ($null -ne $current) {
          $errors.Add("PID $($Proc.Id) is no longer the case's process (start time differs), so it wasn't killed") | Out-Null
        }
      }
    }
    foreach ($p in (Get-GpOwnedProcesses)) {
      $start = Get-GpProcessStart -Process $p
      $again = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
      if ($null -eq $again -or (Get-GpProcessStart -Process $again) -ne $start) { continue }
      try { Stop-Process -Id $p.Id -Force -ErrorAction Stop }
      catch { if ($null -ne (Get-Process -Id $p.Id -ErrorAction SilentlyContinue)) { $errors.Add("stop $($p.ProcessName)[$($p.Id)]: $($_.Exception.Message)") | Out-Null } }
    }
    Start-Sleep -Milliseconds 500
    $owned = @((Get-GpOwnedProcesses) | ForEach-Object { "$($_.ProcessName)[$($_.Id)] $($_.Path)" })
    $other = @(Get-Process -Name gdnc, gdomap, gpbs -ErrorAction SilentlyContinue | Where-Object { -not (Test-GpPathUnderRoot -Path $_.Path -Root $script:installRoot) } | ForEach-Object { "$($_.ProcessName)[$($_.Id)] $($_.Path)" })
  } catch {
    $errors.Add("cleanup failed: $($_.Exception.Message)") | Out-Null
  }
  $script:cleanup.Add([pscustomobject]@{ Case = $Tag; OwnedLeft = $owned; CleanupErrors = @($errors); UnownedHelpersSeen = $other }) | Out-Null
  try {
    $msg = if ($owned.Count -eq 0) { "  cleanup ${Tag}: nothing left from the install root" } else { "  cleanup ${Tag}: OWNED PROCESS LEFT " + [string]::Join(", ", $owned) }
    if ($errors.Count -gt 0) { $msg += "; errors: " + [string]::Join("; ", $errors) }
    if ($other.Count -gt 0) { $msg += "; (observed, not ours, left alone: " + [string]::Join(", ", $other) + ")" }
    Write-GpStep $msg
  } catch { }
}

function Get-GpResidualOwned {
  try { return ,@((Get-GpOwnedProcesses) | ForEach-Object { "$($_.ProcessName)[$($_.Id)] $($_.Path)" }) }
  catch { return ,@("unknown: the final check failed: $($_.Exception.Message)") }
}

# --- Cases --------------------------------------------------------------------

# Runs the installed launcher (or Executable) with the tool's arguments and
# returns its line. Output goes to files, so no child holds the step's pipes.
# Whatever happens, the environment is put back and the case's processes are
# ended in the finally; an error from starting or waiting still propagates.
$script:caseNumber = 0
function Invoke-GpCase {
  param([string]$Url, [hashtable]$Environment = @{}, [string]$Executable = $script:launcherPath)
  $script:caseNumber++
  $tag = "case{0}" -f $script:caseNumber
  Write-GpStep ("{0} start: {1} via {2} env={3}" -f $tag, $Url, (Split-Path -Leaf $Executable), [string]::Join(",", @($Environment.Keys)))
  $resultFile = Join-Path $script:WorkRoot "result-$tag.txt"
  $stdout = Join-Path $script:WorkRoot "result-$tag.stdout.txt"
  $stderr = Join-Path $script:WorkRoot "result-$tag.stderr.txt"
  # The launcher starts the app and exits without waiting; its own errors go
  # to this file.
  $launcherLog = Join-Path $script:WorkRoot "result-$tag.launcher.txt"
  $Environment = @{} + $Environment
  $Environment["GP_LAUNCHER_ERROR_LOG"] = $launcherLog
  $Environment["GP_LAUNCHER_NONINTERACTIVE"] = "1"
  $saved = @{}
  $applied = [System.Collections.Generic.List[string]]::new()
  $proc = $null
  $procStart = $null
  try {
    foreach ($k in $Environment.Keys) {
      $saved[$k] = [Environment]::GetEnvironmentVariable($k)
      $applied.Add($k) | Out-Null
      [Environment]::SetEnvironmentVariable($k, $Environment[$k])
    }
    $proc = Start-Process -FilePath $Executable -ArgumentList @($Url, "`"$resultFile`"") -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $procStart = Get-GpProcessStart -Process $proc
    $deadline = (Get-Date).AddSeconds(120)
    # WaitForExit, not HasExited: an exception from a property read inside a
    # loop condition reads as false, so a failed wait would spin to the deadline.
    while (-not (Test-Path $resultFile) -and (Get-Date) -lt $deadline) {
      if ($proc.WaitForExit(500)) { break }
    }
    # The launcher may exit before its child writes the file.
    while (-not (Test-Path $resultFile) -and (Get-Date) -lt $deadline -and (Get-GpOwnedProcesses).Count -gt 0) { Start-Sleep -Milliseconds 500 }
    Start-Sleep -Milliseconds 500
  } finally {
    foreach ($k in $applied) {
      try { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
      catch { $script:restoreProblems.Add("could not restore the environment variable ${k}: $($_.Exception.Message)") | Out-Null }
    }
    Stop-GpCaseProcesses -Proc $proc -ProcStart $procStart -Tag $tag
  }
  $state = "still running at 120 s"
  try { if ($proc.HasExited) { $state = "$(Split-Path -Leaf $Executable) exit $($proc.ExitCode)" } } catch { $state = "exit state unknown" }
  if (Test-Path $resultFile) { return ([string](Get-Content -Raw $resultFile)).Trim() }
  $err = ""
  foreach ($f in @($stderr, $launcherLog)) {
    if (Test-Path $f) { $err += " " + ([string](Get-Content -Raw $f) -replace "\s+", " ") }
  }
  $err = $err.Trim()
  if ($err.Length -gt 300) { $err = $err.Substring(0, 300) }
  return "FAIL no result ($state; stderr: $err)"
}

# --- Restoring the machine ----------------------------------------------------

# The restore steps, in order: the CA bundle back in place, every removed
# certificate, then each registry value. Plain records, so the steps can be
# listed, run and tested without closures.
function New-GpRestoreSteps {
  param([string]$Bundle, [string]$BundleAside, [object[]]$RegSnapshots)
  $steps = [System.Collections.Generic.List[psobject]]::new()
  $steps.Add([pscustomobject]@{ Name = "move the CA bundle back"; Kind = "bundle"; Bundle = $Bundle; BundleAside = $BundleAside; Snap = $null }) | Out-Null
  $steps.Add([pscustomobject]@{ Name = "re-add the removed certificates"; Kind = "certificates"; Bundle = $null; BundleAside = $null; Snap = $null }) | Out-Null
  foreach ($snap in @($RegSnapshots)) {
    $steps.Add([pscustomobject]@{ Name = "registry $($snap.Key)\$($snap.Name)"; Kind = "registry"; Bundle = $null; BundleAside = $null; Snap = $snap }) | Out-Null
  }
  return ,$steps
}

# Runs every step even when one throws, and records each failure.
function Invoke-GpRestoreSteps {
  param([object[]]$Steps)
  foreach ($step in @($Steps)) {
    try {
      switch ($step.Kind) {
        "bundle" { if (Test-Path -LiteralPath $step.BundleAside) { Move-Item -Force -LiteralPath $step.BundleAside -Destination $step.Bundle -ErrorAction Stop } }
        "certificates" { Restore-GpCertificates }
        "registry" { Restore-GpRegSnapshot -Snap $step.Snap }
        default { throw "unknown restore step kind '$($step.Kind)'" }
      }
      Write-GpStep "restore: $($step.Name) done"
    } catch {
      $script:restoreProblems.Add("restore step '$($step.Name)' failed: $($_.Exception.Message)") | Out-Null
      try { Write-GpStep "restore: $($step.Name) FAILED: $($_.Exception.Message)" } catch { }
    }
  }
}
