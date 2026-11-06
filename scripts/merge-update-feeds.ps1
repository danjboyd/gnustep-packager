<#
.SYNOPSIS
Merges the per-artifact update feeds of one release into one feed.

.DESCRIPTION
Each packaging run writes <artifact>.update-feed.json with one asset. To
publish one feed for several architectures (an x86_64 and an aarch64
AppImage, say), merge them: releases with the same version are combined,
x64 assets come first in each release, and the result is refused if two
assets have the same backend and platform. The feeds must share package.id
and channel.

Updaters before gnustep-packager v0.1.9 install the first asset whose backend
matches, whatever its platform, which is why x64 stays first.

.EXAMPLE
pwsh scripts/merge-update-feeds.ps1 -Output stable.json dist/x64/*.update-feed.json dist/arm64/*.update-feed.json
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$Output,
  [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
  [string[]]$Feed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib/core.ps1")

$paths = @(foreach ($pattern in $Feed) { @(Resolve-Path -Path $pattern | ForEach-Object { $_.ProviderPath }) })
if ($paths.Count -eq 0) {
  throw "No feeds to merge."
}

$merged = $null
$releasesByVersion = [ordered]@{}
foreach ($path in $paths) {
  $document = Get-Content -Raw -Path $path | ConvertFrom-Json -AsHashtable
  if ($null -eq $merged) {
    $merged = [ordered]@{}
    foreach ($key in $document.Keys) {
      if ($key -ne "releases") { $merged[$key] = $document[$key] }
    }
  } else {
    foreach ($key in @("channel")) {
      if ([string]$document[$key] -ne [string]$merged[$key]) {
        throw "$path has $key '$($document[$key])', not '$($merged[$key])'."
      }
    }
    if ([string]$document["package"]["id"] -ne [string]$merged["package"]["id"]) {
      throw "$path is for package '$($document["package"]["id"])', not '$($merged["package"]["id"])'."
    }
  }
  foreach ($release in @($document["releases"])) {
    $version = [string]$release["version"]
    if (-not $releasesByVersion.Contains($version)) {
      $copy = [ordered]@{}
      foreach ($key in $release.Keys) { if ($key -ne "assets") { $copy[$key] = $release[$key] } }
      $copy["assets"] = [System.Collections.Generic.List[object]]::new()
      $releasesByVersion[$version] = $copy
    }
    foreach ($asset in @($release["assets"])) {
      $releasesByVersion[$version]["assets"].Add($asset) | Out-Null
    }
  }
}

foreach ($version in @($releasesByVersion.Keys)) {
  $assets = @($releasesByVersion[$version]["assets"])
  # Stable: x64 assets first, otherwise in input order.
  $ordered = @($assets | Where-Object { ([string]$_["platform"]).EndsWith("-x64") -or [string]::IsNullOrEmpty([string]$_["platform"]) }) +
    @($assets | Where-Object { -not (([string]$_["platform"]).EndsWith("-x64") -or [string]::IsNullOrEmpty([string]$_["platform"])) })
  $releasesByVersion[$version]["assets"] = $ordered
}
$merged["releases"] = @($releasesByVersion.Values)

$issues = @(Test-GpUpdateFeedAssets -Feed $merged)
if ($issues.Count -gt 0) {
  throw ("The merged feed would mislead clients:`n" + ($issues -join "`n"))
}

$merged | ConvertTo-Json -Depth 20 | Set-Content -Path $Output -Encoding utf8
Write-Host ("Merged {0} feed(s) into {1}." -f $paths.Count, $Output)
