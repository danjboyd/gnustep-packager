<#
.SYNOPSIS
Checks that an MSI built with gnustep-cli-new v0.1.5 fetches https on a Windows
host whose certificate store lacks the server's root. Disposable hosts only.

.DESCRIPTION
Follows docs/windows-tls-fresh-host-check.md. It changes the machine's trust
store, so run it only on a throwaway runner or VM.

1. Packages tests/fixtures/windows-tls-fetch (a Foundation tool that fetches one
   URL) as an MSI, with gnustep-base's GSTLS resources staged, and installs it.
2. Stops on-demand root updates and, for each candidate URL in turn, finds the
   root its chain ends in, checks that root is in the staged bundle, and
   removes it from the machine's Root and AuthRoot stores and the user's Root.
3. Runs the cases through the installed launcher:
     control  bundle moved away                         -> must FAIL
     bundled  bundle in place                           -> must PASS
     envfile  bundle moved away, GS_TLS_CA_FILE = copy  -> must PASS
     olderlist ObjcMarkdown 0.2.6's list in its place    -> FAIL if the root
               isn't in that list (recorded either way)
   A URL whose control case passes isn't isolating the root (another trust path
   exists), so the script moves on to the next candidate.

4. Puts the machine back: re-adds every removed certificate, returns the
   registry values it changed (Windows Error Reporting, DisableRootAutoUpdate)
   to exactly their prior presence, kind and data, and checks both.

Before the cases, a sanity fetch with the store intact must pass. After each
case it ends only processes running from the install root (the app, and the
bundled gdnc), and records any that survive. gdnc/gdomap/gpbs running from
elsewhere are listed but left alone.

Writes results.json (cases, skipped checks, restoration, cleanup) and exits 1
unless one candidate gave a failing control with passing bundled and envfile
cases, the restoration checks out, and no owned process was left.
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$ToolPath,
  [Parameter(Mandatory = $true)]
  [string]$ToolchainClangRoot,
  [string]$WorkRoot = (Join-Path ([System.IO.Path]::GetTempPath()) "gp-tls-fresh-host"),
  [string[]]$CandidateUrls = @(
    "https://letsencrypt.org/",
    "https://www.google.com/",
    "https://github.com/",
    "https://www.digicert.com/",
    "https://www.wikipedia.org/"
  ),
  [string]$OlderListUrl = "https://github.com/danjboyd/ObjcMarkdown/releases/download/v0.2.6/ObjcMarkdown-0.2.6-win64-portable.zip"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))

if (Test-Path $WorkRoot) { Remove-Item -Recurse -Force $WorkRoot }
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null
$progressLog = Join-Path $WorkRoot "progress.log"
function Write-GpStep {
  param([string]$Message)
  $line = "[{0:HH:mm:ss}] {1}" -f (Get-Date), $Message
  Write-Host $line
  Add-Content -Path $progressLog -Value $line
}

# --- 1. Stage, package and install ------------------------------------------

