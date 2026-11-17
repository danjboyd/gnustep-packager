Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# A library declared under hostDependencies.windows.msys2Packages was installed
# into the setup-msys2 shell, but an app built with `gnustep build` runs inside
# the gnustep-cli-new toolchain's own MSYS2 runtime, whose pkg-config searches
# only the toolchain's prefix. SpreadsheetApp's MSI build stopped at "required
# packages were not found: vterm" with libvterm installed. These cases rebuild
# that on Linux: a CLANG64 package carrying vterm.pc, a toolchain-shaped root,
# and pkg-config limited to that root, as the toolchain's is.
Describe "MSYS2 libraries reach the toolchain's pkg-config" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")

    $script:tar = (Get-Command tar -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    $script:pkgConfig = (Get-Command pkg-config -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    $script:canRun = $script:tar -and $script:pkgConfig -and (Get-Command zstd -ErrorAction SilentlyContinue)

    $script:workRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-msys2-visibility-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $script:workRoot | Out-Null

    # mingw-w64-clang-x86_64-libvterm, reduced to what pkg-config and the MSI
    # need: the .pc file, the import library and the DLL.
    function New-GpVtermPackage {
      $source = Join-Path $script:workRoot "libvterm-src"
      $prefix = Join-Path $source "clang64"
      New-Item -ItemType Directory -Force -Path (Join-Path $prefix "lib/pkgconfig"), (Join-Path $prefix "bin") | Out-Null
      Set-Content -Path (Join-Path $prefix "lib/pkgconfig/vterm.pc") -Value @(
        'prefix=/clang64'
        'libdir=${prefix}/lib'
        'includedir=${prefix}/include'
        'Name: vterm'
        'Description: Abstract VT220/Xterm/ECMA-48 emulation library'
        'Version: 0.3.3'
        'Libs: -L${libdir} -lvterm'
        'Cflags: -I${includedir}'
      )
      Set-Content -Path (Join-Path $prefix "lib/libvterm.dll.a") -Value "import" -NoNewline
      Set-Content -Path (Join-Path $prefix "bin/libvterm-0.dll") -Value "dll" -NoNewline
      Set-Content -Path (Join-Path $source ".PKGINFO") -Value "pkgname = mingw-w64-clang-x86_64-libvterm"
      $package = Join-Path $script:workRoot "mingw-w64-clang-x86_64-libvterm-0.3.3-1-any.pkg.tar.zst"
      & $script:tar --force-local --zstd -cf $package -C $source .PKGINFO clang64
      if ($LASTEXITCODE -ne 0) { throw "tar failed for $package" }
      return $package
    }

    # A gnustep-cli-new style root: its own clang64 prefix with GNUstep's .pc files.
    function New-GpToolchainRoot {
      $root = Join-Path $script:workRoot "gnustep-cli-new"
      $pc = Join-Path $root "clang64/lib/pkgconfig"
      New-Item -ItemType Directory -Force -Path $pc | Out-Null
      Set-Content -Path (Join-Path $pc "gnustep-gui.pc") -Value @('Name: gnustep-gui', 'Description: GNUstep GUI', 'Version: 0.32.0')
      return $root
    }

    # pkg-config as the toolchain runs it: only its own prefix, nothing from the host.
    function Test-GpToolchainPkgConfig {
      param([string]$Root, [string]$Module)
      $previous = @{ LIBDIR = $env:PKG_CONFIG_LIBDIR; PATH = $env:PKG_CONFIG_PATH }
      try {
        $env:PKG_CONFIG_LIBDIR = Join-Path $Root "clang64/lib/pkgconfig"
        $env:PKG_CONFIG_PATH = ""
        & $script:pkgConfig --exists $Module
        return ($LASTEXITCODE -eq 0)
      } finally {
        $env:PKG_CONFIG_LIBDIR = $previous.LIBDIR
        $env:PKG_CONFIG_PATH = $previous.PATH
      }
    }
  }

  AfterAll {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $script:workRoot
  }

  It "picks the CLANG64 packages to lay over the toolchain and leaves shell tools out" {
    $picked = Get-GpMsys2ToolchainOverlayPackages -Packages @("make", "mingw-w64-clang-x86_64-libvterm", "curl", "mingw-w64-clang-x86_64-cmark", "mingw-w64-clang-x86_64-libvterm")
    $picked | Should -Be @("mingw-w64-clang-x86_64-libvterm", "mingw-w64-clang-x86_64-cmark")
    @(Get-GpMsys2ToolchainOverlayPackages -Packages @("make", "curl")).Count | Should -Be 0
  }

  It "makes an installed library visible to the toolchain's pkg-config and stages its DLL" {
    if (-not $script:canRun) {
      Set-ItResult -Skipped -Because "tar, zstd and pkg-config are needed"
      return
    }
    $package = New-GpVtermPackage
    $root = New-GpToolchainRoot

    # Before: the shell has libvterm, the toolchain doesn't. This is the failure.
    Test-GpToolchainPkgConfig -Root $root -Module "gnustep-gui" | Should -BeTrue
    Test-GpToolchainPkgConfig -Root $root -Module "vterm" | Should -BeFalse

    $overlay = Install-GpMsys2PackageOverlay -PackagePath $package -Root $root -TarPath $script:tar

    Test-GpToolchainPkgConfig -Root $root -Module "vterm" | Should -BeTrue
    Test-Path -LiteralPath (Join-Path $root "clang64/bin/libvterm-0.dll") | Should -BeTrue
    @($overlay.Files).Count | Should -Be 3
  }

  It "leaves a library the toolchain already carries alone" {
    if (-not $script:canRun) {
      Set-ItResult -Skipped -Because "tar, zstd and pkg-config are needed"
      return
    }
    $package = New-GpVtermPackage
    $root = Join-Path $script:workRoot "carried-toolchain"
    New-Item -ItemType Directory -Force -Path (Join-Path $root "clang64/bin") | Out-Null
    # The toolchain's own copy, which its GNUstep was built against.
    Set-Content -Path (Join-Path $root "clang64/bin/libvterm-0.dll") -Value "toolchain" -NoNewline

    $overlay = Install-GpMsys2PackageOverlay -PackagePath $package -Root $root -TarPath $script:tar -SkipIfCarried

    $overlay.Skipped | Should -BeTrue
    Get-Content -Raw (Join-Path $root "clang64/bin/libvterm-0.dll") | Should -Be "toolchain"
    Test-Path -LiteralPath (Join-Path $root "clang64/lib/pkgconfig/vterm.pc") | Should -BeFalse
  }

  It "is wired into the reusable workflow after the toolchain bootstrap, for manifest packages" {
    $workflow = Get-Content -Raw (Join-Path $script:repoRoot ".github/workflows/package-gnustep-app.yml")
    $bootstrap = $workflow.IndexOf("- name: Bootstrap And Smoke Test gnustep-cli-new For MSI")
    $overlay = $workflow.IndexOf("- name: Lay Manifest MSYS2 Libraries Over The Toolchain")
    $overlay | Should -BeGreaterThan $bootstrap
    $workflow | Should -Match "Get-GpMsys2ToolchainOverlayPackages -Packages"
    $workflow | Should -Match "steps.manifest.outputs.manifest_msys2_packages"
  }
}
