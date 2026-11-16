Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# An app that links its own library, built in the app's tree and not part of
# GNUstep (AIManager's Trellis, for example), must ship it inside the AppImage
# and find it there. These cases build a tiny shared library and a program that
# links it, lay them out as a staged AppImage would, and run the backend's
# runtime-closure validation on the result.
Describe "AppImage: a private library built in the app's tree" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
    . (Join-Path $script:repoRoot "backends\\appimage\\lib\\appimage.ps1")

    $script:cc = (Get-Command cc -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    $script:workRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-privlib-" + [guid]::NewGuid().ToString("N"))
    $script:buildRoot = Join-Path $script:workRoot "build"
    New-Item -ItemType Directory -Force -Path $script:buildRoot | Out-Null
    Set-Content -Path (Join-Path $script:buildRoot "private.c") -Value 'int gp_private_answer(void) { return 42; }'
    Set-Content -Path (Join-Path $script:buildRoot "app.c") -Value @(
      '#include <stdio.h>'
      'int gp_private_answer(void);'
      'int main(void) { printf("answer=%d\n", gp_private_answer()); return 0; }'
    )

    $script:config = [pscustomobject]@{
      Validation = [pscustomobject]@{
        RuntimeClosure = "strict"
        AllowedSystemLibraries = [string[]]@()
        AllowedExternalRunpaths = [string[]]@()
      }
    }

    # Builds the library and the app with the given RUNPATH into a fresh
    # expanded AppImage root: the app in usr/app/Demo.app, the library in
    # usr/<LibraryDir>. Returns the root and the app's path.
    function New-GpPrivateLibraryRoot {
      param([string]$Name, [string]$LibraryDir, [string]$Runpath, [switch]$OmitLibrary, [string]$AppRunLibraryPath)
      $root = Join-Path $script:workRoot $Name
      $appDir = Join-Path $root "usr/app/Demo.app"
      $libDir = Join-Path $root ("usr/" + $LibraryDir)
      New-Item -ItemType Directory -Force -Path $appDir, $libDir | Out-Null
      $built = Join-Path $script:buildRoot "libgpprivate.so"
      & $script:cc -shared -fPIC -o $built (Join-Path $script:buildRoot "private.c")
      if ($LASTEXITCODE -ne 0) { throw "building libgpprivate.so failed" }
      $app = Join-Path $appDir "Demo"
      $linkArgs = @("-o", $app, (Join-Path $script:buildRoot "app.c"), "-L$($script:buildRoot)", "-lgpprivate")
      if ($Runpath) { $linkArgs += "-Wl,--enable-new-dtags,-rpath,$Runpath" }
      & $script:cc @linkArgs
      if ($LASTEXITCODE -ne 0) { throw "building Demo failed" }
      if (-not $OmitLibrary) {
        Copy-Item $built (Join-Path $libDir "libgpprivate.so")
      }
      # The lines of a generated AppRun that the loader check reads.
      if ($PSBoundParameters.ContainsKey("AppRunLibraryPath")) {
        Set-Content -Path (Join-Path $root "AppRun") -Value @(
          '#!/bin/sh'
          'APPDIR="${APPDIR:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)}"'
          'USR="${APPDIR}/usr"'
          'RUNTIME_ROOT="${USR}/runtime"'
          'ENTRY_PATH="${USR}/app/Demo.app/Demo"'
          ('export LD_LIBRARY_PATH="{0}${{GP_HOST_LD_LIBRARY_PATH:+:${{GP_HOST_LD_LIBRARY_PATH}}}}"' -f $AppRunLibraryPath)
        )
      }
      return [pscustomobject]@{ Root = $root; App = $app; Log = (Join-Path $script:workRoot "$Name.log") }
    }
  }

  AfterAll {
    if ($script:workRoot -and (Test-Path $script:workRoot)) {
      Remove-Item -Recurse -Force $script:workRoot
    }
  }

  It 'passes and runs when the library is in runtime/lib and the app''s RUNPATH is $ORIGIN-relative' -Skip:(-not (Get-Command cc -ErrorAction SilentlyContinue)) {
    $case = New-GpPrivateLibraryRoot -Name "origin" -LibraryDir "runtime/lib" -Runpath '$ORIGIN/../../runtime/lib'

    $result = Invoke-GpAppImageRuntimeClosureValidation -Config $script:config -ExpandedRoot $case.Root -LogPath $case.Log
    $result.CheckedFileCount | Should -Be 2 -Because "the app and the library are both ELF files"
    @($result.LoaderPathIssues).Count | Should -Be 0

    # Proof it works without help: no LD_LIBRARY_PATH, and the build directory
    # (where the library was linked from) moved out of the way.
    $output = & env -u LD_LIBRARY_PATH $case.App
    $LASTEXITCODE | Should -Be 0
    $output | Should -Be "answer=42"
  }

  It 'passes when the library sits next to the app with RUNPATH $ORIGIN' -Skip:(-not (Get-Command cc -ErrorAction SilentlyContinue)) {
    $case = New-GpPrivateLibraryRoot -Name "beside" -LibraryDir "app/Demo.app" -Runpath '$ORIGIN'
    { Invoke-GpAppImageRuntimeClosureValidation -Config $script:config -ExpandedRoot $case.Root -LogPath $case.Log } | Should -Not -Throw
    (& env -u LD_LIBRARY_PATH $case.App) | Should -Be "answer=42"
  }

  It 'fails when the app''s RUNPATH points back into the build tree' -Skip:(-not (Get-Command cc -ErrorAction SilentlyContinue)) {
    $case = New-GpPrivateLibraryRoot -Name "buildpath" -LibraryDir "runtime/lib" -Runpath $script:buildRoot
    { Invoke-GpAppImageRuntimeClosureValidation -Config $script:config -ExpandedRoot $case.Root -LogPath $case.Log } | Should -Throw "*runtime-closure validation failed*"
    Get-Content -Raw $case.Log | Should -BeLike "*escaped the AppDir via RUNPATH/RPATH*"
  }

  It "fails when the library wasn't staged" -Skip:(-not (Get-Command cc -ErrorAction SilentlyContinue)) {
    $case = New-GpPrivateLibraryRoot -Name "missing" -LibraryDir "runtime/lib" -Runpath '$ORIGIN/../../runtime/lib' -OmitLibrary
    { Invoke-GpAppImageRuntimeClosureValidation -Config $script:config -ExpandedRoot $case.Root -LogPath $case.Log } | Should -Throw "*runtime-closure validation failed*"
    Get-Content -Raw $case.Log | Should -BeLike "*unresolved dependency*libgpprivate.so*"
  }

  # Validation's ldd pass searches every directory in the AppDir that holds an
  # ELF file, so it finds a library the app itself can't.
  It 'warns when the library is in runtime/lib but nothing puts it on the app''s search path' -Skip:(-not (Get-Command cc -ErrorAction SilentlyContinue)) {
    $case = New-GpPrivateLibraryRoot -Name "unreachable" -LibraryDir "runtime/lib" -Runpath "" -AppRunLibraryPath '${RUNTIME_ROOT}/System/Library/Libraries'
    $result = Invoke-GpAppImageRuntimeClosureValidation -Config $script:config -ExpandedRoot $case.Root -LogPath $case.Log -WarningAction SilentlyContinue
    @($result.LoaderPathIssues).Count | Should -Be 1
    $result.LoaderPathIssues[0] | Should -BeLike "usr/app/Demo.app/Demo needs libgpprivate.so, which is in the AppDir but not on its runtime search path*"
    Get-Content -Raw $case.Log | Should -BeLike "*warning only (set backends.appimage.validation.requireLoaderSearchPath to fail)*"

    # The app really can't start, which is what the check predicts.
    & env -u LD_LIBRARY_PATH $case.App 2>$null
    $LASTEXITCODE | Should -Not -Be 0
  }

  It 'fails on the same case with requireLoaderSearchPath' -Skip:(-not (Get-Command cc -ErrorAction SilentlyContinue)) {
    $case = New-GpPrivateLibraryRoot -Name "unreachable-strict" -LibraryDir "runtime/lib" -Runpath "" -AppRunLibraryPath '${RUNTIME_ROOT}/System/Library/Libraries'
    $strict = [pscustomobject]@{
      Validation = [pscustomobject]@{
        RuntimeClosure = "strict"
        AllowedSystemLibraries = [string[]]@()
        AllowedExternalRunpaths = [string[]]@()
        RequireLoaderSearchPath = $true
      }
    }
    { Invoke-GpAppImageRuntimeClosureValidation -Config $strict -ExpandedRoot $case.Root -LogPath $case.Log } | Should -Throw "*runtime-closure validation failed*"
    Get-Content -Raw $case.Log | Should -BeLike "*Library not on the runtime search path: usr/app/Demo.app/Demo needs libgpprivate.so*"
  }

  It 'passes with no RUNPATH when AppRun''s LD_LIBRARY_PATH covers runtime/lib' -Skip:(-not (Get-Command cc -ErrorAction SilentlyContinue)) {
    $case = New-GpPrivateLibraryRoot -Name "apprun-path" -LibraryDir "runtime/lib" -Runpath "" -AppRunLibraryPath '${RUNTIME_ROOT}/lib:${RUNTIME_ROOT}/System/Library/Libraries'
    $result = Invoke-GpAppImageRuntimeClosureValidation -Config $script:config -ExpandedRoot $case.Root -LogPath $case.Log
    @($result.LoaderPathIssues).Count | Should -Be 0
    (& env ("LD_LIBRARY_PATH=" + (Join-Path $case.Root "usr/runtime/lib")) $case.App) | Should -Be "answer=42"
  }

  It 'reads the last AppRun LD_LIBRARY_PATH entry, before the host''s appended value' -Skip:(-not (Get-Command cc -ErrorAction SilentlyContinue)) {
    $case = New-GpPrivateLibraryRoot -Name "apprun-last" -LibraryDir "runtime/System/Library/Libraries" -Runpath "" -AppRunLibraryPath '${RUNTIME_ROOT}/lib:${RUNTIME_ROOT}/System/Library/Libraries'
    $settings = Get-GpAppImageAppRunLoaderSettings -ExpandedRoot $case.Root
    @($settings.LibraryPath) | Should -Be @((Join-Path $case.Root "usr/runtime/lib"), (Join-Path $case.Root "usr/runtime/System/Library/Libraries"))
    $settings.EntryPath | Should -Be (Join-Path $case.Root "usr/app/Demo.app/Demo")
    $result = Invoke-GpAppImageRuntimeClosureValidation -Config $script:config -ExpandedRoot $case.Root -LogPath $case.Log
    @($result.LoaderPathIssues).Count | Should -Be 0
  }
}
