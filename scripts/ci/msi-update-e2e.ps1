<#
.SYNOPSIS
End-to-end MSI update test for the signed-update helper, on a Windows runner.

.DESCRIPTION
Builds the sample-gui MSI at 0.1.0 and 0.1.1 with updates on and a throwaway
Ed25519 key, signs the 0.1.1 and 0.1.0 feeds (edSignature and
versionSignature, with openssl directly), installs 0.1.0, and runs
gp-update-helper through these cases against the installed copy:

  tampered   the downloaded MSI altered         -> refused, 0.1.0 stays
  versig     versionSignature altered           -> refused
  rollback   signed 0.1.0 relabelled as 0.1.2   -> refused
  replay     the real 0.1.0 entry               -> refused (not newer)
  nokey      no publicEDKey in the plan         -> refused
  good       the signed 0.1.1 entry             -> prepared, applied, 0.1.1 installed

Refusals run first, while 0.1.0 is installed. Writes a results table and
exits 1 if any case doesn't behave as expected. Needs openssl on PATH and the
gnustep-cli-new toolchain the helper was built with.
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$HelperPath,
  [string]$WorkRoot = (Join-Path ([System.IO.Path]::GetTempPath()) "gp-msi-e2e")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
. (Join-Path $repoRoot "scripts\lib\core.ps1")

if (Test-Path $WorkRoot) { Remove-Item -Recurse -Force $WorkRoot }
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null
$openssl = (Get-Command openssl -ErrorAction Stop).Source
Write-Host "openssl: $openssl ($(& $openssl version))"

# A throwaway key: the public half goes in the manifests, the private half
# never leaves this run.
$keyPath = Join-Path $WorkRoot "key.pem"
& $openssl genpkey -algorithm ed25519 -out $keyPath
if ($LASTEXITCODE -ne 0) { throw "openssl genpkey failed" }
$publicDer = Join-Path $WorkRoot "pub.der"
& $openssl pkey -in $keyPath -pubout -outform DER -out $publicDer
$pubBytes = [System.IO.File]::ReadAllBytes($publicDer)
$publicKey = [Convert]::ToBase64String($pubBytes[($pubBytes.Length - 32)..($pubBytes.Length - 1)])
Write-Host "throwaway public key: $publicKey"

function New-GpSignature {
  param([byte[]]$Bytes)
  $inPath = Join-Path $WorkRoot ("msg-" + [guid]::NewGuid().ToString("N"))
  $sigPath = "$inPath.sig"
  [System.IO.File]::WriteAllBytes($inPath, $Bytes)
  & $openssl pkeyutl -sign -inkey $keyPath -rawin -in $inPath -out $sigPath
  if ($LASTEXITCODE -ne 0) { throw "openssl pkeyutl -sign failed" }
  $signature = [System.IO.File]::ReadAllBytes($sigPath)
  if ($signature.Length -ne 64) { throw "openssl made a $($signature.Length)-byte signature" }
  return [Convert]::ToBase64String($signature)
}

# Build both versions from the sample-gui example.
$sampleRoot = Join-Path $repoRoot "examples\sample-gui"
$baseManifest = Get-Content -Raw (Join-Path $sampleRoot "package.manifest.json") | ConvertFrom-Json -AsHashtable
$builds = @{}
foreach ($version in @("0.1.0", "0.1.1")) {
  $manifest = Copy-GpValue -Value $baseManifest
  $manifest["package"]["version"] = $version
  $manifest["updates"] = [ordered]@{
    enabled = $true
    provider = "github-release-feed"
    channel = "stable"
    minimumCheckIntervalHours = 24
    startupDelaySeconds = 15
    publicEDKey = $publicKey
    github = [ordered]@{ owner = "example-org"; repo = "sample"; tagPattern = "v{version}"; releaseNotesUrlPattern = "https://github.com/{owner}/{repo}/releases/tag/{tag}" }
  }
  $manifest["backends"]["msi"]["updates"] = [ordered]@{ feedUrl = "https://example.invalid/updates/windows/stable.json" }
  $manifestPath = Join-Path $sampleRoot "e2e-$version.manifest.json"
  $manifest | ConvertTo-Json -Depth 30 | Set-Content -Path $manifestPath -Encoding utf8
  & (Join-Path $repoRoot "scripts\run-packaging-pipeline.ps1") -Manifest $manifestPath -Backend msi
  if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { throw "packaging $version failed" }
  $msi = Get-ChildItem (Join-Path $sampleRoot "dist\packages") -Filter "*$version*.msi" | Select-Object -First 1
  $feedFile = Get-ChildItem (Join-Path $sampleRoot "dist\packages") -Filter "*$version*.update-feed.json" | Select-Object -First 1
  if ($null -eq $msi -or $null -eq $feedFile) { throw "no MSI or feed for $version" }
  $builds[$version] = [pscustomobject]@{ Msi = $msi.FullName; Feed = $feedFile.FullName }
}

