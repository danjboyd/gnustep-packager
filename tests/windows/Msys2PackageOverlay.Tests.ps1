Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Describe "MSYS2 package overlay" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")

    $msysRoot = if ($env:MSYS2_LOCATION) { $env:MSYS2_LOCATION } else { "C:\msys64" }
    $script:tar = Join-Path $msysRoot "usr\bin\tar.exe"
    $script:hasTar = (Test-Path -LiteralPath $script:tar) -and (Test-Path -LiteralPath (Join-Path $msysRoot "usr\bin\zstd.exe"))

    $script:workRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-overlay-tests-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $script:workRoot | Out-Null

    function New-GpTestPackage {
      param([string]$Name, [string]$Prefix = "clang64")

      $source = Join-Path $script:workRoot "$Name-src"
      $bundle = Join-Path $source "$Prefix\lib\GNUstep\Bundles\libgnustep-back-032.bundle"
      New-Item -ItemType Directory -Force -Path $bundle | Out-Null
      Set-Content -Path (Join-Path $bundle "libgnustep-back-032.dll") -Value "carried" -NoNewline
      Set-Content -Path (Join-Path $source ".PKGINFO") -Value "pkgname = test"
      $package = Join-Path $script:workRoot "$Name.pkg.tar.zst"
      & $script:tar --force-local --zstd -cf ($package -replace '\\', '/') -C ($source -replace '\\', '/') .PKGINFO $Prefix
      if ($LASTEXITCODE -ne 0) { throw "tar failed for $package" }
      return $package
    }

    function New-GpTestRoot {
      param([string]$Name, [switch]$Prefix, [switch]$Flattened)

      $root = Join-Path $script:workRoot $Name
      New-Item -ItemType Directory -Force -Path $root | Out-Null
      foreach ($base in @($(if ($Prefix) { Join-Path $root "clang64" }), $(if ($Flattened) { $root }))) {
        if ($base) {
          $bundle = Join-Path $base "lib\GNUstep\Bundles\libgnustep-back-032.bundle"
          New-Item -ItemType Directory -Force -Path $bundle | Out-Null
          Set-Content -Path (Join-Path $bundle "libgnustep-back-032.dll") -Value "stock" -NoNewline
        }
      }
      return $root
    }

    function Assert-GpThrows {
      param([scriptblock]$Script, [string]$Like)

      try { & $Script } catch {
        if ($_.Exception.Message -notlike $Like) { throw "Expected an error like '$Like', got: $($_.Exception.Message)" }
        return
      }
      throw "Expected an error like '$Like'."
    }
  }

  AfterAll {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $script:workRoot
  }

  It "replaces the prefix's files and the flattened copy's in a gnustep-cli-new style root" {
    if (-not $script:hasTar) { Write-Warning "MSYS2's tar and zstd aren't installed; skipped."; return }

    $package = New-GpTestPackage -Name "both"
    $root = New-GpTestRoot -Name "both-root" -Prefix -Flattened
    $result = Install-GpMsys2PackageOverlay -PackagePath $package -Root $root -TarPath $script:tar

    $relative = "lib\GNUstep\Bundles\libgnustep-back-032.bundle\libgnustep-back-032.dll"
    if (@($result.Files) -join "," -ne $relative) { throw "Unexpected file list: $(@($result.Files) -join ',')" }
    if (@($result.Targets).Count -ne 2) { throw "Expected both the prefix and the flattened copy as targets." }
    foreach ($base in @((Join-Path $root "clang64"), $root)) {
      $content = Get-Content -Raw -LiteralPath (Join-Path $base $relative)
      if ($content -ne "carried") { throw "$base still has the stock file." }
    }
    if (Test-Path -LiteralPath (Join-Path $root ".PKGINFO")) { throw "Package metadata should not be laid over the root." }
  }

  It "replaces only the prefix in a plain MSYS2-style root" {
    if (-not $script:hasTar) { Write-Warning "MSYS2's tar and zstd aren't installed; skipped."; return }

    $package = New-GpTestPackage -Name "prefix"
    $root = New-GpTestRoot -Name "prefix-root" -Prefix
    $result = Install-GpMsys2PackageOverlay -PackagePath $package -Root $root -TarPath $script:tar

    if (@($result.Targets).Count -ne 1) { throw "Expected only the prefix as a target." }
    if (Test-Path -LiteralPath (Join-Path $root "lib")) { throw "A root without a flattened copy should not gain one." }
  }

  It "refuses a root it can't lay the package over, and a package for another prefix" {
    if (-not $script:hasTar) { Write-Warning "MSYS2's tar and zstd aren't installed; skipped."; return }

    $package = New-GpTestPackage -Name "nowhere"
    $empty = New-GpTestRoot -Name "empty-root"
    Assert-GpThrows -Script { Install-GpMsys2PackageOverlay -PackagePath $package -Root $empty -TarPath $script:tar } -Like "*neither clang64*"

    $ucrt = New-GpTestPackage -Name "ucrt" -Prefix "ucrt64"
    $root = New-GpTestRoot -Name "ucrt-root" -Prefix
    Assert-GpThrows -Script { Install-GpMsys2PackageOverlay -PackagePath $ucrt -Root $root -TarPath $script:tar } -Like "*no clang64*"
  }
}
