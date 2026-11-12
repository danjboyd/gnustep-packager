Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Describe "MSI fonts.bundle" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
    . (Join-Path $script:repoRoot "backends\\msi\\lib\\msi.ps1")

    function New-GpFontTestRoot {
      $root = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-msifonts-" + [guid]::NewGuid().ToString("N"))
      $source = New-Item -ItemType Directory -Force -Path (Join-Path $root "source")
      $install = New-Item -ItemType Directory -Force -Path (Join-Path $root "install")
      Set-Content -Path (Join-Path $source "DejaVuSans.ttf") -Value "regular"
      Set-Content -Path (Join-Path $source "DejaVuSans-Bold.ttf") -Value "bold"
      Set-Content -Path (Join-Path $source "LICENSE") -Value "Bitstream Vera license"
      return [pscustomobject]@{
        Root = $root
        Source = $source.FullName
        Install = $install.FullName
        Log = Join-Path $root "msi.log"
      }
    }

    function New-GpFontTestConfig {
      param([psobject]$Paths, [string]$LicenseFile)
      return [pscustomobject]@{
        RuntimeRootRelative = "runtime"
        MetadataRootRelative = "metadata"
        BundledFonts = @(
          [pscustomobject]@{
            Name = "DejaVu"
            DirectoryName = (Convert-GpMsiFontDirectoryName -Value "DejaVu")
            Files = [string[]]@((Join-Path $Paths.Source "DejaVuSans.ttf"), (Join-Path $Paths.Source "DejaVuSans-Bold.ttf"))
            LicenseFile = $(if ($LicenseFile) { $LicenseFile } else { Join-Path $Paths.Source "LICENSE" })
            License = "Bitstream-Vera"
            Homepage = "https://dejavu-fonts.github.io/"
          }
        )
      }
    }
  }

  It "copies the fonts and license and writes a relocatable fonts.conf with a per-user cache" {
    $paths = New-GpFontTestRoot
    try {
      $notices = @(Write-GpMsiBundledFonts -Config (New-GpFontTestConfig -Paths $paths) -InstallRoot $paths.Install -LogPath $paths.Log)

      Join-Path $paths.Install "runtime/share/fonts/dejavu/DejaVuSans.ttf" | Should -Exist
      Join-Path $paths.Install "runtime/share/fonts/dejavu/DejaVuSans-Bold.ttf" | Should -Exist
      Join-Path $paths.Install "metadata/licenses/fonts/dejavu.txt" | Should -Exist

      $conf = Get-Content -Raw (Join-Path $paths.Install "runtime/etc/fonts/fonts.conf")
      $conf | Should -BeLike '*<dir>WINDOWSFONTDIR</dir>*' -Because "with no staged config, the Windows fonts must stay visible"
      $conf | Should -BeLike '*<dir prefix="relative">../../share/fonts</dir>*'
      $conf | Should -BeLike '*<cachedir>LOCAL_APPDATA_FONTCONFIG_CACHE</cachedir>*' -Because "the install directory isn't writable"
      $conf | Should -Not -BeLike '*fonts.app.conf*'
      $conf | Should -Not -BeLike ('*' + $paths.Root + '*') -Because "the config must not name a build path"
      ([xml]$conf).fontconfig | Should -Not -BeNullOrEmpty

      $notices.Count | Should -Be 1
      $notices[0].Name | Should -Be "DejaVu (font)"
      $notices[0].License | Should -Be "Bitstream-Vera"
      $notices[0].StageRelativePath | Should -Be "metadata/licenses/fonts/dejavu.txt"
    } finally {
      Remove-Item -Recurse -Force $paths.Root -ErrorAction SilentlyContinue
    }
  }

  It "keeps a staged fonts.conf as fonts.app.conf and includes it first" {
    $paths = New-GpFontTestRoot
    try {
      $confDir = New-Item -ItemType Directory -Force -Path (Join-Path $paths.Install "runtime/etc/fonts")
      Set-Content -Path (Join-Path $confDir "fonts.conf") -Value "<fontconfig><dir>WINDOWSFONTDIR</dir></fontconfig>"

      Write-GpMsiBundledFonts -Config (New-GpFontTestConfig -Paths $paths) -InstallRoot $paths.Install -LogPath $paths.Log | Out-Null

      Get-Content -Raw (Join-Path $confDir "fonts.app.conf") | Should -BeLike "*WINDOWSFONTDIR*"
      $conf = Get-Content -Raw (Join-Path $confDir "fonts.conf")
      $conf | Should -BeLike '*<include ignore_missing="no">fonts.app.conf</include>*'
      $conf | Should -Not -BeLike '*<dir>WINDOWSFONTDIR</dir>*' -Because "the app's own config decides the system directories"
      $conf.IndexOf("fonts.app.conf") | Should -BeLessThan $conf.IndexOf("share/fonts")
    } finally {
      Remove-Item -Recurse -Force $paths.Root -ErrorAction SilentlyContinue
    }
  }

  It "does nothing without fonts.bundle and fails on a missing license" {
    $paths = New-GpFontTestRoot
    try {
      $empty = [pscustomobject]@{ RuntimeRootRelative = "runtime"; MetadataRootRelative = "metadata"; BundledFonts = @() }
      @(Write-GpMsiBundledFonts -Config $empty -InstallRoot $paths.Install -LogPath $paths.Log).Count | Should -Be 0
      Join-Path $paths.Install "runtime/etc/fonts/fonts.conf" | Should -Not -Exist

      $missing = New-GpFontTestConfig -Paths $paths -LicenseFile (Join-Path $paths.Source "NOPE")
      { Write-GpMsiBundledFonts -Config $missing -InstallRoot $paths.Install -LogPath $paths.Log } | Should -Throw "*license file not found*"
    } finally {
      Remove-Item -Recurse -Force $paths.Root -ErrorAction SilentlyContinue
    }
  }

  It "is in the schema for backends.msi" {
    $schema = Get-Content -Raw (Join-Path $script:repoRoot "schemas/gnustep-packager.schema.json") | ConvertFrom-Json
    $item = $schema.properties.backends.properties.msi.properties.fonts.properties.bundle.items
    @($item.required) | Should -Be @("name", "files", "licenseFile")
  }
}