# Mirror the MSIs locally, point the feeds at them and sign them.
$mirror = New-Item -ItemType Directory -Force -Path (Join-Path $WorkRoot "mirror")
$feeds = @{}
foreach ($version in $builds.Keys) {
  $copy = Join-Path $mirror (Split-Path -Leaf $builds[$version].Msi)
  Copy-Item $builds[$version].Msi $copy
  $feed = Get-Content -Raw $builds[$version].Feed | ConvertFrom-Json -AsHashtable
  $asset = $feed["releases"][0]["assets"][0]
  $asset["url"] = ([System.Uri]::new($copy)).AbsoluteUri
  $sha = (Get-FileHash -Algorithm SHA256 -Path $copy).Hash.ToLowerInvariant()
  if ($asset["sha256"] -ne $sha) { throw "feed sha256 for $version doesn't match the MSI" }
  $asset["edSignature"] = New-GpSignature -Bytes ([System.IO.File]::ReadAllBytes($copy))
  $message = [string]::Join("`n", @("gnustep-packager-update-v1", $feed["package"]["id"], $feed["releases"][0]["version"], $feed["channel"], $asset["platform"], $sha))
  $asset["versionSignature"] = New-GpSignature -Bytes ([System.Text.Encoding]::UTF8.GetBytes($message))
  $feeds[$version] = $feed
  Write-Host ("feed {0}: platform {1}, signed" -f $version, $asset["platform"])
}
$tamperedDir = New-Item -ItemType Directory -Force -Path (Join-Path $WorkRoot "mirror-tampered")
$tamperedMsi = Join-Path $tamperedDir (Split-Path -Leaf $builds["0.1.1"].Msi)
$bytes = [System.IO.File]::ReadAllBytes((Join-Path $mirror (Split-Path -Leaf $builds["0.1.1"].Msi)))
$bytes[[int]($bytes.Length / 2)] = $bytes[[int]($bytes.Length / 2)] -bxor 0x5A
[System.IO.File]::WriteAllBytes($tamperedMsi, $bytes)

function Get-GpInstalledSample {
  foreach ($root in @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall")) {
    $entry = Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object { Get-ItemProperty $_.PSPath } |
      Where-Object { $_.PSObject.Properties["DisplayName"] -and $_.DisplayName -like "Sample GNUstep App*" } | Select-Object -First 1
    if ($entry) { return $entry }
  }
  return $null
}

# Install 0.1.0 for the current user.
$log = Join-Path $WorkRoot "install-0.1.0.log"
$p = Start-Process msiexec.exe -ArgumentList @("/i", "`"$($builds["0.1.0"].Msi)`"", "/qn", "/l*v", "`"$log`"") -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "installing 0.1.0 failed: msiexec $($p.ExitCode), see $log" }
$installed = Get-GpInstalledSample
if ($null -eq $installed) { throw "0.1.0 installed but not found in Uninstall" }
Write-Host "installed: $($installed.DisplayName) $($installed.DisplayVersion) at $($installed.InstallLocation)"
# The relaunch path the way the app's updater computes it: the install root
# (the folder holding metadata\updates) plus the packaged config's
# package.launcherRelativePath. The Uninstall entry has no InstallLocation.
$installedConfig = Get-ChildItem -Path @($env:LOCALAPPDATA, $env:ProgramFiles) -Recurse -Filter "gnustep-packager-update.json" -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -like "*SampleGNUstepApp*\metadata\updates\*" } | Select-Object -First 1
if ($null -eq $installedConfig) { throw "the installed updater config was not found" }
$installRoot = $installedConfig.Directory.Parent.Parent.FullName
$installedPackage = (Get-Content -Raw $installedConfig.FullName | ConvertFrom-Json -AsHashtable)["package"]
if (-not $installedPackage.Contains("launcherRelativePath")) { throw "the installed config has no package.launcherRelativePath" }
$relaunchPath = Join-Path $installRoot ([string]$installedPackage["launcherRelativePath"])
if (-not (Test-Path $relaunchPath)) { throw "the relaunch path $relaunchPath does not exist" }
Write-Host "install root: $installRoot; relaunch path: $relaunchPath"

