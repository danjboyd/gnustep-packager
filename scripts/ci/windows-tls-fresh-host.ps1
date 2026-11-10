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
. (Join-Path $PSScriptRoot "windows-tls-fresh-host-helpers.ps1")
$script:WorkRoot = $WorkRoot
$script:progressLog = $progressLog

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
# Processes from the install root that started after this point are ours.
$script:installSince = Get-Date
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

# The helpers below (certificates, registry snapshots, owned processes, the
# case runner and the restore steps) live in a separate file so the failure
# paths can be tested without a Windows runner: tests/shared/WindowsTlsFreshHost.Tests.ps1.
$script:launcherPath = $launcher.FullName
$script:installRoot = $installRoot

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
  # Each step runs whether or not the one before it threw.
  Invoke-GpRestoreSteps -Steps (New-GpRestoreSteps -Bundle $bundle.FullName -BundleAside $bundleAside -RegSnapshots $regSnapshots)
}

# Check the restoration and the cleanup before reporting anything.
$certCheck = @()
$regCheck = @()
try { $certCheck = Test-GpCertificatesRestored } catch { $script:restoreProblems.Add("could not check the certificates: $($_.Exception.Message)") | Out-Null }
foreach ($snap in $regSnapshots) {
  try { $regCheck += Test-GpRegRestored -Snap $snap } catch { $script:restoreProblems.Add("could not check $($snap.Key)\$($snap.Name): $($_.Exception.Message)") | Out-Null }
}
$finalOwned = Get-GpResidualOwned
foreach ($c in $certCheck) { Write-GpStep "restored? $($c.Store) $($c.Thumbprint): $($c.Present)" }
foreach ($r in $regCheck) { Write-GpStep "restored? $($r.Key)\$($r.Name): $($r.Restored) (before: $($r.Before); after: $($r.After))" }
$restored = (@($certCheck | Where-Object { -not $_.Present }).Count -eq 0) -and (@($regCheck | Where-Object { -not $_.Restored }).Count -eq 0) -and ($script:restoreProblems.Count -eq 0)
$ownedLeft = @($script:cleanup | Where-Object { $_.OwnedLeft.Count -gt 0 -or $_.CleanupErrors.Count -gt 0 })
foreach ($o in $finalOwned) { Write-GpStep "final check: OWNED PROCESS LEFT $o" }
if ($finalOwned.Count -eq 0) { Write-GpStep "final check: nothing left running from the install root" }

$report = [ordered]@{
  Sanity = $sanity
  SanityDirect = $sanityDirect
  Cases = $results
  SkippedChecks = $skipped
  Restoration = [ordered]@{ Restored = $restored; Certificates = $certCheck; Registry = $regCheck; Problems = $script:restoreProblems }
  Cleanup = $script:cleanup
  FinalOwnedLeft = $finalOwned
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
if ($ownedLeft.Count -gt 0 -or $finalOwned.Count -gt 0) { Write-GpStep "CLEANUP: an owned process was left or could not be stopped (see results.json)."; $exitCode = 1 }
exit $exitCode
