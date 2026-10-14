Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Describe "Shared validation contract" {
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

    function Assert-GpMatch {
      param(
        [string]$Actual,
        [string]$Pattern,
        [string]$Message
      )

      if ($Actual -notmatch $Pattern) {
        throw "$Message Pattern: $Pattern Actual: $Actual"
      }
    }

    function New-GpSiblingManifest {
      param(
        [Parameter(Mandatory = $true)]
        [string]$BaseManifestPath,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Customize
      )

      $manifest = Get-GpJsonFile -Path $BaseManifestPath
      & $Customize $manifest

      $manifestDirectory = Split-Path -Parent $BaseManifestPath
      $tempManifestPath = Join-Path $manifestDirectory ("pester-validation-" + [guid]::NewGuid().ToString("N") + ".json")
      $manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $tempManifestPath -Encoding utf8
      return $tempManifestPath
    }

    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    $script:manifestPath = Join-Path $script:repoRoot "examples\\sample-gui\\package.manifest.json"

    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
  }

  It "accepts glob entries in validation.smoke.requiredPaths and logs matched paths" {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-validation-glob-" + [guid]::NewGuid().ToString("N"))
    $stageRoot = Join-Path $tempRoot "stage"
    $appPath = Join-Path $stageRoot "app\\SampleGNUstepApp.app\\SampleGNUstepApp.exe"
    $resourcePath = Join-Path $stageRoot "app\\SampleGNUstepApp.app\\Resources\\Info-gnustep.plist"
    $runtimeBinPath = Join-Path $stageRoot "runtime\\bin\\defaults.exe"
    $bundlePath = Join-Path $stageRoot "runtime\\lib\\GNUstep\\Bundles\\libgnustep-back-032.bundle\\libgnustep-back-032.dll"
    $metadataPath = Join-Path $stageRoot "metadata\\icons\\sample-icon.txt"
    $manifestPath = $null

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $appPath) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resourcePath) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $runtimeBinPath) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $bundlePath) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $metadataPath) | Out-Null
    Set-Content -Path $appPath -Value "fixture"
    Set-Content -Path $resourcePath -Value "fixture"
    Set-Content -Path $runtimeBinPath -Value "fixture"
    Set-Content -Path $bundlePath -Value "fixture"
    Set-Content -Path $metadataPath -Value "fixture"

    try {
      $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:manifestPath -Customize {
        param($manifest)
        $manifest["payload"]["stageRoot"] = $stageRoot
        $manifest["outputs"]["root"] = (Join-Path $tempRoot "dist")
        $manifest["outputs"]["packageRoot"] = (Join-Path $tempRoot "dist\\packages")
        $manifest["outputs"]["logRoot"] = (Join-Path $tempRoot "dist\\logs")
        $manifest["outputs"]["tempRoot"] = (Join-Path $tempRoot "dist\\tmp")
        $manifest["outputs"]["validationRoot"] = (Join-Path $tempRoot "dist\\validation")
        $manifest["validation"]["packageContract"] = @{
          requiredContent = @()
        }
        $manifest["validation"]["smoke"]["requiredPaths"] = @(
          "runtime/lib/GNUstep/Bundles/libgnustep-back-*.bundle/libgnustep-back-*.dll"
        )
      }

      $context = Get-GpManifestContext -Path $manifestPath
      $result = Invoke-GpSharedValidation -Context $context
      $logText = Get-Content -Raw -Path $result.LogPath

      Assert-GpTrue -Condition (Test-Path $result.LogPath) -Message "Shared validation should write a validation log."
      Assert-GpMatch -Actual $logText -Pattern "smoke:runtime/lib/GNUstep/Bundles/libgnustep-back-\*\.bundle/libgnustep-back-\*\.dll" -Message "The validation log should preserve the original glob pattern."
      Assert-GpMatch -Actual $logText -Pattern "MATCH.+libgnustep-back-032\.bundle.+libgnustep-back-032\.dll" -Message "The validation log should report the matched concrete path."
    } finally {
      if ($null -ne $manifestPath -and (Test-Path $manifestPath)) {
        Remove-Item -Force $manifestPath
      }
      if (Test-Path $tempRoot) {
        Remove-Item -Recurse -Force $tempRoot
      }
    }
  }

  It "fails glob validation when no required path matches" {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-validation-glob-miss-" + [guid]::NewGuid().ToString("N"))
    $stageRoot = Join-Path $tempRoot "stage"
    $appPath = Join-Path $stageRoot "app\\SampleGNUstepApp.app\\SampleGNUstepApp.exe"
    $resourcePath = Join-Path $stageRoot "app\\SampleGNUstepApp.app\\Resources\\Info-gnustep.plist"
    $runtimeBinPath = Join-Path $stageRoot "runtime\\bin\\defaults.exe"
    $metadataPath = Join-Path $stageRoot "metadata\\icons\\sample-icon.txt"
    $manifestPath = $null
    $threw = $false

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $appPath) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resourcePath) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $runtimeBinPath) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $metadataPath) | Out-Null
    Set-Content -Path $appPath -Value "fixture"
    Set-Content -Path $resourcePath -Value "fixture"
    Set-Content -Path $runtimeBinPath -Value "fixture"
    Set-Content -Path $metadataPath -Value "fixture"

    try {
      $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:manifestPath -Customize {
        param($manifest)
        $manifest["payload"]["stageRoot"] = $stageRoot
        $manifest["outputs"]["root"] = (Join-Path $tempRoot "dist")
        $manifest["outputs"]["packageRoot"] = (Join-Path $tempRoot "dist\\packages")
        $manifest["outputs"]["logRoot"] = (Join-Path $tempRoot "dist\\logs")
        $manifest["outputs"]["tempRoot"] = (Join-Path $tempRoot "dist\\tmp")
        $manifest["outputs"]["validationRoot"] = (Join-Path $tempRoot "dist\\validation")
        $manifest["validation"]["packageContract"] = @{
          requiredContent = @()
        }
        $manifest["validation"]["smoke"]["requiredPaths"] = @(
          "runtime/lib/GNUstep/Bundles/libgnustep-back-*.bundle/libgnustep-back-*.dll"
        )
      }

      $context = Get-GpManifestContext -Path $manifestPath
      try {
        Invoke-GpSharedValidation -Context $context | Out-Null
      } catch {
        $threw = $true
        Assert-GpMatch -Actual $_.Exception.Message -Pattern "Shared validation failed" -Message "Missing glob matches should fail shared validation."
      }

      Assert-GpTrue -Condition $threw -Message "Shared validation should fail when a required glob has no matches."
    } finally {
      if ($null -ne $manifestPath -and (Test-Path $manifestPath)) {
        Remove-Item -Force $manifestPath
      }
      if (Test-Path $tempRoot) {
        Remove-Item -Recurse -Force $tempRoot
      }
    }
  }

  It "treats native stderr output as diagnostic when the process exits successfully" {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-shell-command-" + [guid]::NewGuid().ToString("N"))
    $logPath = Join-Path $tempRoot "shell-command.log"
    $shellPath = (Get-Process -Id $PID).Path

    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    try {
      $result = Invoke-GpShellCommand `
        -Invocation ([pscustomobject]@{
          FilePath = $shellPath
          ArgumentList = @(
            "-NoProfile",
            "-Command",
            "[Console]::Out.WriteLine('stdout ok'); [Console]::Error.WriteLine('stderr warning'); exit 0"
          )
          ShellKind = "pwsh"
        }) `
        -WorkingDirectory $tempRoot `
        -LogPath $logPath
      $logText = Get-Content -Raw -Path $logPath

      Assert-GpEqual -Actual $result.ExitCode -Expected 0 -Message "Shell command execution should preserve a successful native exit code."
      Assert-GpMatch -Actual $logText -Pattern "stdout ok" -Message "Shell command logs should keep native stdout."
      Assert-GpMatch -Actual $logText -Pattern "stderr warning" -Message "Shell command logs should keep native stderr without treating it as fatal."
    } finally {
      if (Test-Path $tempRoot) {
        Remove-Item -Recurse -Force $tempRoot
      }
    }
  }

  It "preserves shell command arguments that contain spaces and separators" {
    if ($IsWindows) {
      return
    }

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-shell-arguments-" + [guid]::NewGuid().ToString("N"))
    $logPath = Join-Path $tempRoot "shell-command.log"
    $markerPath = Join-Path $tempRoot "marker.txt"
    $shellPath = Resolve-GpDefaultPosixShellProgram -Name "bash"

    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    try {
      $result = Invoke-GpShellCommand `
        -Invocation ([pscustomobject]@{
          FilePath = $shellPath
          ArgumentList = @(
            "-lc",
            "printf 'stdout ok\n'; printf 'marker ok\n' > marker.txt"
          )
          ShellKind = "bash"
        }) `
        -WorkingDirectory $tempRoot `
        -LogPath $logPath
      $logText = Get-Content -Raw -Path $logPath
      $markerText = Get-Content -Raw -Path $markerPath

      Assert-GpEqual -Actual $result.ExitCode -Expected 0 -Message "Shell command execution should preserve a successful native exit code."
      Assert-GpMatch -Actual $logText -Pattern "stdout ok" -Message "Shell command logs should include output from the full shell command string."
      Assert-GpEqual -Actual $markerText.Trim() -Expected "marker ok" -Message "Shell command execution should preserve semicolon-separated commands as one argument."
    } finally {
      if (Test-Path $tempRoot) {
        Remove-Item -Recurse -Force $tempRoot
      }
    }
  }

  It "uses system POSIX shells when PATH contains managed toolchain shims" {
    if ($IsWindows) {
      return
    }

    $oldPath = $env:PATH
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-shell-path-" + [guid]::NewGuid().ToString("N"))

    try {
      New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
      Set-Content -Path (Join-Path $tempRoot "bash") -Value "#!/bin/sh`nexit 42`n"
      $env:PATH = "$tempRoot$([System.IO.Path]::PathSeparator)$oldPath"

      $invocation = Get-GpShellInvocation -ShellConfig @{ kind = "bash" } -Command "printf ok"

      Assert-GpMatch -Actual $invocation.FilePath -Pattern "^/(usr/)?bin/bash$" -Message "Default bash invocation should use the system shell instead of a PATH shim."
    } finally {
      $env:PATH = $oldPath
      if (Test-Path $tempRoot) {
        Remove-Item -Recurse -Force $tempRoot
      }
    }
  }

  It "moves managed System Tools behind host tools for POSIX pipeline commands" {
    if ($IsWindows) {
      return
    }

    $oldPath = $env:PATH
    $oldRoot = $env:GP_GNUSTEP_CLI_ROOT
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-shell-tool-path-" + [guid]::NewGuid().ToString("N"))
    $managedRoot = Join-Path $tempRoot "gnustep-cli"
    $bin = Join-Path $managedRoot "bin"
    $tools = Join-Path $managedRoot "Tools"
    $systemTools = Join-Path $managedRoot "System/Tools"

    try {
      New-Item -ItemType Directory -Force -Path $bin, $tools, $systemTools | Out-Null
      $env:GP_GNUSTEP_CLI_ROOT = $managedRoot
      $env:PATH = "$systemTools$([System.IO.Path]::PathSeparator)$tools$([System.IO.Path]::PathSeparator)$bin$([System.IO.Path]::PathSeparator)$oldPath"

      $shellPath = Get-GpShellCommandPath -Invocation ([pscustomobject]@{ ShellKind = "bash" })

      Assert-GpMatch -Actual $shellPath -Pattern "$([regex]::Escape($oldPath))$([regex]::Escape([string][System.IO.Path]::PathSeparator))$([regex]::Escape($bin))$([regex]::Escape([string][System.IO.Path]::PathSeparator))$([regex]::Escape($tools))$([regex]::Escape([string][System.IO.Path]::PathSeparator))$([regex]::Escape($systemTools))$" -Message "Managed tool directories should move behind host tools for POSIX pipeline commands."
    } finally {
      $env:PATH = $oldPath
      $env:GP_GNUSTEP_CLI_ROOT = $oldRoot
      if (Test-Path $tempRoot) {
        Remove-Item -Recurse -Force $tempRoot
      }
    }
  }

  It "realizes packagedDefaults.defaultTheme into the launch contract" {
    $manifestPath = $null

    try {
      $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:manifestPath -Customize {
        param($manifest)
        $manifest["packagedDefaults"] = @{
          defaultTheme = "StageTheme"
        }
        $manifest["launch"]["env"] = @{
          GNUSTEP_PATHPREFIX_LIST = "{@runtimeRoot}"
        }
      }

      $context = Get-GpManifestContext -Path $manifestPath
      $launch = Get-GpLaunchContract -Context $context

      Assert-GpEqual -Actual $launch.Environment["GSTheme"]["value"] -Expected "StageTheme" -Message "Declarative packaged defaults should realize a default theme into the launch contract."
      Assert-GpEqual -Actual $launch.Environment["GSTheme"]["policy"] -Expected "ifUnset" -Message "Declarative packaged defaults should seed the theme only when unset."
    } finally {
      if ($null -ne $manifestPath -and (Test-Path $manifestPath)) {
        Remove-Item -Force $manifestPath
      }
    }
  }

  It "normalizes packagedDefaults.appDomain against package.id by default" {
    $manifestPath = $null

    try {
      $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:manifestPath -Customize {
        param($manifest)
        $manifest["packagedDefaults"]["appDomain"] = @{
          values = @{
            ExampleEnabled = $true
            ExampleFontSize = 12
            ExampleTitle = "Packaged sample"
          }
        }
      }

      $context = Get-GpManifestContext -Path $manifestPath
      $packagedDefaults = Get-GpPackagedDefaults -Manifest $context.Manifest

      Assert-GpEqual -Actual $packagedDefaults.AppDomain.Domain -Expected "com.example.SampleGNUstepApp" -Message "App-domain defaults should default to package.id when no explicit domain is declared."
      Assert-GpEqual -Actual @($packagedDefaults.AppDomain.Entries | ForEach-Object { $_.Type }) -Expected @("bool", "integer", "string") -Message "App-domain defaults should normalize scalar value types."
    } finally {
      if ($null -ne $manifestPath -and (Test-Path $manifestPath)) {
        Remove-Item -Force $manifestPath
      }
    }
  }

  It "rejects unsupported packagedDefaults.appDomain values and theme keys" {
    $manifestPath = $null

    try {
      $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:manifestPath -Customize {
        param($manifest)
        $manifest["packagedDefaults"]["appDomain"] = @{
          values = @{
            GSTheme = "WinUITheme"
            ExampleObject = @{
              nested = "value"
            }
          }
        }
      }

      $schemaIssues = @(Test-GpManifestSchema -Path $manifestPath)
      $context = Get-GpManifestContext -Path $manifestPath
      $issues = @(Test-GpManifest -Manifest $context.Manifest)
      $allIssues = @($schemaIssues + $issues)

      Assert-GpMatch -Actual ([string]::Join("`n", $allIssues)) -Pattern "packagedDefaults\.appDomain\.values" -Message "Invalid app-domain defaults should be rejected by schema or shared manifest validation."
      Assert-GpMatch -Actual ([string]::Join("`n", $allIssues)) -Pattern "GSTheme" -Message "GSTheme should remain a semantic packaged default rather than a generic app-domain key."
    } finally {
      if ($null -ne $manifestPath -and (Test-Path $manifestPath)) {
        Remove-Item -Force $manifestPath
      }
    }
  }

  It "fails shared validation when a semantic stage contract item is missing" {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-validation-contract-stage-" + [guid]::NewGuid().ToString("N"))
    $stageRoot = Join-Path $tempRoot "stage"
    $appPath = Join-Path $stageRoot "app\\SampleGNUstepApp.app\\SampleGNUstepApp.exe"
    $resourcePath = Join-Path $stageRoot "app\\SampleGNUstepApp.app\\Resources\\Info-gnustep.plist"
    $runtimeBinPath = Join-Path $stageRoot "runtime\\bin\\defaults.exe"
    $metadataPath = Join-Path $stageRoot "metadata\\icons\\sample-icon.txt"
    $manifestPath = $null
    $threw = $false

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $appPath) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resourcePath) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $runtimeBinPath) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $metadataPath) | Out-Null
    Set-Content -Path $appPath -Value "fixture"
    Set-Content -Path $resourcePath -Value "fixture"
    Set-Content -Path $runtimeBinPath -Value "fixture"
    Set-Content -Path $metadataPath -Value "fixture"

    try {
      $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:manifestPath -Customize {
        param($manifest)
        $manifest["payload"]["stageRoot"] = $stageRoot
        $manifest["outputs"]["root"] = (Join-Path $tempRoot "dist")
        $manifest["outputs"]["packageRoot"] = (Join-Path $tempRoot "dist\\packages")
        $manifest["outputs"]["logRoot"] = (Join-Path $tempRoot "dist\\logs")
        $manifest["outputs"]["tempRoot"] = (Join-Path $tempRoot "dist\\tmp")
        $manifest["outputs"]["validationRoot"] = (Join-Path $tempRoot "dist\\validation")
        $manifest["validation"]["packageContract"] = @{
          requiredContent = @(
            @{
              kind = "updater-helper"
            }
          )
        }
      }

      $context = Get-GpManifestContext -Path $manifestPath
      try {
        Invoke-GpSharedValidation -Context $context | Out-Null
      } catch {
        $threw = $true
        Assert-GpMatch -Actual $_.Exception.Message -Pattern "Shared validation failed" -Message "Missing semantic stage contract items should fail shared validation."
      }

      Assert-GpTrue -Condition $threw -Message "Shared validation should fail when semantic contract content is missing from stage."
    } finally {
      if ($null -ne $manifestPath -and (Test-Path $manifestPath)) {
        Remove-Item -Force $manifestPath
      }
      if (Test-Path $tempRoot) {
        Remove-Item -Recurse -Force $tempRoot
      }
    }
  }

  It "reports forbidden payload files by name or relative path and checks the size budget" {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-payload-policy-" + [guid]::NewGuid().ToString("N"))
    try {
      New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "runtime/lib") | Out-Null
      New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot "app") | Out-Null
      Set-Content -Path (Join-Path $tempRoot "runtime/lib/libgnustep-base.so.1.31") -Value ("x" * 1000) -NoNewline
      Set-Content -Path (Join-Path $tempRoot "runtime/lib/libavcodec.so.61") -Value ("x" * 3000) -NoNewline
      Set-Content -Path (Join-Path $tempRoot "runtime/lib/LIBX265.so.209") -Value ("x" * 100) -NoNewline
      Set-Content -Path (Join-Path $tempRoot "app/notes.a") -Value "x" -NoNewline

      $policy = [pscustomobject]@{
        ForbiddenFiles = [string[]]@("libavcodec*", "libx26*", "runtime/lib/*.a", "libMagick*")
        MaxPayloadBytes = [long]4000
      }
      $result = Test-GpPayloadPolicy -RootPath $tempRoot -Policy $policy
      $text = [string]::Join("`n", @($result.Lines))

      Assert-GpEqual -Actual @($result.Issues).Count -Expected 3 -Message "Two forbidden patterns and the size budget should be reported."
      Assert-GpMatch -Actual $text -Pattern "FORBIDDEN libavcodec\* -> runtime/lib/libavcodec\.so\.61" -Message "A name pattern should match the file name and report its relative path."
      Assert-GpMatch -Actual $text -Pattern "FORBIDDEN libx26\* -> runtime/lib/LIBX265\.so\.209" -Message "Name patterns should match without regard to case."
      Assert-GpMatch -Actual $text -Pattern "OK      forbidden:runtime/lib/\*\.a -> none" -Message "A path pattern should only match under its directory."
      Assert-GpMatch -Actual $text -Pattern "OVERSIZE payload is .* over the .*4000 bytes.* budget; largest files: runtime/lib/libavcodec\.so\.61" -Message "An oversize payload should name the budget and its largest files."

      $within = Test-GpPayloadPolicy -RootPath $tempRoot -Policy ([pscustomobject]@{ ForbiddenFiles = [string[]]@(); MaxPayloadBytes = [long]100000 })
      Assert-GpEqual -Actual @($within.Issues).Count -Expected 0 -Message "A payload within its budget should pass."

      if (-not $IsWindows) {
        New-Item -ItemType SymbolicLink -Path (Join-Path $tempRoot "runtime/lib/libgnustep-base.so") -Target "libgnustep-base.so.1.31" | Out-Null
        $exact = Test-GpPayloadPolicy -RootPath $tempRoot -Policy ([pscustomobject]@{ ForbiddenFiles = [string[]]@(); MaxPayloadBytes = [long]4101 })
        Assert-GpEqual -Actual @($exact.Issues).Count -Expected 0 -Message "Symbolic links should not count toward the payload size."
      }

      $none = Test-GpPayloadPolicy -RootPath $tempRoot -Policy ([pscustomobject]@{ ForbiddenFiles = [string[]]@(); MaxPayloadBytes = $null })
      Assert-GpEqual -Actual @($none.Lines).Count -Expected 0 -Message "No policy should mean no payload checks."
    } finally {
      if (Test-Path $tempRoot) {
        Remove-Item -Recurse -Force $tempRoot
      }
    }
  }

  It "fails shared validation on a forbidden library in the staged payload" {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-payload-policy-stage-" + [guid]::NewGuid().ToString("N"))
    $stageRoot = Join-Path $tempRoot "stage"
    $manifestPath = $null
    $threw = $false

    foreach ($relative in @(
      "app/SampleGNUstepApp.app/SampleGNUstepApp.exe",
      "app/SampleGNUstepApp.app/Resources/Info-gnustep.plist",
      "runtime/bin/defaults.exe",
      "runtime/bin/avcodec-61.dll",
      "metadata/icons/sample-icon.txt"
    )) {
      $path = Join-Path $stageRoot $relative
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
      Set-Content -Path $path -Value "fixture"
    }

    try {
      $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:manifestPath -Customize {
        param($manifest)
        $manifest["payload"]["stageRoot"] = $stageRoot
        $manifest["outputs"]["root"] = (Join-Path $tempRoot "dist")
        $manifest["outputs"]["packageRoot"] = (Join-Path $tempRoot "dist\\packages")
        $manifest["outputs"]["logRoot"] = (Join-Path $tempRoot "dist\\logs")
        $manifest["outputs"]["tempRoot"] = (Join-Path $tempRoot "dist\\tmp")
        $manifest["outputs"]["validationRoot"] = (Join-Path $tempRoot "dist\\validation")
        $manifest["validation"]["packageContract"] = @{
          forbiddenFiles = @("avcodec-*.dll", "libavcodec*")
        }
      }

      $context = Get-GpManifestContext -Path $manifestPath
      try {
        Invoke-GpSharedValidation -Context $context | Out-Null
      } catch {
        $threw = $true
        Assert-GpMatch -Actual $_.Exception.Message -Pattern "Shared validation failed" -Message "A forbidden staged library should fail shared validation."
        $logText = Get-Content -Raw -Path ([regex]::Match($_.Exception.Message, "See log: (.+)$").Groups[1].Value)
        Assert-GpMatch -Actual $logText -Pattern "FORBIDDEN avcodec-\*\.dll -> runtime/bin/avcodec-61\.dll" -Message "The validation log should name the forbidden file."
      }

      Assert-GpTrue -Condition $threw -Message "Shared validation should fail when the stage holds a forbidden library."
    } finally {
      if ($null -ne $manifestPath -and (Test-Path $manifestPath)) {
        Remove-Item -Force $manifestPath
      }
      if (Test-Path $tempRoot) {
        Remove-Item -Recurse -Force $tempRoot
      }
    }
  }

  It "reads a backend's artifact size budget and fails an artifact over it" {
    $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-artifact-budget-" + [guid]::NewGuid().ToString("N") + ".bin")
    try {
      Set-Content -Path $tempFile -Value ("x" * 2048) -NoNewline
      $manifest = @{ backends = @{ msi = @{ validation = @{ maxArtifactBytes = 1024 } }; appimage = @{ enabled = $true } } }

      Assert-GpEqual -Actual (Get-GpArtifactSizeBudget -Manifest $manifest -Backend "msi") -Expected 1024 -Message "The MSI budget should come from backends.msi.validation."
      Assert-GpTrue -Condition ($null -eq (Get-GpArtifactSizeBudget -Manifest $manifest -Backend "appimage")) -Message "A backend without a budget should have none."
      Assert-GpTrue -Condition ($null -eq (Assert-GpArtifactSizeBudget -Manifest $manifest -Backend "appimage" -ArtifactPath $tempFile)) -Message "No budget should mean no check."

      $message = $null
      try {
        Assert-GpArtifactSizeBudget -Manifest $manifest -Backend "msi" -ArtifactPath $tempFile | Out-Null
      } catch {
        $message = $_.Exception.Message
      }
      Assert-GpTrue -Condition ($null -ne $message) -Message "An artifact over its budget should fail."
      Assert-GpMatch -Actual $message -Pattern "msi artifact is .*2048 bytes.*maxArtifactBytes budget of .*1024 bytes" -Message "The failure should give the size and the budget."

      $manifest["backends"]["msi"]["validation"]["maxArtifactBytes"] = 4096
      Assert-GpMatch -Actual (Assert-GpArtifactSizeBudget -Manifest $manifest -Backend "msi" -ArtifactPath $tempFile) -Pattern "^OK      artifact size" -Message "An artifact within its budget should pass."
    } finally {
      if (Test-Path $tempFile) {
        Remove-Item -Force $tempFile
      }
    }
  }

  It "validates bundled-theme semantically against stage content" {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-validation-theme-stage-" + [guid]::NewGuid().ToString("N"))
    $stageRoot = Join-Path $tempRoot "stage"
    $appPath = Join-Path $stageRoot "app\\SampleGNUstepApp.app\\SampleGNUstepApp.exe"
    $resourcePath = Join-Path $stageRoot "app\\SampleGNUstepApp.app\\Resources\\Info-gnustep.plist"
    $runtimeBinPath = Join-Path $stageRoot "runtime\\bin\\defaults.exe"
    $themePath = Join-Path $stageRoot "runtime\\lib\\GNUstep\\Themes\\WinUITheme.theme"
    $metadataPath = Join-Path $stageRoot "metadata\\icons\\sample-icon.txt"
    $manifestPath = $null

    foreach ($dir in @(
      (Split-Path -Parent $appPath),
      (Split-Path -Parent $resourcePath),
      (Split-Path -Parent $runtimeBinPath),
      $themePath,
      (Split-Path -Parent $metadataPath)
    )) {
      New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -Path $appPath -Value "fixture"
    Set-Content -Path $resourcePath -Value "fixture"
    Set-Content -Path $runtimeBinPath -Value "fixture"
    Set-Content -Path (Join-Path $themePath "theme.txt") -Value "fixture theme"
    Set-Content -Path $metadataPath -Value "fixture"

    try {
      $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:manifestPath -Customize {
        param($manifest)
        $manifest["payload"]["stageRoot"] = $stageRoot
        $manifest["outputs"]["root"] = (Join-Path $tempRoot "dist")
        $manifest["outputs"]["packageRoot"] = (Join-Path $tempRoot "dist\\packages")
        $manifest["outputs"]["logRoot"] = (Join-Path $tempRoot "dist\\logs")
        $manifest["outputs"]["tempRoot"] = (Join-Path $tempRoot "dist\\tmp")
        $manifest["outputs"]["validationRoot"] = (Join-Path $tempRoot "dist\\validation")
        $manifest["validation"]["smoke"]["requiredPaths"] = @()
        $manifest["validation"]["packageContract"] = @{
          requiredContent = @(
            @{
              kind = "bundled-theme"
              name = "WinUITheme"
            }
          )
        }
      }

      $context = Get-GpManifestContext -Path $manifestPath
      $result = Invoke-GpSharedValidation -Context $context
      $logText = Get-Content -Raw -Path $result.LogPath

      Assert-GpMatch -Actual $logText -Pattern "validation\.packageContract\.requiredContent\[0\]" -Message "Bundled-theme stage validation should log the semantic assertion source."
      Assert-GpMatch -Actual $logText -Pattern "WinUITheme\.theme" -Message "Bundled-theme stage validation should log the concrete theme candidate path."
    } finally {
      if ($null -ne $manifestPath -and (Test-Path $manifestPath)) {
        Remove-Item -Force $manifestPath
      }
      if (Test-Path $tempRoot) {
        Remove-Item -Recurse -Force $tempRoot
      }
    }
  }

  It "accepts bundled-theme under the GNUstep System/Library runtime tree" {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-validation-theme-system-stage-" + [guid]::NewGuid().ToString("N"))
    $stageRoot = Join-Path $tempRoot "stage"
    $appPath = Join-Path $stageRoot "app\\SampleGNUstepApp.app\\SampleGNUstepApp.exe"
    $resourcePath = Join-Path $stageRoot "app\\SampleGNUstepApp.app\\Resources\\Info-gnustep.plist"
    $runtimeBinPath = Join-Path $stageRoot "runtime\\bin\\defaults.exe"
    $themePath = Join-Path $stageRoot "runtime\\System\\Library\\Themes\\Adwaita.theme"
    $metadataPath = Join-Path $stageRoot "metadata\\icons\\sample-icon.txt"
    $manifestPath = $null

    foreach ($dir in @(
      (Split-Path -Parent $appPath),
      (Split-Path -Parent $resourcePath),
      (Split-Path -Parent $runtimeBinPath),
      $themePath,
      (Split-Path -Parent $metadataPath)
    )) {
      New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -Path $appPath -Value "fixture"
    Set-Content -Path $resourcePath -Value "fixture"
    Set-Content -Path $runtimeBinPath -Value "fixture"
    Set-Content -Path (Join-Path $themePath "theme.txt") -Value "fixture theme"
    Set-Content -Path $metadataPath -Value "fixture"

    try {
      $manifestPath = New-GpSiblingManifest -BaseManifestPath $script:manifestPath -Customize {
        param($manifest)
        $manifest["payload"]["stageRoot"] = $stageRoot
        $manifest["outputs"]["root"] = (Join-Path $tempRoot "dist")
        $manifest["outputs"]["packageRoot"] = (Join-Path $tempRoot "dist\\packages")
        $manifest["outputs"]["logRoot"] = (Join-Path $tempRoot "dist\\logs")
        $manifest["outputs"]["tempRoot"] = (Join-Path $tempRoot "dist\\tmp")
        $manifest["outputs"]["validationRoot"] = (Join-Path $tempRoot "dist\\validation")
        $manifest["validation"]["smoke"]["requiredPaths"] = @()
        $manifest["validation"]["packageContract"] = @{
          requiredContent = @(
            @{
              kind = "bundled-theme"
              name = "Adwaita"
            }
          )
        }
      }

      $context = Get-GpManifestContext -Path $manifestPath
      $result = Invoke-GpSharedValidation -Context $context
      $logText = Get-Content -Raw -Path $result.LogPath

      Assert-GpMatch -Actual $logText -Pattern "validation\.packageContract\.requiredContent\[0\]" -Message "Bundled-theme System/Library validation should log the semantic assertion source."
      Assert-GpMatch -Actual $logText -Pattern "runtime[/\\]System[/\\]Library[/\\]Themes[/\\]Adwaita\.theme" -Message "Bundled-theme System/Library validation should log the GNUstep runtime tree candidate path."
    } finally {
      if ($null -ne $manifestPath -and (Test-Path $manifestPath)) {
        Remove-Item -Force $manifestPath
      }
      if (Test-Path $tempRoot) {
        Remove-Item -Recurse -Force $tempRoot
      }
    }
  }
}