$projectRoot = Join-Path $WorkRoot "project"
$stageRoot = Join-Path $projectRoot "dist\stage"
New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot "app"), (Join-Path $stageRoot "runtime\lib"), (Join-Path $stageRoot "metadata\licenses") | Out-Null
Copy-Item -Force $ToolPath (Join-Path $stageRoot "app\gp-tls-fetch.exe")
Copy-Item -Recurse -Force (Join-Path $ToolchainClangRoot "lib\GNUstep") (Join-Path $stageRoot "runtime\lib\GNUstep")
# gnustep-base goes in runtime\bin, as in a real Windows stage: it finds its
# resources (GSTLS among them) at ..\lib\GNUstep relative to its DLL. The MSI
# backend's closure analysis copies the remaining DLLs from runtimeSearchRoots.
New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot "runtime\bin") | Out-Null
$baseDll = Get-ChildItem -Path (Join-Path $ToolchainClangRoot "bin") -Filter "gnustep-base*.dll" | Select-Object -First 1
if ($null -eq $baseDll) { throw "No gnustep-base DLL in $ToolchainClangRoot\bin" }
Copy-Item -Force $baseDll.FullName (Join-Path $stageRoot "runtime\bin")
Write-GpStep "staged $($baseDll.Name)"
# gnustep-base starts gdnc when the URL loading system first posts a
# distributed notification, and throws "Unable to find the gdnc tool" without
# it. Stage it as a real Windows package does (runtime\System\Tools), with a
# GNUstep.conf next to the DLL that points the tools and libraries into the
# package. The closure analysis copies gdnc's DLLs as it does the app's.
$systemTools = Join-Path $stageRoot "runtime\System\Tools"
New-Item -ItemType Directory -Force -Path $systemTools | Out-Null
$gdnc = Join-Path $ToolchainClangRoot "bin\gdnc.exe"
if (-not (Test-Path $gdnc)) { throw "No gdnc.exe in $ToolchainClangRoot\bin" }
Copy-Item -Force $gdnc $systemTools
Set-Content -Path (Join-Path $stageRoot "runtime\bin\GNUstep.conf") -Encoding ascii -Value @(
  "GNUSTEP_USER_CONFIG_FILE=",
  "GNUSTEP_SYSTEM_ROOT=../System",
  "GNUSTEP_LOCAL_ROOT=../System",
  "GNUSTEP_NETWORK_ROOT=../System",
  "GNUSTEP_SYSTEM_LIBRARY=../lib/GNUstep",
  "GNUSTEP_NETWORK_LIBRARY=../lib/GNUstep",
  "GNUSTEP_LOCAL_LIBRARY=../lib/GNUstep",
  "GNUSTEP_SYSTEM_TOOLS=../System/Tools",
  "GNUSTEP_NETWORK_TOOLS=../System/Tools",
  "GNUSTEP_LOCAL_TOOLS=../System/Tools"
)
Write-GpStep "staged gdnc.exe and runtime\bin\GNUstep.conf"
Set-Content -Path (Join-Path $stageRoot "metadata\licenses\gp-tls-fetch.txt") -Value "gp-tls-fetch test fixture. GNUstep libraries: LGPL-2.1-or-later."

$stagedBundle = Get-ChildItem -Path (Join-Path $stageRoot "runtime\lib\GNUstep") -Recurse -Filter "ca-certificates.crt" |
  Where-Object { $_.Directory.Name -eq "GSTLS" } | Select-Object -First 1
if ($null -eq $stagedBundle) { throw "The toolchain has no GSTLS/ca-certificates.crt under $ToolchainClangRoot\lib\GNUstep" }
Write-GpStep "staged bundle: $($stagedBundle.FullName)"

# validation.smoke.enabled is false, and only that. The MSI backend's smoke
# launch expects a GUI app that keeps running, and this tool fetches once and
# exits. MSI validation still installs the package, checks the installed
# layout and uninstalls it. Skipping the launch isn't a pass: the cases below
# are this job's check.
$noop = "Write-Host 'prebuilt by windows-tls-fresh-host.ps1'"
$manifest = [ordered]@{
  schemaVersion = 1
  package = [ordered]@{ id = "org.gnustep-packager.TlsFetchCheck"; name = "GpTlsFetch"; displayName = "GP TLS Fetch Check"; version = "0.1.0"; manufacturer = "gnustep-packager tests"; summary = "Fetches one https URL (fresh-host TLS check)."; license = "LGPL-2.1-or-later" }
  pipeline = [ordered]@{ workingDirectory = "."; shell = [ordered]@{ kind = "pwsh"; bootstrapCommands = @(); environment = [ordered]@{} }; build = [ordered]@{ command = $noop }; stage = [ordered]@{ command = $noop; outputRoot = "dist/stage" } }
  payload = [ordered]@{ layoutVersion = 1; stageRoot = "dist/stage"; appRoot = "app"; runtimeRoot = "runtime"; metadataRoot = "metadata" }
  launch = [ordered]@{ entryRelativePath = "app/gp-tls-fetch.exe"; workingDirectory = "."; arguments = @(); pathPrepend = @("runtime/bin"); env = [ordered]@{} }
  outputs = [ordered]@{ root = "dist"; packageRoot = "dist/packages"; logRoot = "dist/logs"; tempRoot = "dist/tmp"; validationRoot = "dist/validation" }
  validation = [ordered]@{ fetchesHttps = $true; smoke = [ordered]@{ enabled = $false; kind = "staged-layout"; requiredPaths = @("app/gp-tls-fetch.exe", "runtime/System/Tools/gdnc.exe", "runtime/bin/GNUstep.conf"); timeoutSeconds = 30 }; logs = [ordered]@{ retainOnSuccess = $true } }
  compliance = [ordered]@{ runtimeNotices = @([ordered]@{ name = "gp-tls-fetch"; license = "LGPL-2.1-or-later"; source = "tests/fixtures/windows-tls-fetch"; stageRelativePath = "metadata/licenses/gp-tls-fetch.txt" }) }
  backends = [ordered]@{
    msi = [ordered]@{ enabled = $true; upgradeCode = "5b0e6f0e-3a43-4d55-9c55-7d2f1a6e0c11"; installScope = "perUser"; productName = "GP TLS Fetch Check"; installDirectoryName = "GpTlsFetch"; launcherFileName = "GpTlsFetch.exe"; runtimeSearchRoots = @((Join-Path $ToolchainClangRoot "bin")) }
  }
}
$manifestPath = Join-Path $projectRoot "package.manifest.json"
$manifest | ConvertTo-Json -Depth 30 | Set-Content -Path $manifestPath -Encoding utf8

