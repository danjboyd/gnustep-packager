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
   removes it from the machine's Root and AuthRoot stores.
3. Runs the cases through the installed launcher:
     control  bundle moved away                         -> must FAIL
     bundled  bundle in place                           -> must PASS
     envfile  bundle moved away, GS_TLS_CA_FILE = copy  -> must PASS
     olderlist ObjcMarkdown 0.2.6's list in its place    -> FAIL if the root
               isn't in that list (recorded either way)
   A URL whose control case passes isn't isolating the root (another trust path
   exists), so the script moves on to the next candidate.

Writes results.json and a table, and exits 1 unless one candidate gave a
failing control with passing bundled and envfile cases.
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
  validation = [ordered]@{ fetchesHttps = $true; smoke = [ordered]@{ enabled = $false; kind = "staged-layout"; requiredPaths = @("app/gp-tls-fetch.exe"); timeoutSeconds = 30 }; logs = [ordered]@{ retainOnSuccess = $true } }
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
function Stop-GpCaseProcesses {
  param($Proc)
  if ($Proc -and -not $Proc.HasExited) { & taskkill.exe /T /F /PID $Proc.Id 2>&1 | Out-Null }
  Get-Process -ErrorAction SilentlyContinue | Where-Object {
    ($_.Path -and $_.Path.StartsWith($installRoot, [System.StringComparison]::OrdinalIgnoreCase)) -or $_.ProcessName -in @("WerFault", "WerFaultSecure")
  } | Stop-Process -Force -ErrorAction SilentlyContinue
}
function Invoke-GpCase {
  param([string]$Url, [hashtable]$Environment = @{}, [string]$Executable = $launcher.FullName)
  $script:caseNumber++
  $tag = "case{0}" -f $script:caseNumber
  Write-GpStep ("{0} start: {1} via {2} env={3}" -f $tag, $Url, (Split-Path -Leaf $Executable), [string]::Join(",", @($Environment.Keys)))
  $resultFile = Join-Path $WorkRoot "result-$tag.txt"
  $stdout = Join-Path $WorkRoot "result-$tag.stdout.txt"
  $stderr = Join-Path $WorkRoot "result-$tag.stderr.txt"
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
  $state = if ($proc.HasExited) { "exit $($proc.ExitCode)" } else { "still running at 120 s" }
  Stop-GpCaseProcesses -Proc $proc
  if (Test-Path $resultFile) { return (Get-Content -Raw $resultFile).Trim() }
  $err = if (Test-Path $stderr) { ((Get-Content -Raw $stderr) -replace "\s+", " ").Trim() } else { "" }
  if ($err.Length -gt 300) { $err = $err.Substring(0, 300) }
  return "FAIL no result ($state; stderr: $err)"
}

# Windows Error Reporting would hold a crashed process open behind a dialog.
$werKey = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"
New-Item -Path $werKey -Force | Out-Null
Set-ItemProperty -Path $werKey -Name "DontShowUI" -Value 1 -Type DWord
Set-ItemProperty -Path $werKey -Name "Disabled" -Value 1 -Type DWord

# Sanity: before any root is removed, the installed app must fetch the first
# candidate. If it doesn't, the cases below can't mean anything, so stop here
# with the launcher's and the bare tool's output.
$sanity = Invoke-GpCase -Url $CandidateUrls[0]
Write-GpStep "sanity (store intact, bundle in place): $sanity"
if (-not $sanity.StartsWith("PASS")) {
  $env:PATH = (Join-Path $installRoot "runtime\bin") + ";" + $env:PATH
  $bare = Invoke-GpCase -Url $CandidateUrls[0] -Executable (Join-Path $installRoot "app\gp-tls-fetch.exe")
  Write-GpStep "sanity, tool run directly with runtime\bin on PATH: $bare"
  @([pscustomobject]@{ Url = $CandidateUrls[0]; Sanity = $sanity; SanityDirect = $bare; Isolated = $false }) | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $WorkRoot "results.json") -Encoding utf8
  Write-GpStep "RESULT: the installed app can't fetch https with the store intact; no TLS case was run."
  exit 1
}

# --- 2. Isolate a root -------------------------------------------------------

$policyKey = "HKLM:\SOFTWARE\Policies\Microsoft\SystemCertificates\AuthRoot"
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
if ($older) { Write-GpStep "older list (ObjcMarkdown 0.2.6) has $($older.Count) certificates" }

$results = [System.Collections.Generic.List[psobject]]::new()
$isolated = $false
foreach ($url in $CandidateUrls) {
  try { $root = Get-GpChainRoot -Url $url } catch { Write-GpStep "${url}: no chain ($($_.Exception.Message))"; continue }
  $thumb = $root.Thumbprint
  Write-GpStep "${url}: root $($root.Subject) [$thumb]"
  if (-not $ours.Contains($thumb)) { Write-GpStep "  not in the bundle; next"; continue }

  $removedFrom = Remove-GpRoot -Thumbprint $thumb
  $hostFetch = Test-GpHostFetch -Url $url
  Write-GpStep "  removed from: $([string]::Join(',', $removedFrom)); host fetch now: $hostFetch"

  Move-Item -Force $bundle.FullName $bundleAside
  $control = Invoke-GpCase -Url $url
  Write-GpStep "  control (no bundle): $control"
  if ($control.StartsWith("PASS")) {
    Move-Item -Force $bundleAside $bundle.FullName
    $results.Add([pscustomobject]@{ Url = $url; Root = $root.Subject; Thumbprint = $thumb; RemovedFrom = [string]::Join(",", $removedFrom); HostFetch = $hostFetch; Control = $control; Bundled = ""; EnvFile = ""; OlderList = ""; Isolated = $false }) | Out-Null
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

$results | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $WorkRoot "results.json") -Encoding utf8
$results | Format-List | Out-String -Width 400 | Write-Host

if (-not $isolated) { Write-GpStep "No candidate URL isolated a root (see the lines above: no chain, root not in the bundle, or the control case passed)."; exit 1 }
$last = $results[$results.Count - 1]
if ($last.Bundled.StartsWith("PASS") -and $last.EnvFile.StartsWith("PASS")) {
  Write-GpStep "RESULT: the bundled CA file let the installed app fetch $($last.Url) with its root removed from the store."
  exit 0
}
Write-GpStep "RESULT: the control failed, but the bundled or GS_TLS_CA_FILE case also failed."
exit 1