$results = [System.Collections.Generic.List[object]]::new()
$failures = 0
foreach ($case in @(
  @{ Name = "tampered"; Feed = "0.1.1"; Expect = "refused" },
  @{ Name = "versig"; Feed = "0.1.1"; Expect = "refused" },
  @{ Name = "rollback"; Feed = "0.1.0"; Expect = "refused" },
  @{ Name = "replay"; Feed = "0.1.0"; Expect = "refused" },
  @{ Name = "nokey"; Feed = "0.1.1"; Expect = "refused" },
  @{ Name = "good"; Feed = "0.1.1"; Expect = "installed" }
)) {
  $caseRoot = New-Item -ItemType Directory -Force -Path (Join-Path $WorkRoot "case-$($case.Name)")
  $work = New-Item -ItemType Directory -Force -Path (Join-Path $caseRoot "work")
  $statePath = Join-Path $work "update-state.json"
  $feed = Copy-GpValue -Value $feeds[$case.Feed]
  $release = $feed["releases"][0]
  $asset = $release["assets"][0]
  $version = [string]$release["version"]
  $package = [ordered]@{ id = $feed["package"]["id"]; name = $feed["package"]["name"]; displayName = $feed["package"]["displayName"]; currentVersion = [string]$installed.DisplayVersion; backend = "msi"; channel = $feed["channel"]; publicEDKey = $publicKey }
  switch ($case.Name) {
    "tampered" { $asset["url"] = ([System.Uri]::new($tamperedMsi)).AbsoluteUri }
    "versig" { $b = [Convert]::FromBase64String($asset["versionSignature"]); $b[5] = $b[5] -bxor 1; $asset["versionSignature"] = [Convert]::ToBase64String($b) }
    "rollback" { $version = "0.1.2" }
    "nokey" { $package.Remove("publicEDKey") }
  }
  $plan = [ordered]@{
    formatVersion = 1
    package = $package
    release = [ordered]@{ version = $version }
    asset = $asset
    currentExecutablePath = $relaunchPath
    execution = [ordered]@{ stateFile = $statePath; workingRoot = [string]$work; relaunchExecutablePath = $relaunchPath }
  }
  $planPath = Join-Path $caseRoot "plan.json"
  $plan | ConvertTo-Json -Depth 20 | Set-Content -Path $planPath -Encoding utf8

  & $HelperPath --mode prepare --plan $planPath --state-file $statePath | Out-Null
  $prepareCode = $LASTEXITCODE
  $state = Get-Content -Raw $statePath | ConvertFrom-Json -AsHashtable
  $detail = if ($state.Contains("error")) { [string]$state["error"]["message"] } else { [string]$state["message"] }
  $relaunched = "n/a"
  if ($state["status"] -eq "readyToApply") {
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($installRoot, [System.StringComparison]::OrdinalIgnoreCase) } | Stop-Process -Force -ErrorAction SilentlyContinue
    $applyStart = Get-Date
    & $HelperPath --mode apply --plan $planPath --state-file $statePath | Out-Null
    $deadline = (Get-Date).AddMinutes(5)
    do {
      Start-Sleep -Seconds 3
      $state = Get-Content -Raw $statePath | ConvertFrom-Json -AsHashtable
    } while ($state["status"] -notin @("completed", "failed") -and (Get-Date) -lt $deadline)
    $detail = "apply: $($state["status"]): $($state["message"])"
    # apply-msi.cmd starts the launcher once msiexec finishes; the fixture
    # app then stays up for 30 seconds.
    $relaunched = "no"
    $waitUntil = (Get-Date).AddSeconds(30)
    do {
      $started = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -and $_.Path.StartsWith($installRoot, [System.StringComparison]::OrdinalIgnoreCase) -and $_.StartTime -ge $applyStart })
      if ($started.Count -gt 0) { $relaunched = "yes: " + (($started | ForEach-Object { Split-Path -Leaf $_.Path }) -join ", "); break }
      Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $waitUntil)
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($installRoot, [System.StringComparison]::OrdinalIgnoreCase) } | Stop-Process -Force -ErrorAction SilentlyContinue
  }
  $now = Get-GpInstalledSample
  $nowVersion = if ($now) { [string]$now.DisplayVersion } else { "none" }
  $outcome = if ($nowVersion -like "0.1.1*") { "installed" } elseif ($state["status"] -eq "failed" -and $nowVersion -like "0.1.0*") { "refused" } else { "unexpected" }
  $ok = $outcome -eq $case.Expect
  if ($case.Expect -eq "installed" -and -not $relaunched.StartsWith("yes")) { $ok = $false }
  if (-not $ok) { $failures++ }
  $results.Add([pscustomobject]@{ Case = $case.Name; Expected = $case.Expect; Outcome = $outcome; Installed = $nowVersion; Relaunched = $relaunched; PrepareExit = $prepareCode; Detail = $detail; Pass = $ok }) | Out-Null
}

$results | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Write-Host
$results | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $WorkRoot "results.json") -Encoding utf8
if ($failures -gt 0) { throw "$failures MSI update case(s) did not behave as expected." }
Write-Host "All MSI update cases behaved as expected."
