Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# The MSI runtime closure counted a DLL found anywhere in the install tree as
# present. Windows looks only in the app's folder, the importing file's
# folder, the working directory and PATH (which the launcher builds from
# launch.pathPrepend and runtime\bin), so a DLL left under Resources passed
# packaging and the installed app didn't start. These cases cross-build a tiny
# PE app and DLL with clang and lld-link (no CRT, no Windows needed) and run
# the closure analysis on install trees that put the DLL in different places.
Describe "MSI: DLLs on the app's search path" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
    . (Join-Path $script:repoRoot "backends\\msi\\lib\\msi.ps1")

    $script:canBuild = [bool]((Get-Command clang -ErrorAction SilentlyContinue) -and (Get-Command lld-link -ErrorAction SilentlyContinue))
    $script:workRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-msi-loader-" + [guid]::NewGuid().ToString("N"))
    $script:buildRoot = Join-Path $script:workRoot "build"
    New-Item -ItemType Directory -Force -Path $script:buildRoot | Out-Null
    if ($script:canBuild) {
      Set-Content -Path (Join-Path $script:buildRoot "private.c") -Value '__declspec(dllexport) int gp_private_answer(void) { return 42; }'
      Set-Content -Path (Join-Path $script:buildRoot "app.c") -Value @(
        '__declspec(dllimport) int gp_private_answer(void);'
        'int mainCRTStartup(void) { return gp_private_answer(); }'
      )
      $common = @("--target=x86_64-pc-windows-msvc", "-fuse-ld=lld", "-nostdlib")
      & clang @common -shared "-Wl,/noentry" -o (Join-Path $script:buildRoot "gpprivate.dll") (Join-Path $script:buildRoot "private.c")
      if ($LASTEXITCODE -ne 0) { throw "building gpprivate.dll failed" }
      & clang @common "-Wl,/subsystem:console" -o (Join-Path $script:buildRoot "Demo.exe") (Join-Path $script:buildRoot "app.c") (Join-Path $script:buildRoot "gpprivate.lib")
      if ($LASTEXITCODE -ne 0) { throw "building Demo.exe failed" }
    }
    # The closure reads imports with objdump. An objdump built for another
    # architecture (the arm64 Linux runner's) can't read an x86-64 PE, and
    # every case would pass with nothing checked.
    $script:canReadPe = $script:canBuild -and (@(Get-GpPeImportedDllNames -Path (Join-Path $script:buildRoot "Demo.exe")) -contains "gpprivate.dll")
    function Skip-GpUnlessPeReadable {
      if (-not $script:canReadPe) {
        Set-ItResult -Skipped -Because "this host's objdump can't read the cross-built x86-64 PE files"
        return $true
      }
      return $false
    }

    # An install tree with app/Demo.app/Demo.exe and gpprivate.dll at
    # $DllRelativeDir. Returns the analysis and its context and config.
    function Invoke-GpLoaderCase {
      param([string]$Name, [string]$DllRelativeDir, [string[]]$PathPrepend = @(), [switch]$Require)
      $root = Join-Path $script:workRoot $Name
      New-Item -ItemType Directory -Force -Path (Join-Path $root "app/Demo.app"), (Join-Path $root "runtime/bin"), (Join-Path $root $DllRelativeDir) | Out-Null
      Copy-Item (Join-Path $script:buildRoot "Demo.exe") (Join-Path $root "app/Demo.app/")
      Copy-Item (Join-Path $script:buildRoot "gpprivate.dll") (Join-Path $root $DllRelativeDir)
      $context = [pscustomobject]@{
        Manifest = @{ launch = @{ entryRelativePath = "app/Demo.app/Demo.exe"; workingDirectory = "app/Demo.app"; pathPrepend = $PathPrepend } }
      }
      $config = [pscustomobject]@{
        AppRootRelative = "app"
        RuntimeRootRelative = "runtime"
        MetadataRootRelative = "metadata"
        RuntimeSeedPaths = @()
        RuntimeSearchRoots = [string[]]@()
        RequireLoaderSearchPath = [bool]$Require
      }
      $analysis = Get-GpMsiRuntimeClosureAnalysis -Context $context -Config $config -InstallRoot $root -LogPath (Join-Path $script:workRoot "$Name.log")
      return [pscustomobject]@{ Root = $root; Config = $config; Analysis = $analysis; Log = (Join-Path $script:workRoot "$Name.log") }
    }
  }

  AfterAll {
    if ($script:workRoot -and (Test-Path $script:workRoot)) {
      Remove-Item -Recurse -Force $script:workRoot
    }
  }

  It "accepts the DLL in runtime\bin, which the launcher puts on PATH" -Skip:(-not ((Get-Command clang -ErrorAction SilentlyContinue) -and (Get-Command lld-link -ErrorAction SilentlyContinue))) {
    if (Skip-GpUnlessPeReadable) { return }
    $case = Invoke-GpLoaderCase -Name "runtime-bin" -DllRelativeDir "runtime/bin"
    @($case.Analysis.MissingDependencyNames).Count | Should -Be 0
    @($case.Analysis.OffSearchPathRecords).Count | Should -Be 0
  }

  It "accepts the DLL next to the app" -Skip:(-not ((Get-Command clang -ErrorAction SilentlyContinue) -and (Get-Command lld-link -ErrorAction SilentlyContinue))) {
    if (Skip-GpUnlessPeReadable) { return }
    $case = Invoke-GpLoaderCase -Name "beside" -DllRelativeDir "app/Demo.app"
    @($case.Analysis.OffSearchPathRecords).Count | Should -Be 0
  }

  It "accepts the DLL in a folder named in launch.pathPrepend, with tokens expanded" -Skip:(-not ((Get-Command clang -ErrorAction SilentlyContinue) -and (Get-Command lld-link -ErrorAction SilentlyContinue))) {
    if (Skip-GpUnlessPeReadable) { return }
    $case = Invoke-GpLoaderCase -Name "prepend" -DllRelativeDir "app/plugins/bin" -PathPrepend @("{@appRoot}/plugins/bin")
    @($case.Analysis.OffSearchPathRecords).Count | Should -Be 0
    @($case.Analysis.LoaderSearchDirectories) | Should -Contain ([System.IO.Path]::GetFullPath((Join-Path $case.Root "app/plugins/bin")))
  }

  It "warns about a DLL that is only under Resources" -Skip:(-not ((Get-Command clang -ErrorAction SilentlyContinue) -and (Get-Command lld-link -ErrorAction SilentlyContinue))) {
    if (Skip-GpUnlessPeReadable) { return }
    $case = Invoke-GpLoaderCase -Name "resources" -DllRelativeDir "app/Demo.app/Resources"
    @($case.Analysis.MissingDependencyNames).Count | Should -Be 0 -Because "it is in the install tree, which is all the old check asked"
    @($case.Analysis.OffSearchPathRecords).Count | Should -Be 1
    $lines = @(Assert-GpMsiLoaderSearchPath -Config $case.Config -Analysis $case.Analysis -LogPath $case.Log -WarningAction SilentlyContinue)
    $lines | Should -Be @("app/Demo.app/Demo.exe imports gpprivate.dll, which is only at app/Demo.app/Resources/gpprivate.dll: not in its own folder, the app's folder, the working directory or the launcher's PATH")
    Get-Content -Raw $case.Log | Should -BeLike "*warning only (set backends.msi.validation.requireLoaderSearchPath to fail)*"
  }

  It "fails on the same case with requireLoaderSearchPath" -Skip:(-not ((Get-Command clang -ErrorAction SilentlyContinue) -and (Get-Command lld-link -ErrorAction SilentlyContinue))) {
    if (Skip-GpUnlessPeReadable) { return }
    $case = Invoke-GpLoaderCase -Name "resources-strict" -DllRelativeDir "app/Demo.app/Resources" -Require
    { Assert-GpMsiLoaderSearchPath -Config $case.Config -Analysis $case.Analysis -LogPath $case.Log } | Should -Throw "*not on the app's DLL search path*gpprivate.dll*"
  }

  It "is in the schema as backends.msi.validation.requireLoaderSearchPath, and the AppImage one too" {
    $schema = Get-Content -Raw (Join-Path $script:repoRoot "schemas/gnustep-packager.schema.json") | ConvertFrom-Json
    $schema.properties.backends.properties.msi.properties.validation.properties.requireLoaderSearchPath.type | Should -Be "boolean"
    $schema.properties.backends.properties.appimage.properties.validation.properties.requireLoaderSearchPath.type | Should -Be "boolean"
  }
}
