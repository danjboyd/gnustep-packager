Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Parsing and path resolution behind the DMG's library-references check. The
# check itself runs otool on macOS (tests/macos/DmgLibraryReferences.Tests.ps1).
Describe "DMG library references: otool parsing and resolution" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
    . (Join-Path $script:repoRoot "backends\\dmg\\lib\\dmg.ps1")
  }

  It "reads otool -L for a universal file once, skipping its own install name and noting weak links" {
    $lines = @(
      "/x/Demo.app/Contents/Frameworks/libTrellis.dylib (architecture x86_64):"
      "`t@rpath/libTrellis.dylib (compatibility version 1.0.0, current version 1.0.0)"
      "`t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1345.0.0)"
      "`t/opt/homebrew/lib/libz.1.dylib (compatibility version 1.0.0, current version 1.3.1, weak)"
      "/x/Demo.app/Contents/Frameworks/libTrellis.dylib (architecture arm64):"
      "`t@rpath/libTrellis.dylib (compatibility version 1.0.0, current version 1.0.0)"
      "`t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1345.0.0)"
      "`t/opt/homebrew/lib/libz.1.dylib (compatibility version 1.0.0, current version 1.3.1, weak)"
    )
    $references = @(ConvertFrom-GpDmgOtoolLibraries -Lines $lines -InstallName "@rpath/libTrellis.dylib")
    @($references.Path) | Should -Be @("/usr/lib/libSystem.B.dylib", "/opt/homebrew/lib/libz.1.dylib")
    @($references.Weak) | Should -Be @($false, $true)
  }

  It "reads LC_RPATH entries from otool -l" {
    $lines = @(
      "Load command 12"
      "          cmd LC_RPATH"
      "      cmdsize 48"
      "         path @executable_path/../Frameworks (offset 12)"
      "Load command 13"
      "          cmd LC_LOAD_DYLIB"
      "      cmdsize 56"
      "         name /usr/lib/libSystem.B.dylib (offset 24)"
      "Load command 14"
      "          cmd LC_RPATH"
      "      cmdsize 40"
      "         path /Users/runner/work/app/build (offset 12)"
    )
    @(ConvertFrom-GpDmgOtoolRpaths -Lines $lines) | Should -Be @("@executable_path/../Frameworks", "/Users/runner/work/app/build")
  }

  It "reads the Mach-O filetype from otool -h, with or without the caps column" {
    ConvertFrom-GpDmgOtoolFileType -Lines @(
      "/v/Demo.app/Contents/MacOS/Demo (architecture arm64):"
      "Mach header"
      "      magic  cputype cpusubtype  caps    filetype ncmds sizeofcmds      flags"
      " 0xfeedfacf 16777228          0  0x00           2    17       1056 0x00200085"
    ) | Should -Be 2
    ConvertFrom-GpDmgOtoolFileType -Lines @(
      "Mach header"
      "      magic cputype cpusubtype filetype ncmds sizeofcmds      flags"
      " 0xfeedfacf 16777223          3        6    14       1384 0x00100085"
    ) | Should -Be 6
    ConvertFrom-GpDmgOtoolFileType -Lines @("not a Mach-O file") | Should -BeNullOrEmpty
  }

  It "expands @rpath, @executable_path and @loader_path the way dyld does" {
    $exe = "/v/Demo.app/Contents/MacOS"
    $loader = "/v/Demo.app/Contents/Frameworks"
    @(Get-GpDmgMachOReferenceCandidates -Reference "@rpath/libTrellis.dylib" -LoaderDirectory $loader -ExecutableDirectory $exe -Rpaths @("@executable_path/../Frameworks", "@loader_path")) |
      Should -Be @("/v/Demo.app/Contents/MacOS/../Frameworks/libTrellis.dylib", "/v/Demo.app/Contents/Frameworks/libTrellis.dylib")
    @(Get-GpDmgMachOReferenceCandidates -Reference "@loader_path/libA.dylib" -LoaderDirectory $loader -ExecutableDirectory $exe -Rpaths @()) |
      Should -Be @("/v/Demo.app/Contents/Frameworks/libA.dylib")
    @(Get-GpDmgMachOReferenceCandidates -Reference "/Users/runner/build/libTrellis.dylib" -LoaderDirectory $loader -ExecutableDirectory $exe -Rpaths @()) |
      Should -Be @("/Users/runner/build/libTrellis.dylib")
    @(Get-GpDmgMachOReferenceCandidates -Reference "@rpath/libX.dylib" -LoaderDirectory $loader -ExecutableDirectory $exe -Rpaths @()).Count | Should -Be 0
  }

  It "is in the schema as backends.dmg.validation.requireBundledDependencies" {
    $schema = Get-Content -Raw (Join-Path $script:repoRoot "schemas/gnustep-packager.schema.json") | ConvertFrom-Json
    $schema.properties.backends.properties.dmg.properties.validation.properties.requireBundledDependencies.type | Should -Be "boolean"
  }
}