Write-GpStep "packaging"
& (Join-Path $repoRoot "scripts\run-packaging-pipeline.ps1") -Manifest $manifestPath -Backend msi
Write-GpStep "packaging finished"
if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { throw "packaging failed" }
$msi = Get-ChildItem (Join-Path $projectRoot "dist\packages") -Filter "*.msi" | Select-Object -First 1
if ($null -eq $msi) { throw "no MSI was built" }

$installLog = Join-Path $WorkRoot "install.log"
Write-GpStep "installing $($msi.Name)"
$p = Start-Process msiexec.exe -ArgumentList @("/i", "`"$($msi.FullName)`"", "/qn", "/l*v", "`"$installLog`"") -PassThru
if (-not $p.WaitForExit(300000)) { throw "msiexec did not finish within 5 minutes, see $installLog" }
if ($p.ExitCode -ne 0) { throw "installing the MSI failed: msiexec $($p.ExitCode), see $installLog" }
$launcher = Get-Item -LiteralPath (Join-Path $env:LOCALAPPDATA "GpTlsFetch\GpTlsFetch.exe") -ErrorAction SilentlyContinue
if ($null -eq $launcher) { throw "the installed launcher GpTlsFetch.exe was not found" }
$installRoot = $launcher.Directory.FullName
$bundle = Get-ChildItem -Path $installRoot -Recurse -Filter "ca-certificates.crt" | Where-Object { $_.Directory.Name -eq "GSTLS" } | Select-Object -First 1
if ($null -eq $bundle) { throw "the installed package has no GSTLS/ca-certificates.crt" }
Write-GpStep "installed: $installRoot; bundle: $($bundle.FullName)"

$bundleCopy = Join-Path $WorkRoot "ca-certificates.copy.crt"
Copy-Item -Force $bundle.FullName $bundleCopy
$bundleAside = "$($bundle.FullName).aside"

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

# Runs the installed launcher with the tool's arguments and returns its line.
# Its output goes to files, so no child holds the step's console pipes open,
# and a case that writes no result reports the exit code and stderr instead.
$caseNumber = 0
# Ends only what this script started: the case's process tree, and anything
# still running from the install root (the app, and gdnc from
# runtime\System\Tools). Then checks nothing owned is left, and lists helpers
# running from elsewhere without touching them.
$script:cleanup = [System.Collections.Generic.List[psobject]]::new()
function Get-GpOwnedProcesses {
  return ,@(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($installRoot, [System.StringComparison]::OrdinalIgnoreCase) })
}
function Stop-GpCaseProcesses {
  param($Proc, [string]$Tag)
  $errors = @()
  if ($Proc -and -not $Proc.HasExited) {
    $out = & taskkill.exe /T /F /PID $Proc.Id 2>&1
    # A tree that ended on its own between the check and the kill isn't an error.
    if ($LASTEXITCODE -ne 0 -and -not $Proc.HasExited) { $errors += "taskkill $($Proc.Id): $out" }
  }
  foreach ($p in (Get-GpOwnedProcesses)) {
    try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { $errors += "stop $($p.ProcessName)[$($p.Id)]: $($_.Exception.Message)" }
  }
  Start-Sleep -Milliseconds 500
  $owned = @((Get-GpOwnedProcesses) | ForEach-Object { "$($_.ProcessName)[$($_.Id)] $($_.Path)" })
  $other = @(Get-Process -Name gdnc, gdomap, gpbs -ErrorAction SilentlyContinue | Where-Object { -not ($_.Path -and $_.Path.StartsWith($installRoot, [System.StringComparison]::OrdinalIgnoreCase)) } | ForEach-Object { "$($_.ProcessName)[$($_.Id)] $($_.Path)" })
  $script:cleanup.Add([pscustomobject]@{ Case = $Tag; OwnedLeft = $owned; CleanupErrors = $errors; UnownedHelpersSeen = $other }) | Out-Null
  $msg = if ($owned.Count -eq 0) { "  cleanup ${Tag}: nothing left from the install root" } else { "  cleanup ${Tag}: OWNED PROCESS LEFT " + [string]::Join(", ", $owned) }
  if ($errors.Count -gt 0) { $msg += "; errors: " + [string]::Join("; ", $errors) }
  if ($other.Count -gt 0) { $msg += "; (observed, not ours, left alone: " + [string]::Join(", ", $other) + ")" }
  Write-GpStep $msg
}
function Invoke-GpCase {
  param([string]$Url, [hashtable]$Environment = @{}, [string]$Executable = $launcher.FullName)
  $script:caseNumber++
  $tag = "case{0}" -f $script:caseNumber
  Write-GpStep ("{0} start: {1} via {2} env={3}" -f $tag, $Url, (Split-Path -Leaf $Executable), [string]::Join(",", @($Environment.Keys)))
  $resultFile = Join-Path $WorkRoot "result-$tag.txt"
  $stdout = Join-Path $WorkRoot "result-$tag.stdout.txt"
  $stderr = Join-Path $WorkRoot "result-$tag.stderr.txt"
  # The launcher starts the app and exits without waiting; its own errors go
  # to this file.
  $launcherLog = Join-Path $WorkRoot "result-$tag.launcher.txt"
  $Environment = @{} + $Environment
  $Environment["GP_LAUNCHER_ERROR_LOG"] = $launcherLog
  $Environment["GP_LAUNCHER_NONINTERACTIVE"] = "1"
  $saved = @{}
  foreach ($k in $Environment.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Environment[$k]) }
  $proc = $null
  try {
    $proc = Start-Process -FilePath $Executable -ArgumentList @($Url, "`"$resultFile`"") -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $deadline = (Get-Date).AddSeconds(120)
    while (-not (Test-Path $resultFile) -and -not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
    # The launcher may exit before its child writes the file.
    while (-not (Test-Path $resultFile) -and (Get-Date) -lt $deadline -and @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($installRoot, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) { Start-Sleep -Milliseconds 500 }
    Start-Sleep -Milliseconds 500
  } finally {
    foreach ($k in $Environment.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
  }
  $state = if ($proc.HasExited) { "$(Split-Path -Leaf $Executable) exit $($proc.ExitCode)" } else { "still running at 120 s" }
  Stop-GpCaseProcesses -Proc $proc -Tag $tag
  if (Test-Path $resultFile) { return ([string](Get-Content -Raw $resultFile)).Trim() }
  $err = ""
  foreach ($f in @($stderr, $launcherLog)) {
    if (Test-Path $f) { $err += " " + ([string](Get-Content -Raw $f) -replace "\s+", " ") }
  }
  $err = $err.Trim()
  if ($err.Length -gt 300) { $err = $err.Substring(0, 300) }
  return "FAIL no result ($state; stderr: $err)"
}

# --- 2. Run the cases, then restore the machine -----------------------------

# Everything this script changes on the machine, captured first.
$werKey = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"
$policyKey = "HKLM:\SOFTWARE\Policies\Microsoft\SystemCertificates\AuthRoot"
$regSnapshots = @(
  (Get-GpRegSnapshot -Key $werKey -Name "DontShowUI"),
  (Get-GpRegSnapshot -Key $werKey -Name "Disabled"),
  (Get-GpRegSnapshot -Key $policyKey -Name "DisableRootAutoUpdate")
)
foreach ($snap in $regSnapshots) { Write-GpStep "before: $($snap.Key)\$($snap.Name) existed=$($snap.ValueExisted) kind=$($snap.Kind) data=$($snap.Data) keyExisted=$($snap.KeyExisted)" }

$sanity = ""
$sanityDirect = ""
$results = [System.Collections.Generic.List[psobject]]::new()
$isolated = $false
$skipped = [System.Collections.Generic.List[string]]::new()
$skipped.Add("MSI backend smoke launch (validation.smoke.enabled=false): not run, so not a pass. The tool exits after one fetch; the MSI install, layout and uninstall validation did run.") | Out-Null
try {
  # Windows Error Reporting would hold a crashed process open behind a dialog.
  New-Item -Path $werKey -Force | Out-Null
  Set-ItemProperty -Path $werKey -Name "DontShowUI" -Value 1 -Type DWord
  Set-ItemProperty -Path $werKey -Name "Disabled" -Value 1 -Type DWord

  # Sanity: before any root is removed, the installed app must fetch the first
  # candidate. If it doesn't, the cases below can't mean anything.
  $sanity = Invoke-GpCase -Url $CandidateUrls[0]
  Write-GpStep "sanity (store intact, bundle in place): $sanity"
  if (-not $sanity.StartsWith("PASS")) {
    $savedPath = $env:PATH
    $env:PATH = (Join-Path $installRoot "runtime\bin") + ";" + $env:PATH
    $sanityDirect = Invoke-GpCase -Url $CandidateUrls[0] -Executable (Join-Path $installRoot "app\gp-tls-fetch.exe")
    $env:PATH = $savedPath
    Write-GpStep "sanity, tool run directly with runtime\bin on PATH: $sanityDirect"
    $skipped.Add("All TLS cases: the sanity fetch failed, so no root was removed.") | Out-Null
  } else {
    New-Item -Path $policyKey -Force | Out-Null
    Set-ItemProperty -Path $policyKey -Name "DisableRootAutoUpdate" -Value 1 -Type DWord
    Write-GpStep "DisableRootAutoUpdate set"

    $ours = Get-GpPemThumbprints -Path $bundle.FullName
    Write-GpStep "bundle has $($ours.Count) certificates"

    $olderList = $null
    try {
      $zip = Join-Path $WorkRoot "older.zip"
      Invoke-WebRequest -Uri $OlderListUrl -OutFile $zip -UseBasicParsing
      $olderDir = Join-Path $WorkRoot "older"
      Expand-Archive -Path $zip -DestinationPath $olderDir -Force
      $olderList = Get-ChildItem -Path $olderDir -Recurse -Filter "ca-certificates.crt" | Where-Object { $_.Directory.Name -eq "GSTLS" } | Select-Object -First 1
    } catch {
      Write-GpStep "could not get the older list: $($_.Exception.Message)"
    }
    $older = if ($olderList) { Get-GpPemThumbprints -Path $olderList.FullName } else { $null }
    if ($older) { Write-GpStep "older list (ObjcMarkdown 0.2.6) has $($older.Count) certificates" } else { $skipped.Add("Older-list case: the ObjcMarkdown 0.2.6 list could not be fetched.") | Out-Null }

    foreach ($url in $CandidateUrls) {
      try { $root = Get-GpChainRoot -Url $url } catch { Write-GpStep "${url}: no chain ($($_.Exception.Message))"; $skipped.Add("${url}: no chain could be built.") | Out-Null; continue }
      $thumb = $root.Thumbprint
      Write-GpStep "${url}: root $($root.Subject) [$thumb]"
      if (-not $ours.Contains($thumb)) { Write-GpStep "  not in the bundle; next"; $skipped.Add("${url}: root $($root.Subject) is not in the bundle.") | Out-Null; continue }

      $removedFrom = Remove-GpRoot -Thumbprint $thumb
      $hostFetch = Test-GpHostFetch -Url $url
      Write-GpStep "  removed from: $([string]::Join(',', $removedFrom)); host fetch now: $hostFetch"

      Move-Item -Force $bundle.FullName $bundleAside
      $control = Invoke-GpCase -Url $url
      Write-GpStep "  control (no bundle): $control"
      if ($control.StartsWith("PASS")) {
        Move-Item -Force $bundleAside $bundle.FullName
        $results.Add([pscustomobject]@{ Url = $url; Root = $root.Subject; Thumbprint = $thumb; RemovedFrom = [string]::Join(",", $removedFrom); HostFetch = $hostFetch; Control = $control; Bundled = "not run"; EnvFile = "not run"; OlderList = "not run"; Isolated = $false }) | Out-Null
        $skipped.Add("${url}: control passed with the root removed (another trust path), so its other cases were not run.") | Out-Null
        continue
      }

      $envFile = Invoke-GpCase -Url $url -Environment @{ GS_TLS_CA_FILE = $bundleCopy }
      Write-GpStep "  GS_TLS_CA_FILE: $envFile"

      $olderResult = "not run (no older list)"
      if ($olderList) {
        Copy-Item -Force $olderList.FullName $bundle.FullName
        $olderResult = Invoke-GpCase -Url $url
        $olderResult = "{0} (root in that list: {1})" -f $olderResult, $older.Contains($thumb)
        Write-GpStep "  older list: $olderResult"
        Remove-Item -Force $bundle.FullName
      }

      Move-Item -Force $bundleAside $bundle.FullName
      $bundled = Invoke-GpCase -Url $url
      Write-GpStep "  bundled: $bundled"

      $results.Add([pscustomobject]@{ Url = $url; Root = $root.Subject; Thumbprint = $thumb; RemovedFrom = [string]::Join(",", $removedFrom); HostFetch = $hostFetch; Control = $control; Bundled = $bundled; EnvFile = $envFile; OlderList = $olderResult; Isolated = $true }) | Out-Null
      $isolated = $true
      break
    }
  }
} catch {
  Write-GpStep "ERROR during the cases: $($_.Exception.Message)"
  $script:restoreProblems.Add("cases stopped early: $($_.Exception.Message)") | Out-Null
} finally {
  if (Test-Path $bundleAside) { Move-Item -Force $bundleAside $bundle.FullName }
  Restore-GpCertificates
  foreach ($snap in $regSnapshots) { Restore-GpRegSnapshot -Snap $snap }
}

# Check the restoration before reporting anything.
$certCheck = Test-GpCertificatesRestored
$regCheck = @($regSnapshots | ForEach-Object { Test-GpRegRestored -Snap $_ })
foreach ($c in $certCheck) { Write-GpStep "restored? $($c.Store) $($c.Thumbprint): $($c.Present)" }
foreach ($r in $regCheck) { Write-GpStep "restored? $($r.Key)\$($r.Name): $($r.Restored) (before: $($r.Before); after: $($r.After))" }
$restored = (@($certCheck | Where-Object { -not $_.Present }).Count -eq 0) -and (@($regCheck | Where-Object { -not $_.Restored }).Count -eq 0) -and ($script:restoreProblems.Count -eq 0)
$ownedLeft = @($script:cleanup | Where-Object { $_.OwnedLeft.Count -gt 0 -or $_.CleanupErrors.Count -gt 0 })

$report = [ordered]@{
  Sanity = $sanity
  SanityDirect = $sanityDirect
  Cases = $results
  SkippedChecks = $skipped
  Restoration = [ordered]@{ Restored = $restored; Certificates = $certCheck; Registry = $regCheck; Problems = $script:restoreProblems }
  Cleanup = $script:cleanup
}
$report | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $WorkRoot "results.json") -Encoding utf8
$results | Format-List | Out-String -Width 400 | Write-Host

$exitCode = 1
if (-not $sanity.StartsWith("PASS")) {
  Write-GpStep "RESULT: the installed app can't fetch https with the store intact; no TLS case was run."
} elseif (-not $isolated) {
  Write-GpStep "RESULT: no candidate URL isolated a root (no chain, root not in the bundle, or the control case passed)."
} else {
  $last = $results[$results.Count - 1]
  if ($last.Bundled.StartsWith("PASS") -and $last.EnvFile.StartsWith("PASS")) {
    Write-GpStep "RESULT: the bundled CA file let the installed app fetch $($last.Url) with its root removed from the store."
    $exitCode = 0
  } else {
    Write-GpStep "RESULT: the control failed, but the bundled or GS_TLS_CA_FILE case also failed."
  }
}
if (-not $restored) { Write-GpStep "RESTORATION FAILED: the machine is not back to its prior state (see results.json)."; $exitCode = 1 }
else { Write-GpStep "restoration verified: certificates and registry values are as they were before" }
if ($ownedLeft.Count -gt 0) { Write-GpStep "CLEANUP: an owned process was left or could not be stopped (see results.json)."; $exitCode = 1 }
exit $exitCode
