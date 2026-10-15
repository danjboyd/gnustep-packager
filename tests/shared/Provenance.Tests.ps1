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
        [switch]$BigEndian,
        # The PT_NOTE segment's alignment; with 8, the descriptor follows the
        # 12-byte header and "GNU\0" at offset 16, with no padding.
        [int]$NoteAlign = 4
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
        & $put $noteSize 8; & $put $noteSize 8; & $put $NoteAlign 8
      } else {
        & $put 4 4; & $put $noteOffset 4; & $put 0 4; & $put 0 4
        & $put $noteSize 4; & $put $noteSize 4; & $put 4 4; & $put $NoteAlign 4
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
      New-GpTestElf -Path (Join-Path $root "elf64-align8.so") -NoteAlign 8
      Set-Content -Path (Join-Path $root "not-elf.dll") -Value "MZ not an ELF file"

      Assert-GpEqual -Actual (Get-GpElfBuildId -Path (Join-Path $root "elf64.so")) -Expected $script:buildId -Message "The 64-bit little-endian build ID should be read."
      Assert-GpEqual -Actual (Get-GpElfBuildId -Path (Join-Path $root "elf32be.so")) -Expected $script:buildId -Message "The 32-bit big-endian build ID should be read."
      Assert-GpEqual -Actual (Get-GpElfBuildId -Path (Join-Path $root "elf64-align8.so")) -Expected $script:buildId -Message "A build ID in an 8-byte-aligned note segment should be read."
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

  It "records a checkout's commit, and whether a tracked file changed" {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
      Set-ItResult -Skipped -Because "git is not available"
      return
    }

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-provenance-git-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    try {
      & git -C $root init -q
      Set-Content -Path (Join-Path $root "one.txt") -Value "one"
      Set-Content -Path (Join-Path $root "two.txt") -Value "two"
      & git -C $root add one.txt two.txt
      & git -C $root -c user.name=test -c user.email=test@example.invalid commit -q -m fixture
      $commit = (& git -C $root rev-parse HEAD).Trim()

      $clean = Get-GpSourceRevision -Path $root
      Assert-GpEqual -Actual $clean["commit"] -Expected $commit -Message "The commit should be recorded."
      Assert-GpEqual -Actual $clean["dirty"] -Expected $false -Message "A clean checkout is not dirty."

      # One changed file: a single status line, which must still count.
      Add-Content -Path (Join-Path $root "one.txt") -Value "changed"
      Assert-GpEqual -Actual (Get-GpSourceRevision -Path $root)["dirty"] -Expected $true -Message "One changed tracked file makes the checkout dirty."

      Add-Content -Path (Join-Path $root "two.txt") -Value "changed"
      Assert-GpEqual -Actual (Get-GpSourceRevision -Path $root)["dirty"] -Expected $true -Message "Two changed tracked files make the checkout dirty."
      Assert-GpEqual -Actual (Get-GpSourceRevision -Path ([System.IO.Path]::GetTempPath())) -Expected $null -Message "Outside a checkout there's no revision."
    } finally {
      Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
    }
  }

  It "checks a staged payload against the pinned toolchain's lock and build IDs" {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-toolchain-pin-" + [guid]::NewGuid().ToString("N"))
    $stage = Join-Path $root "stage"
    $libraryDirectory = Join-Path $stage "runtime/System/Library/Libraries"
    New-Item -ItemType Directory -Force -Path $libraryDirectory | Out-Null
    try {
      New-GpTestElf -Path (Join-Path $libraryDirectory "libgnustep-base.so.1.31.1")
      $lockPath = Join-Path $root "gnustep-toolchain.lock.json"
      Set-Content -Path $lockPath -Value '{"schema_version":1,"kind":"custom-toolchain-lock","name":"fixture"}' -NoNewline
      $provenancePath = Join-Path $root "gnustep-toolchain-provenance.json"
      $writeProvenance = {
        param([string]$BuildId, [string]$LockSha256)
        [ordered]@{
          kind = "custom-gnustep-toolchain-provenance"
          schema_version = 1
          name = "fixture-toolchain"
          prefix = "/opt/private/build/prefix"
          lock = [ordered]@{ path = "/home/builder/gnustep-toolchain.lock.json"; sha256 = $LockSha256 }
          components = @([ordered]@{ name = "libs-base"; resolved_commit = "1111111111111111111111111111111111111111" })
          elf_files = [ordered]@{
            "System/Library/Libraries/libgnustep-base.so.1.31.1" = [ordered]@{ sha256 = ("0" * 64); build_id = $BuildId }
            "Tools/gdnc" = [ordered]@{ sha256 = ("1" * 64); build_id = $null }
          }
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $provenancePath
      }
      $context = [pscustomobject]@{
        Manifest = @{
          toolchain = @{ provenanceFile = $provenancePath; lockFile = $lockPath }
          provenance = @{ libraries = @("libgnustep-*") }
        }
        ManifestRoot = $root
      }

      & $writeProvenance $script:buildId (Get-GpFileSha256 -Path $lockPath)
      $result = Test-GpToolchainPin -Context $context -PayloadRoot $stage
      Assert-GpEqual -Actual @($result.Issues).Count -Expected 0 -Message "A payload from the pinned toolchain should pass. Issues: $([string]::Join('; ', @($result.Issues)))"
      $summary = Get-GpToolchainProvenanceSummary -Context $context
      Assert-GpEqual -Actual $summary["name"] -Expected "fixture-toolchain" -Message "The release provenance should name the toolchain."
      Assert-GpEqual -Actual $summary["components"][0]["resolvedCommit"] -Expected "1111111111111111111111111111111111111111" -Message "The release provenance should carry the component commits."
      Assert-GpTrue -Condition (-not (($summary | ConvertTo-Json -Depth 6).Contains("/opt/private") -or ($summary | ConvertTo-Json -Depth 6).Contains("/home/builder"))) -Message "The release provenance should leave out the toolchain's paths."

      & $writeProvenance ("f" * 40) (Get-GpFileSha256 -Path $lockPath)
      $issues = [string]::Join("`n", @((Test-GpToolchainPin -Context $context -PayloadRoot $stage).Issues))
      Assert-GpTrue -Condition ($issues -match "runtime/System/Library/Libraries/libgnustep-base\.so\.1\.31\.1 has build ID $($script:buildId), which toolchain fixture-toolchain did not build") -Message "A library from another GNUstep should fail, naming it. Issues: $issues"

      & $writeProvenance $script:buildId ("a" * 64)
      $issues = [string]::Join("`n", @((Test-GpToolchainPin -Context $context -PayloadRoot $stage).Issues))
      Assert-GpTrue -Condition ($issues -match "built from a different lock") -Message "A changed lock should fail. Issues: $issues"

      $context.Manifest["toolchain"]["provenanceFile"] = (Join-Path $root "missing.json")
      $issues = [string]::Join("`n", @((Test-GpToolchainPin -Context $context -PayloadRoot $stage).Issues))
      Assert-GpTrue -Condition ($issues -match "toolchain provenance file was not found") -Message "A missing provenance file should fail. Issues: $issues"

      $context.Manifest["toolchain"].Remove("provenanceFile")
      $issues = [string]::Join("`n", @((Test-GpToolchainPin -Context $context -PayloadRoot $stage).Issues))
      Assert-GpTrue -Condition ($issues -match "No toolchain provenance file is set") -Message "A toolchain section without a provenance file should say so. Issues: $issues"

      $context.Manifest.Remove("toolchain")
      Assert-GpEqual -Actual @((Test-GpToolchainPin -Context $context -PayloadRoot $stage).Issues).Count -Expected 0 -Message "Without a toolchain section nothing is checked."
    } finally {
      Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
    }
  }

  It "fails shared validation for a payload built with a different GNUstep" {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-toolchain-validate-" + [guid]::NewGuid().ToString("N"))
    $stage = Join-Path $root "stage"
    New-Item -ItemType Directory -Force -Path (Join-Path $stage "runtime/lib") | Out-Null
    $baseManifestPath = Join-Path $script:repoRoot "examples/sample-linux/package.manifest.json"
    $manifestPath = Join-Path (Split-Path -Parent $baseManifestPath) ("pester-toolchain-" + [guid]::NewGuid().ToString("N") + ".json")
    try {
      New-GpTestElf -Path (Join-Path $stage "runtime/lib/libobjc.so.4.6")
      $provenancePath = Join-Path $root "gnustep-toolchain-provenance.json"
      [ordered]@{
        kind = "custom-gnustep-toolchain-provenance"
        schema_version = 1
        name = "other-toolchain"
        lock = [ordered]@{ sha256 = ("0" * 64) }
        components = @()
        elf_files = [ordered]@{ "lib/libobjc.so.4.6" = [ordered]@{ sha256 = ("0" * 64); build_id = ("e" * 40) } }
      } | ConvertTo-Json -Depth 8 | Set-Content -Path $provenancePath

      $manifest = Get-GpJsonFile -Path $baseManifestPath
      $manifest["payload"]["stageRoot"] = $stage
      foreach ($key in @("root", "packageRoot", "logRoot", "tempRoot", "validationRoot")) {
        $manifest["outputs"][$key] = (Join-Path $root ("dist-" + $key))
      }
      $manifest["validation"]["smoke"]["requiredPaths"] = @()
      $manifest["validation"].Remove("packageContract")
      $manifest["toolchain"] = @{ provenanceFile = $provenancePath }
      $manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $manifestPath -Encoding utf8

      $context = Get-GpManifestContext -Path $manifestPath
      $message = $null
      try {
        Invoke-GpSharedValidation -Context $context | Out-Null
      } catch {
        $message = $_.Exception.Message
      }
      Assert-GpTrue -Condition ($null -ne $message) -Message "Shared validation should fail for a library the pinned toolchain didn't build."
      $log = Get-Content -Raw -Path (Get-ChildItem -Path (Join-Path $root "dist-logRoot") -Recurse -Filter *.log | Select-Object -First 1).FullName
      Assert-GpTrue -Condition ($log -match "\[toolchain\]" -and $log -match "runtime/lib/libobjc\.so\.4\.6 has build ID") -Message "The validation log should name the library. Log: $log"
    } finally {
      Remove-Item -Force -ErrorAction SilentlyContinue $manifestPath
      Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
    }
  }

  It "refuses a file outside the payload rather than publish its path" {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-provenance-outside-" + [guid]::NewGuid().ToString("N"))
    $payload = Join-Path $root "payload"
    New-Item -ItemType Directory -Force -Path $payload | Out-Null
    try {
      $outside = Join-Path $root "MyApp"
      New-GpTestElf -Path $outside
      $failure = $null
      try {
        Get-GpPayloadProvenanceFiles -PayloadRoot $payload -EntryPath $outside | Out-Null
      } catch {
        $failure = $_.Exception.Message
      }
      Assert-GpTrue -Condition ($failure -like "*is not inside the payload root*") -Message "An entry outside the payload should stop provenance. Got: $failure"
    } finally {
      Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
    }
  }

  It "hashes the artifact and the other files the build publishes" {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-provenance-doc-" + [guid]::NewGuid().ToString("N"))
    $payload = Join-Path $root "payload"
    New-Item -ItemType Directory -Force -Path $payload | Out-Null
    try {
      $artifactPath = Join-Path $root "MyApp-1.0.0-win64.msi"
      $zipPath = Join-Path $root "MyApp-1.0.0-win64-portable.zip"
      Set-Content -Path $artifactPath -Value "msi"
      Set-Content -Path $zipPath -Value "zip"
      $manifest = Get-GpDefaultManifest
      $manifest["package"] = @{ id = "com.example.myapp"; name = "MyApp"; version = "1.0.0" }
      $context = [pscustomobject]@{ Manifest = $manifest; ManifestRoot = $root; ToolRoot = $root }

      $path = Write-GpProvenanceDocument -Context $context -Backend "msi" -ArtifactPath $artifactPath -PayloadRoot $payload -RelatedArtifactPaths @($zipPath, (Join-Path $root "missing.zip"))
      $document = Get-Content -Raw -Path $path | ConvertFrom-Json
      Assert-GpEqual -Actual @($document.relatedArtifacts).Count -Expected 1 -Message "Only related files that exist should be listed."
      Assert-GpEqual -Actual $document.relatedArtifacts[0].name -Expected "MyApp-1.0.0-win64-portable.zip" -Message "The portable ZIP should be named."
      Assert-GpEqual -Actual $document.relatedArtifacts[0].sha256 -Expected (Get-GpFileSha256 -Path $zipPath) -Message "The portable ZIP should be hashed."

      $path = Write-GpProvenanceDocument -Context $context -Backend "appimage" -ArtifactPath $artifactPath -PayloadRoot $payload
      Assert-GpEqual -Actual @((Get-Content -Raw -Path $path | ConvertFrom-Json).relatedArtifacts).Count -Expected 0 -Message "Without related files the list is empty."
    } finally {
      Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
    }
  }

  It "lists the GNUstep runtime libraries by default and can be turned off" {
    $manifest = Get-GpDefaultManifest
    $settings = Get-GpProvenanceSettings -Context ([pscustomobject]@{ Manifest = $manifest })
    Assert-GpTrue -Condition $settings.Enabled -Message "Provenance should be on by default."
    foreach ($name in @("libgnustep-base.so.1.31", "libgnustep-gui-0_32.dll", "libobjc.so.4.6", "libdispatch.so", "dispatch.dll", "libBlocksRuntime.so")) {
      Assert-GpTrue -Condition (@($settings.Libraries | Where-Object { $name -like $_ }).Count -gt 0) -Message "$name should be recorded by default."
    }

    $manifest["provenance"]["enabled"] = $false
    $settings = Get-GpProvenanceSettings -Context ([pscustomobject]@{ Manifest = $manifest })
    Assert-GpTrue -Condition (-not $settings.Enabled) -Message "provenance.enabled = false should turn it off."
  }
}
