Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# An app bundle that links its own dylib, built in the app's tree (AIManager's
# Trellis, for example). The DMG's library-references check must accept the
# dylib in Contents/Frameworks found through @rpath, and flag one referenced by
# its build path, which only works on the build Mac.
Describe "DMG: library references of an app's own dylib" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
    . (Join-Path $script:repoRoot "backends\\dmg\\lib\\dmg.ps1")

    $script:workRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-dmg-libref-" + [guid]::NewGuid().ToString("N"))
    $script:buildRoot = Join-Path $script:workRoot "build"
    New-Item -ItemType Directory -Force -Path $script:buildRoot | Out-Null
    Set-Content -Path (Join-Path $script:buildRoot "private.c") -Value 'int gp_private_answer(void) { return 42; }'
    Set-Content -Path (Join-Path $script:buildRoot "app.c") -Value @(
      '#include <stdio.h>'
      'int gp_private_answer(void);'
      'int main(void) { printf("answer=%d\n", gp_private_answer()); return 0; }'
    )

    # Builds Demo.app. With -Bundled the dylib's install name is @rpath/...,
    # it sits in Contents/Frameworks, and the executable has
    # LC_RPATH @executable_path/../Frameworks. Without it the dylib keeps its
    # build path as its install name and stays in the build directory.
    function New-GpDemoApp {
      param([string]$Name, [switch]$Bundled)
      $app = Join-Path $script:workRoot "$Name/Demo.app"
      $macos = Join-Path $app "Contents/MacOS"
      $frameworks = Join-Path $app "Contents/Frameworks"
      New-Item -ItemType Directory -Force -Path $macos, $frameworks | Out-Null
      $libDir = Join-Path $script:buildRoot $Name
      New-Item -ItemType Directory -Force -Path $libDir | Out-Null
      $dylib = Join-Path $libDir "libgpprivate.dylib"
      $installName = if ($Bundled) { "@rpath/libgpprivate.dylib" } else { $dylib }
      & xcrun clang -dynamiclib -install_name $installName -o $dylib (Join-Path $script:buildRoot "private.c")
      if ($LASTEXITCODE -ne 0) { throw "building libgpprivate.dylib failed" }
      $exe = Join-Path $macos "Demo"
      $linkArgs = @("-o", $exe, (Join-Path $script:buildRoot "app.c"), $dylib)
      if ($Bundled) { $linkArgs += @("-Wl,-rpath,@executable_path/../Frameworks") }
      & xcrun clang @linkArgs
      if ($LASTEXITCODE -ne 0) { throw "building Demo failed" }
      if ($Bundled) {
        Copy-Item $dylib $frameworks
      }
      return [pscustomobject]@{ App = $app; Exe = $exe; Dylib = $dylib }
    }
  }

  AfterAll {
    if ($script:workRoot -and (Test-Path $script:workRoot)) {
      Remove-Item -Recurse -Force $script:workRoot
    }
  }

  It "accepts a dylib in Contents/Frameworks found through @rpath, and the app runs from the bundle" {
    $demo = New-GpDemoApp -Name "bundled" -Bundled
    Remove-Item -Force $demo.Dylib
    $report = Get-GpDmgMachODependencyReport -AppPath $demo.App -ExecutablePath $demo.Exe
    @($report.Issues).Count | Should -Be 0 -Because ([string]::Join("; ", @($report.Issues)))
    $report.MachOFileCount | Should -Be 2
    $report.BundledReferenceCount | Should -Be 1
    (& $demo.Exe) | Should -Be "answer=42"
  }

  It "flags a dylib referenced by its build path, even though it runs on the build Mac" {
    $demo = New-GpDemoApp -Name "buildpath"
    (& $demo.Exe) | Should -Be "answer=42" -Because "the build path exists here, which is why a smoke launch can't catch this"
    $report = Get-GpDmgMachODependencyReport -AppPath $demo.App -ExecutablePath $demo.Exe
    @($report.Issues).Count | Should -Be 1
    $report.Issues[0] | Should -BeLike "Contents/MacOS/Demo loads */buildpath/libgpprivate.dylib, which is outside the bundle and the system"
  }

  It "flags an @rpath reference that no rpath resolves inside the bundle" {
    $demo = New-GpDemoApp -Name "norpath" -Bundled
    & install_name_tool -delete_rpath "@executable_path/../Frameworks" $demo.Exe
    $report = Get-GpDmgMachODependencyReport -AppPath $demo.App -ExecutablePath $demo.Exe
    @($report.Issues) | Should -BeLike "*@rpath/libgpprivate.dylib, which doesn't resolve inside the bundle"
  }

  # A helper tool in the bundle is its own main executable: dyld resolves its
  # @rpath only through its own LC_RPATH entries, not the app's, and
  # @executable_path is the helper's folder.
  It "checks a helper executable's @rpath against its own run paths, not the app's" {
    $demo = New-GpDemoApp -Name "helper" -Bundled
    Remove-Item -Force $demo.Dylib
    $resources = Join-Path $demo.App "Contents/Resources"
    New-Item -ItemType Directory -Force -Path $resources | Out-Null
    $bundledDylib = Join-Path $demo.App "Contents/Frameworks/libgpprivate.dylib"
    $helper = Join-Path $resources "gphelper"
    & xcrun clang -o $helper (Join-Path $script:buildRoot "app.c") $bundledDylib
    if ($LASTEXITCODE -ne 0) { throw "building gphelper failed" }

    # No run path of its own: the app's @executable_path/../Frameworks doesn't
    # apply to it, and dyld can't load it.
    $output = & $helper 2>&1
    $LASTEXITCODE | Should -Not -Be 0 -Because "dyld should not find @rpath/libgpprivate.dylib for the helper ($output)"
    $report = Get-GpDmgMachODependencyReport -AppPath $demo.App -ExecutablePath $demo.Exe
    @($report.Issues) | Should -Be @("Contents/Resources/gphelper loads @rpath/libgpprivate.dylib, which doesn't resolve inside the bundle")

    # Its own run path, relative to its own folder: it loads, and passes. It's
    # linked fresh rather than patched with install_name_tool: on Apple
    # Silicon the kernel keeps the old signature for a file changed in place,
    # and kills the re-signed binary.
    Remove-Item -Force $helper
    & xcrun clang -o $helper (Join-Path $script:buildRoot "app.c") $bundledDylib "-Wl,-rpath,@executable_path/../Frameworks"
    if ($LASTEXITCODE -ne 0) { throw "building gphelper with a run path failed" }
    $output = & $helper 2>&1
    $output | Should -Be "answer=42" -Because "exit code $LASTEXITCODE"
    $report = Get-GpDmgMachODependencyReport -AppPath $demo.App -ExecutablePath $demo.Exe
    @($report.Issues).Count | Should -Be 0 -Because ([string]::Join("; ", @($report.Issues)))
  }
}
