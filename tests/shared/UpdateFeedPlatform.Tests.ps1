Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Describe "Update feed platforms" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
    $script:mergeScript = Join-Path $script:repoRoot "scripts/merge-update-feeds.ps1"

    function New-GpTestFeed {
      param([string]$Path, [string]$Platform, [string]$Name, [string]$Channel = "stable", [string]$Id = "com.example.App")
      [ordered]@{
        formatVersion = 1
        channel = $Channel
        package = [ordered]@{ id = $Id; version = "1.2.3" }
        releases = @([ordered]@{ version = "1.2.3"; assets = @([ordered]@{ backend = "appimage"; platform = $Platform; name = $Name }) })
      } | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding utf8
    }
  }

  It "names platforms from the backend and architecture" {
    $hostPlatform = if ((Get-GpHostArchitecture) -eq "aarch64") { "linux-arm64" } else { "linux-x64" }
    Get-GpUpdatePlatform -Backend appimage | Should -Be $hostPlatform -Because "an AppImage defaults to the build host's architecture"
    Get-GpUpdatePlatform -Backend msi | Should -Be "windows-x64"
    Get-GpUpdatePlatform -Backend dmg | Should -Be "macos"
    Get-GpUpdatePlatform -Backend appimage -Architecture aarch64 | Should -Be "linux-arm64"
    Get-GpUpdatePlatform -Backend appimage -Architecture arm64 | Should -Be "linux-arm64"
    Get-GpUpdatePlatform -Backend msi -Architecture arm64 | Should -Be "windows-arm64"
    Get-GpUpdatePlatform -Backend appimage -Architecture amd64 | Should -Be "linux-x64"
    { Get-GpUpdatePlatform -Backend appimage -Architecture riscv64 } | Should -Throw "*Unknown architecture*"
  }

  It "flags duplicate platforms and a non-x64 asset listed first" {
    $feed = [ordered]@{ releases = @([ordered]@{ version = "1.2.3"; assets = @(
      [ordered]@{ backend = "appimage"; platform = "linux-arm64"; name = "a" },
      [ordered]@{ backend = "appimage"; platform = "linux-x64"; name = "b" },
      [ordered]@{ backend = "appimage"; platform = "linux-x64"; name = "c" }
    ) }) }
    $issues = @(Test-GpUpdateFeedAssets -Feed $feed)
    @($issues | Where-Object { $_ -like "*two appimage assets for platform 'linux-x64'*" }).Count | Should -Be 1
    @($issues | Where-Object { $_ -like "*before the x64 one*" }).Count | Should -Be 1

    $good = [ordered]@{ releases = @([ordered]@{ version = "1.2.3"; assets = @(
      [ordered]@{ backend = "appimage"; platform = "linux-x64"; name = "b" },
      [ordered]@{ backend = "appimage"; platform = "linux-arm64"; name = "a" }
    ) }) }
    @(Test-GpUpdateFeedAssets -Feed $good).Count | Should -Be 0
  }

  It "merges per-architecture feeds with x64 first, whatever the input order" {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-merge-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    try {
      New-GpTestFeed -Path (Join-Path $root "arm.json") -Platform "linux-arm64" -Name "App-aarch64.AppImage"
      New-GpTestFeed -Path (Join-Path $root "x64.json") -Platform "linux-x64" -Name "App-x86_64.AppImage"
      $out = Join-Path $root "stable.json"
      & $script:mergeScript -Output $out (Join-Path $root "arm.json") (Join-Path $root "x64.json") | Out-Null
      $merged = Get-Content -Raw $out | ConvertFrom-Json -AsHashtable
      @($merged["releases"]).Count | Should -Be 1
      @($merged["releases"][0]["assets"] | ForEach-Object { $_["name"] }) | Should -Be @("App-x86_64.AppImage", "App-aarch64.AppImage")
      $merged["channel"] | Should -Be "stable"
    } finally {
      Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
    }
  }

  It "refuses to merge duplicates or feeds for another package or channel" {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-merge-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    try {
      New-GpTestFeed -Path (Join-Path $root "a.json") -Platform "linux-x64" -Name "one"
      New-GpTestFeed -Path (Join-Path $root "b.json") -Platform "linux-x64" -Name "two"
      New-GpTestFeed -Path (Join-Path $root "beta.json") -Platform "linux-arm64" -Name "beta" -Channel "beta"
      New-GpTestFeed -Path (Join-Path $root "other.json") -Platform "linux-arm64" -Name "other" -Id "com.example.Other"
      $out = Join-Path $root "stable.json"
      { & $script:mergeScript -Output $out (Join-Path $root "a.json") (Join-Path $root "b.json") } | Should -Throw "*two appimage assets*"
      { & $script:mergeScript -Output $out (Join-Path $root "a.json") (Join-Path $root "beta.json") } | Should -Throw "*channel*"
      { & $script:mergeScript -Output $out (Join-Path $root "a.json") (Join-Path $root "other.json") } | Should -Throw "*package*"
      Test-Path $out | Should -BeFalse
    } finally {
      Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
    }
  }
}
