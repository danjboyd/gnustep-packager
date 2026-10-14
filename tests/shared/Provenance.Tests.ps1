Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Describe "Release provenance" {
  BeforeAll {
    function Assert-GpEqual {
      param(
        [object]$Actual,
        [object]$Expected,
        [string]$Message
      )

      if ($Actual -is [System.Array] -or $Expected -is [System.Array]) {
        $actualJson = ConvertTo-Json @($Actual) -Compress
        $expectedJson = ConvertTo-Json @($Expected) -Compress
        if ($actualJson -ne $expectedJson) {
          throw "$Message Expected: $expectedJson Actual: $actualJson"
        }
        return
      }

      if ($Actual -ne $Expected) {
        throw "$Message Expected: $Expected Actual: $Actual"
      }
    }

    function Assert-GpTrue {
      param(
        [bool]$Condition,
        [string]$Message
      )

      if (-not $Condition) {
        throw $Message
      }
    }

    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")

    $script:buildId = "0123456789abcdef0123456789abcdef01234567"

    # A minimal ELF file: the header, one PT_NOTE program header, and a GNU
    # build-id note, in the given class (32 or 64 bits) and byte order.
    function New-GpTestElf {
      param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [int]$Bits = 64,
        [switch]$BigEndian
      )

      $bytes = [System.Collections.Generic.List[byte]]::new()
      $put = {
        param([long]$Value, [int]$Size)
        $raw = switch ($Size) {
          2 { [System.BitConverter]::GetBytes([uint16]$Value) }
          4 { [System.BitConverter]::GetBytes([uint32]$Value) }
          8 { [System.BitConverter]::GetBytes([uint64]$Value) }
        }
        if ($BigEndian) {
          [array]::Reverse($raw)
        }
        $bytes.AddRange([byte[]]$raw)
      }
      $word = if ($Bits -eq 64) { 8 } else { 4 }
      $headerSize = if ($Bits -eq 64) { 64 } else { 52 }
      $programHeaderSize = if ($Bits -eq 64) { 56 } else { 32 }
      $noteOffset = $headerSize + $programHeaderSize
      $descriptor = [byte[]]@(for ($i = 0; $i -lt $script:buildId.Length; $i += 2) { [Convert]::ToByte($script:buildId.Substring($i, 2), 16) })
      $noteSize = 12 + 4 + $descriptor.Length

      $bytes.AddRange([byte[]]@(0x7F, 0x45, 0x4C, 0x46, $(if ($Bits -eq 64) { 2 } else { 1 }), $(if ($BigEndian) { 2 } else { 1 }), 1, 0, 0, 0, 0, 0, 0, 0, 0, 0))
      & $put 3 2          # e_type: shared object
      & $put 62 2         # e_machine
      & $put 1 4          # e_version
      & $put 0 $word      # e_entry
      & $put $headerSize $word  # e_phoff
      & $put 0 $word      # e_shoff
      & $put 0 4          # e_flags
      & $put $headerSize 2
      & $put $programHeaderSize 2
      & $put 1 2          # e_phnum
      & $put 0 2
      & $put 0 2
      & $put 0 2

      if ($Bits -eq 64) {
        & $put 4 4; & $put 4 4
        & $put $noteOffset 8; & $put 0 8; & $put 0 8
        & $put $noteSize 8; & $put $noteSize 8; & $put 4 8
      } else {
        & $put 4 4; & $put $noteOffset 4; & $put 0 4; & $put 0 4
        & $put $noteSize 4; & $put $noteSize 4; & $put 4 4; & $put 4 4
      }

      & $put 4 4
      & $put $descriptor.Length 4
      & $put 3 4
      $bytes.AddRange([byte[]]@(0x47, 0x4E, 0x55, 0))
      $bytes.AddRange($descriptor)
      [System.IO.File]::WriteAllBytes($Path, $bytes.ToArray())
    }
  }

  It "reads the GNU build ID of 64-bit little-endian and 32-bit big-endian ELF files" {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-provenance-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    try {
      New-GpTestElf -Path (Join-Path $root "elf64.so")
      New-GpTestElf -Path (Join-Path $root "elf32be.so") -Bits 32 -BigEndian
      Set-Content -Path (Join-Path $root "not-elf.dll") -Value "MZ not an ELF file"

      Assert-GpEqual -Actual (Get-GpElfBuildId -Path (Join-Path $root "elf64.so")) -Expected $script:buildId -Message "The 64-bit little-endian build ID should be read."
      Assert-GpEqual -Actual (Get-GpElfBuildId -Path (Join-Path $root "elf32be.so")) -Expected $script:buildId -Message "The 32-bit big-endian build ID should be read."
      Assert-GpEqual -Actual (Get-GpElfBuildId -Path (Join-Path $root "not-elf.dll")) -Expected $null -Message "A file that isn't ELF has no build ID."
    } finally {
      Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
    }
  }

  It "records the entry and the GNUstep libraries with paths relative to the payload" {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-provenance-" + [guid]::NewGuid().ToString("N"))
    $libraryDirectory = Join-Path $root "usr/runtime/lib"
    $entryDirectory = Join-Path $root "usr/app/MyApp.app"
    New-Item -ItemType Directory -Force -Path $libraryDirectory, $entryDirectory | Out-Null
    try {
      New-GpTestElf -Path (Join-Path $libraryDirectory "libgnustep-base.so.1.31")
      New-GpTestElf -Path (Join-Path $libraryDirectory "libobjc.so.4.6")
      Set-Content -Path (Join-Path $libraryDirectory "libgnustep-base-1_31.dll") -Value "a Windows build of the same library"
      Set-Content -Path (Join-Path $libraryDirectory "libz.so.1") -Value "not a GNUstep library"
      New-GpTestElf -Path (Join-Path $entryDirectory "MyApp")
      if (-not $IsWindows) {
        New-Item -ItemType SymbolicLink -Path (Join-Path $libraryDirectory "libgnustep-base.so") -Target "libgnustep-base.so.1.31" | Out-Null
      }

      $files = @(Get-GpPayloadProvenanceFiles -PayloadRoot $root -LibraryPatterns @("libgnustep-*", "libobjc*") -EntryPath (Join-Path $entryDirectory "MyApp"))

      Assert-GpEqual -Actual @($files | ForEach-Object { "$($_.role):$($_.path)" }) -Expected @(
        "entry:usr/app/MyApp.app/MyApp",
        "library:usr/runtime/lib/libgnustep-base-1_31.dll",
        "library:usr/runtime/lib/libgnustep-base.so.1.31",
        "library:usr/runtime/lib/libobjc.so.4.6"
      ) -Message "The entry and matching libraries should be listed once each, without symbolic links or other libraries."
      Assert-GpEqual -Actual $files[2].elfBuildId -Expected $script:buildId -Message "An ELF library should carry its build ID."
      Assert-GpEqual -Actual $files[1].elfBuildId -Expected $null -Message "A non-ELF library has no build ID."
      Assert-GpEqual -Actual $files[2].sha256 -Expected (Get-GpFileSha256 -Path (Join-Path $libraryDirectory "libgnustep-base.so.1.31")) -Message "Each file should carry its SHA-256."
    } finally {
      Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
    }
  }

  It "lists the GNUstep runtime libraries by default and can be turned off" {
    $manifest = Get-GpDefaultManifest
    $settings = Get-GpProvenanceSettings -Context ([pscustomobject]@{ Manifest = $manifest })
    Assert-GpTrue -Condition $settings.Enabled -Message "Provenance should be on by default."
    foreach ($name in @("libgnustep-base.so.1.31", "libgnustep-gui-0_32.dll", "libobjc.so.4.6", "libdispatch.so", "dispatch.dll")) {
      Assert-GpTrue -Condition (@($settings.Libraries | Where-Object { $name -like $_ }).Count -gt 0) -Message "$name should be recorded by default."
    }

    $manifest["provenance"]["enabled"] = $false
    $settings = Get-GpProvenanceSettings -Context ([pscustomobject]@{ Manifest = $manifest })
    Assert-GpTrue -Condition (-not $settings.Enabled) -Message "provenance.enabled = false should turn it off."
  }
}
