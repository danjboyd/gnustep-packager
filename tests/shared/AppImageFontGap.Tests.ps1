Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Describe "AppImage font gap warning" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
    . (Join-Path $script:repoRoot "backends\\appimage\\lib\\appimage.ps1")

    function New-GpTestAppDir {
      param([string[]]$Files)
      $root = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-fontgap-" + [guid]::NewGuid().ToString("N"))
      foreach ($file in $Files) {
        $path = Join-Path $root $file
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
        Set-Content -Path $path -Value "x"
      }
      New-Item -ItemType Directory -Force -Path (Join-Path $root "usr") | Out-Null
      return $root
    }
  }

  It "warns when the AppImage bundles fontconfig or cairo but no font, pointing at the clean-host smoke" {
    $appDir = New-GpTestAppDir -Files @("usr/runtime/lib/libcairo.so.2", "usr/runtime/lib/libfontconfig.so.1", "usr/runtime/System/Library/Fonts/Helvetica.nfont/n019003l.pfb")
    try {
      $message = Get-GpAppImageFontGap -AppDirRoot $appDir
      $message | Should -Not -BeNullOrEmpty -Because "a Type 1 nfont is not a font the cairo backend finds through fontconfig"
      $message | Should -BeLike "*libcairo.so.2, libfontconfig.so.1*"
      $message | Should -BeLike "*fonts.bundle*"
      $message | Should -BeLike "*appimage-clean-smoke-image*fedora:42*"
    } finally {
      Remove-Item -Recurse -Force $appDir -ErrorAction SilentlyContinue
    }
  }

  It "stays quiet when fonts are bundled, a font file is staged, or the host's font libraries are used" {
    foreach ($case in @(
      @{ Files = @("usr/runtime/lib/libcairo.so.2"); Bundled = @([pscustomobject]@{ Name = "DejaVu" }); Because = "fonts.bundle is set" },
      @{ Files = @("usr/runtime/lib/libfontconfig.so.1", "usr/runtime/share/fonts/app/Sans.ttf"); Bundled = @(); Because = "a font file is staged" },
      @{ Files = @("usr/runtime/lib/libgnustep-gui.so.0.32"); Bundled = @(); Because = "fontconfig and cairo come from the host" }
    )) {
      $appDir = New-GpTestAppDir -Files $case.Files
      try {
        Get-GpAppImageFontGap -AppDirRoot $appDir -BundledFonts $case.Bundled | Should -BeNullOrEmpty -Because $case.Because
      } finally {
        Remove-Item -Recurse -Force $appDir -ErrorAction SilentlyContinue
      }
    }
  }
}
