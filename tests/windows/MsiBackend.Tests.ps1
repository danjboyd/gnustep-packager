Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Describe "MSI backend" {
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

    function Assert-GpFalse {
      param(
        [bool]$Condition,
        [string]$Message
      )

      if ($Condition) {
        throw $Message
      }
    }

    function New-GpSiblingManifest {
      param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Customize
      )

      $manifest = Get-GpJsonFile -Path $script:manifestPath
      & $Customize $manifest

      $manifestDirectory = Split-Path -Parent $script:manifestPath
      $tempManifestPath = Join-Path $manifestDirectory ("pester-msi-" + [guid]::NewGuid().ToString("N") + ".json")
      $manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $tempManifestPath -Encoding utf8
      return $tempManifestPath
    }

    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    $script:manifestPath = Join-Path $script:repoRoot "examples\\sample-gui\\package.manifest.json"
    $script:toolScript = Join-Path $script:repoRoot "scripts\\gnustep-packager.ps1"

    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
    . (Join-Path $script:repoRoot "backends\\msi\\lib\\msi.ps1")

    & $script:toolScript -Command build -Manifest $script:manifestPath
    & $script:toolScript -Command stage -Manifest $script:manifestPath

    $script:transformContext = Get-GpManifestContext -Path $script:manifestPath
    $script:transformConfig = Get-GpMsiConfig -Context $script:transformContext
    $script:transformWorkPaths = Get-GpMsiWorkPaths -Context $script:transformContext
    $script:transformLogPath = Join-Path $script:transformConfig.OutputPaths.LogRoot "pester-msi-transform.log"
    $script:transform = Prepare-GpMsiInstallTree -Context $script:transformContext -Config $script:transformConfig -WorkPaths $script:transformWorkPaths -LogPath $script:transformLogPath
  }

  Context "Manifest resolution" {
    It "applies defaults and honors package version override" {
      $context = Get-GpManifestContext -Path $script:manifestPath -PackageVersion "2.5.7-rc1"

      Assert-GpEqual -Actual $context.PackageVersionOverride -Expected "2.5.7-rc1" -Message "Version override should be preserved."
      Assert-GpEqual -Actual $context.Manifest["package"]["version"] -Expected "2.5.7-rc1" -Message "Resolved manifest should use the overridden version."
      Assert-GpEqual -Actual $context.Manifest["backends"]["msi"]["portableArtifactNamePattern"] -Expected "{name}-{version}-win64-portable.zip" -Message "MSI portable artifact default should be present."
      Assert-GpEqual -Actual @($context.Manifest["profiles"]) -Expected @("gnustep-gui") -Message "Resolved manifest should preserve requested built-in profiles."
      Assert-GpEqual -Actual @(Get-GpComplianceEntries -Manifest $context.Manifest).Count -Expected 2 -Message "Resolved manifest should surface compliance notice entries."
    }

    It "defaults the smoke stay-alive period to five seconds" {
      $context = Get-GpManifestContext -Path $script:manifestPath
      $plan = Get-GpValidationPlan -Context $context

      Assert-GpEqual -Actual $plan.StayAliveSeconds -Expected 5 -Message "The packaged app should have to stay running for five seconds by default."
    }

    It "fails a smoke launch whose app exits soon after it starts" {
      $quick = Start-Process cmd.exe -ArgumentList @("/c", "ping -n 2 127.0.0.1 >nul & exit 3") -PassThru -WindowStyle Hidden
      $failed = $false
      try {
        Wait-GpMsiSmokeAppAlive -Processes @($quick) -Seconds 4 -AppPath "quick.exe"
      } catch {
        $failed = $_.Exception.Message -like "*exited within 4 seconds*0x00000003*"
      }
      Assert-GpTrue -Condition $failed -Message "An app that exits within the stay-alive period should fail the smoke launch with its exit code."

      $steady = Start-Process cmd.exe -ArgumentList @("/c", "ping -n 11 127.0.0.1 >nul") -PassThru -WindowStyle Hidden
      try {
        Wait-GpMsiSmokeAppAlive -Processes @($steady) -Seconds 2 -AppPath "steady.exe"
      } finally {
        Stop-Process -Id $steady.Id -Force -ErrorAction SilentlyContinue
      }
    }

    It "keeps the build toolchain off the smoke launch PATH" {
      $hostPath = @(
        "C:\Windows\system32",
        "D:\gnustep-cli\clang64\bin",
        "D:\gnustep-cli\usr\bin",
        "C:\msys64\clang64\bin",
        "C:\msys64\usr\bin",
        "C:\clang64\bin",
        "C:\tools\mingw64\bin",
        "C:\Program Files\Git\cmd",
        "C:\Windows"
      ) -join ";"

      $cleanPath = Get-GpMsiCleanSmokePath -Path $hostPath -ToolchainRoots @("D:\gnustep-cli", "C:\msys64", "C:\clang64")

      Assert-GpEqual -Actual $cleanPath -Expected "C:\Windows\system32;C:\Program Files\Git\cmd;C:\Windows" -Message "Toolchain directories should be removed from the smoke launch PATH."
    }

    It "resolves enabled backends from the manifest" {
      $context = Get-GpManifestContext -Path $script:manifestPath

      Assert-GpEqual -Actual @(Get-GpEnabledBackends -Manifest $context.Manifest) -Expected @("msi") -Message "Enabled backends should match the sample manifest."
    }

    It "applies built-in profile defaults before manifest overrides" {
      $context = Get-GpManifestContext -Path $script:manifestPath

      Assert-GpEqual -Actual @($context.Manifest["launch"]["pathPrepend"]) -Expected @("runtime/bin") -Message "GUI profile should provide common runtime PATH defaults."
      Assert-GpEqual -Actual $context.Manifest["launch"]["env"]["GNUSTEP_PATHPREFIX_LIST"] -Expected "{@runtimeRoot}" -Message "GUI profile should provide the common GNUstep runtime root token."
      Assert-GpEqual -Actual @($context.Manifest["payload"]["runtimeSeedPaths"]) -Expected @("runtime/bin/defaults.exe") -Message "The Windows fixture manifest should declare its runtime seed paths."
    }

    It "normalizes launch environment policies for backend rendering" {
      $launch = Get-GpLaunchContract -Context $script:transformContext

      Assert-GpEqual -Actual $launch.Environment["GSTheme"]["value"] -Expected "WinUXTheme" -Message "Launch contract should preserve environment values."
      Assert-GpEqual -Actual $launch.Environment["GSTheme"]["policy"] -Expected "ifUnset" -Message "Launch contract should preserve conditional environment policies."
      Assert-GpEqual -Actual $launch.Environment["GNUSTEP_PATHPREFIX_LIST"]["policy"] -Expected "override" -Message "Plain string launch environment entries should normalize to override."
    }

    It "normalizes packaged app-domain defaults for backend rendering" {
      $packagedDefaults = Get-GpPackagedDefaults -Manifest $script:transformContext.Manifest

      Assert-GpEqual -Actual $packagedDefaults.AppDomain.Domain -Expected "com.example.SampleGNUstepApp" -Message "App-domain defaults should default to package.id when no explicit domain is declared."
      Assert-GpEqual -Actual @($packagedDefaults.AppDomain.Entries | ForEach-Object { $_.Key }) -Expected @("SampleFirstRunComplete", "SamplePreferredWidth", "SampleWelcomeText") -Message "App-domain defaults should preserve declared keys."
      Assert-GpEqual -Actual @($packagedDefaults.AppDomain.Entries | ForEach-Object { $_.Type }) -Expected @("bool", "integer", "string") -Message "App-domain defaults should normalize scalar value types."
    }
  }

  Context "Versioning and transform" {
    It "normalizes semantic versions for MSI upgrade semantics" {
      Assert-GpEqual -Actual (Normalize-GpMsiVersion -Version "1.2.3-rc1+7") -Expected "1.2.3.1" -Message "MSI version normalization should keep the first four numeric groups."
    }

    It "builds artifact names from the overridden package version" {
      $context = Get-GpManifestContext -Path $script:manifestPath -PackageVersion "3.4.5"
      $config = Get-GpMsiConfig -Context $context

      Assert-GpEqual -Actual $config.ArtifactPlan.ArtifactName -Expected "SampleGNUstepApp-3.4.5-win64.msi" -Message "MSI artifact name should track the overridden version."
      Assert-GpEqual -Actual $config.PortablePlan.ArtifactName -Expected "SampleGNUstepApp-3.4.5-win64-portable.zip" -Message "Portable artifact name should track the overridden version."
      Assert-GpEqual -Actual $config.MsiVersion -Expected "3.4.5.0" -Message "MSI numeric version should be normalized from the overridden version."
    }

    It "computes the per-user install root used by validation" {
      $context = Get-GpManifestContext -Path $script:manifestPath
      $config = Get-GpMsiConfig -Context $context

      Assert-GpMatch -Actual (Get-GpMsiInstallPathGuess -Config $config) -Pattern ([regex]::Escape((Join-Path $env:LOCALAPPDATA "SampleGNUstepApp"))) -Message "Validation install path should point to LocalAppData for per-user installs."
    }

    It "copies the staged payload into the install tree" {
      Assert-GpTrue -Condition (Test-Path (Join-Path $script:transform.InstallRoot "app\\SampleGNUstepApp.app\\SampleGNUstepApp.exe")) -Message "Transformed install tree should contain the app executable."
      Assert-GpTrue -Condition (Test-Path (Join-Path $script:transform.InstallRoot "runtime\\bin\\defaults.exe")) -Message "Transformed install tree should contain the staged runtime seed."
      Assert-GpTrue -Condition (Test-Path (Join-Path $script:transform.InstallRoot "metadata\\icons\\sample-icon.txt")) -Message "Transformed install tree should contain staged metadata."
      Assert-GpTrue -Condition (Test-Path (Join-Path $script:transform.InstallRoot "metadata\\licenses\\GNUstep-runtime.txt")) -Message "Transformed install tree should contain staged license metadata."
    }

    It "generates launcher output and config" {
      Assert-GpTrue -Condition (Test-Path $script:transform.LauncherPath) -Message "Launcher executable should be generated."
      Assert-GpTrue -Condition (Test-Path $script:transform.LauncherConfigPath) -Message "Launcher config should be generated."
    }

    It "writes the launch contract into the generated launcher config" {
      $configText = Get-Content -Raw -Path $script:transform.LauncherConfigPath

      Assert-GpMatch -Actual $configText -Pattern "entryRelativePath=app/SampleGNUstepApp.app/SampleGNUstepApp.exe" -Message "Launcher config should contain the entry path."
      Assert-GpMatch -Actual $configText -Pattern "pathPrepend=runtime/bin" -Message "Launcher config should contain runtime PATH additions."
      Assert-GpMatch -Actual $configText -Pattern "env=GNUSTEP_PATHPREFIX_LIST=\{@runtimeRoot\}" -Message "Launcher config should preserve runtime token expansion."
      Assert-GpMatch -Actual $configText -Pattern "env=ifUnset\|GSTheme=WinUXTheme" -Message "Launcher config should preserve conditional environment defaults."
      Assert-GpMatch -Actual $configText -Pattern "appDefaultsDomain=com\.example\.SampleGNUstepApp" -Message "Launcher config should preserve the packaged app defaults domain."
      Assert-GpMatch -Actual $configText -Pattern 'appDefault=GSTheme=\"WinUXTheme\"' -Message "Launcher config should seed the packaged theme through GNUstep defaults as well as the env fallback."
      Assert-GpMatch -Actual $configText -Pattern 'appDefault=SampleFirstRunComplete=YES' -Message "Launcher config should serialize boolean app defaults."
      Assert-GpMatch -Actual $configText -Pattern 'appDefault=SamplePreferredWidth=800' -Message "Launcher config should serialize integer app defaults."
      Assert-GpMatch -Actual $configText -Pattern 'appDefault=SampleWelcomeText=\"Packaged sample\"' -Message "Launcher config should serialize string app defaults as quoted GNUstep literals."
    }

    It "reports launcher errors without a dialog in non-interactive mode" {
      # A text file posing as defaults.exe: the launcher cannot run it to seed
      # packaged defaults. Interactively that error is a modal dialog, which
      # hangs a headless run until the smoke timeout.
      $brokenRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-msi-broken-launch-" + [guid]::NewGuid().ToString("N"))
      $stderrPath = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-msi-broken-launch-" + [guid]::NewGuid().ToString("N") + ".err")
      $previousNonInteractive = $env:GP_LAUNCHER_NONINTERACTIVE
      try {
        Copy-Item -Recurse -Path $script:transform.InstallRoot -Destination $brokenRoot
        Set-Content -Path (Join-Path $brokenRoot "runtime\bin\defaults.exe") -Value "not an executable"
        $launcher = Join-Path $brokenRoot (Split-Path -Leaf $script:transform.LauncherPath)

        $env:GP_LAUNCHER_NONINTERACTIVE = "1"
        $proc = Start-Process $launcher -PassThru -WorkingDirectory $brokenRoot -RedirectStandardError $stderrPath
        $exited = $proc.WaitForExit(15000)
        if (-not $exited) {
          $proc | Stop-Process -Force
        }

        Assert-GpTrue -Condition $exited -Message "The launcher should exit instead of waiting on an error dialog."
        Assert-GpTrue -Condition ($proc.ExitCode -ne 0) -Message "A failed launch should exit with a nonzero code."
        Assert-GpMatch -Actual (Get-Content -Raw -Path $stderrPath) -Pattern "Unable to read packaged app default" -Message "The launcher error should be written to stderr."
      } finally {
        $env:GP_LAUNCHER_NONINTERACTIVE = $previousNonInteractive
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $brokenRoot, $stderrPath
      }
    }

    It "fails the smoke launch fast with the launcher's error for a broken payload" {
      $brokenRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-msi-broken-smoke-" + [guid]::NewGuid().ToString("N"))
      $smokeLog = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-msi-broken-smoke-" + [guid]::NewGuid().ToString("N") + ".log")
      try {
        Copy-Item -Recurse -Path $script:transform.InstallRoot -Destination $brokenRoot
        Set-Content -Path (Join-Path $brokenRoot "runtime\bin\defaults.exe") -Value "not an executable"
        $launcher = Join-Path $brokenRoot (Split-Path -Leaf $script:transform.LauncherPath)
        $app = Join-Path $brokenRoot "app\SampleGNUstepApp.app\SampleGNUstepApp.exe"

        $message = $null
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
          Invoke-GpMsiSmokeLaunch -LauncherPath $launcher -AppPath $app -WorkingDirectory $brokenRoot -TimeoutSeconds 30 -LogPath $smokeLog
        } catch {
          $message = $_.Exception.Message
        }
        $stopwatch.Stop()

        Assert-GpTrue -Condition ($null -ne $message) -Message "The smoke launch should fail for a broken payload."
        Assert-GpTrue -Condition ($stopwatch.Elapsed.TotalSeconds -lt 20) -Message "The smoke launch should fail fast, not at the timeout. Took $($stopwatch.Elapsed.TotalSeconds) s."
        Assert-GpMatch -Actual $message -Pattern "launcher exited with code" -Message "The smoke failure should report the launcher exit."
        Assert-GpMatch -Actual $message -Pattern "Launcher error: .*Unable to read packaged app default" -Message "The smoke failure should include the launcher's error message."
      } finally {
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $brokenRoot, $smokeLog
      }
    }

    It "resolves relative path arguments against the caller's directory, not the working directory" {
      # Beside the install tree rather than under %TEMP%, whose 8.3 name
      # (RUNNER~1) would make the expected paths differ in form.
      $tempRoot = Join-Path (Split-Path -Parent $script:transform.InstallRoot) ("gp-msi-relative-args-" + [guid]::NewGuid().ToString("N"))
      $previousNonInteractive = $env:GP_LAUNCHER_NONINTERACTIVE
      $previousOutput = $env:GP_TEST_ARGV_PATH
      try {
        $installRoot = Join-Path $tempRoot "install"
        New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
        Copy-Item -Recurse -Path $script:transform.InstallRoot -Destination $installRoot
        $launcher = Join-Path $installRoot (Split-Path -Leaf $script:transform.LauncherPath)
        $launch = Get-GpLaunchContract -Context $script:transformContext
        $workingDirectory = [System.IO.Path]::GetFullPath((Join-Path $installRoot $launch.WorkingDirectory))
        $entryPath = Join-Path $installRoot $launch.EntryRelativePath

        # A stub entry reports where it runs and what it receives.
        $stubSource = Join-Path $tempRoot "ArgvStub.c"
        Set-Content -Path $stubSource -Encoding ascii -Value @(
          '#include <windows.h>'
          '#include <stdio.h>'
          '#include <stdlib.h>'
          'int wmain(int argc, wchar_t **argv)'
          '{'
          '    wchar_t cwd[32768];'
          '    FILE *out = _wfopen(_wgetenv(L"GP_TEST_ARGV_PATH"), L"w, ccs=UTF-8");'
          '    int i;'
          '    if (out == NULL) return 1;'
          '    GetCurrentDirectoryW(32768, cwd);'
          '    fwprintf(out, L"cwd=%ls\n", cwd);'
          '    for (i = 1; i < argc; i++) fwprintf(out, L"arg=[%ls]\n", argv[i]);'
          '    fclose(out);'
          '    return 0;'
          '}'
        )
        & (Get-GpPreferredWindowsClang) -municode -mwindows -o $entryPath $stubSource
        Assert-GpEqual -Actual $LASTEXITCODE -Expected 0 -Message "The argv stub should compile."

        $callerDir = Join-Path $tempRoot "home"
        New-Item -ItemType Directory -Force -Path (Join-Path $callerDir "Pictures"), (Join-Path $callerDir "My Docs") | Out-Null
        # YES is there so the -NSDebugLog YES case shows that an option's value stays as is.
        foreach ($file in @("Pictures\x.png", "notes.txt", "My Docs\a b.md", "YES")) {
          Set-Content -Path (Join-Path $callerDir $file) -Value ""
        }

        function Invoke-GpTestLauncher {
          param([string]$From, [string[]]$Arguments)
          $outputPath = Join-Path $tempRoot ("argv-" + [guid]::NewGuid().ToString("N") + ".txt")
          $env:GP_LAUNCHER_NONINTERACTIVE = "1"
          $env:GP_TEST_ARGV_PATH = $outputPath
          $startArguments = @{ FilePath = $launcher; WorkingDirectory = $From; PassThru = $true }
          if (@($Arguments).Count -gt 0) {
            # Start-Process joins its arguments with spaces, so quote each one.
            $startArguments["ArgumentList"] = @($Arguments | ForEach-Object { '"' + $_ + '"' })
          }
          $proc = Start-Process @startArguments
          Assert-GpTrue -Condition ($proc.WaitForExit(15000)) -Message "The launcher should exit."
          Assert-GpEqual -Actual $proc.ExitCode -Expected 0 -Message "The launcher should start the app."
          # The launcher does not wait for the app; wait for the stub's report.
          $deadline = [DateTime]::UtcNow.AddSeconds(15)
          while (-not (Test-Path $outputPath) -and [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 100
          }
          Start-Sleep -Milliseconds 200
          Assert-GpTrue -Condition (Test-Path $outputPath) -Message "The app stub should have written its report."
          return @(Get-Content -Path $outputPath -Encoding utf8)
        }

        # Launched from a prompt in the user's folder.
        $prompt = Invoke-GpTestLauncher -From $callerDir -Arguments @(
          "Pictures\x.png", "Pictures/x.png", "notes.txt", ".\notes.txt", "My Docs\a b.md", "exports\new.png",
          "missing.txt", "--foo=bar", "-NSDebugLog", "YES", "-Key", "notes.txt", "-GSLogFile", "logs\run.txt", "--out", "notes.txt",
          "/flag", "https://example.invalid/a?b=c", "mailto:someone@example.invalid"
        )
        Assert-GpEqual -Actual $prompt -Expected @(
          "cwd=$workingDirectory"
          "arg=[$callerDir\Pictures\x.png]"
          "arg=[$callerDir\Pictures\x.png]"
          "arg=[$callerDir\notes.txt]"
          "arg=[$callerDir\notes.txt]"
          "arg=[$callerDir\My Docs\a b.md]"
          "arg=[$callerDir\exports\new.png]"
          "arg=[missing.txt]"
          "arg=[--foo=bar]"
          "arg=[-NSDebugLog]"
          "arg=[YES]"
          "arg=[-Key]"
          "arg=[notes.txt]"
          "arg=[-GSLogFile]"
          "arg=[$callerDir\logs\run.txt]"
          "arg=[--out]"
          "arg=[$callerDir\notes.txt]"
          "arg=[/flag]"
          "arg=[https://example.invalid/a?b=c]"
          "arg=[mailto:someone@example.invalid]"
        ) -Message "Relative paths should resolve against the caller's directory, while the app still runs in launch.workingDirectory; options, a -Key option's plain value, and URLs pass through."

        # Explorer, Open with and shortcuts pass absolute paths or file URLs.
        $absolute = Join-Path $callerDir "Pictures\x.png"
        $fileUrl = ([System.Uri]$absolute).AbsoluteUri
        $explorer = Invoke-GpTestLauncher -From ([System.IO.Path]::GetPathRoot($tempRoot)) -Arguments @($absolute, $fileUrl)
        Assert-GpEqual -Actual $explorer -Expected @(
          "cwd=$workingDirectory"
          "arg=[$absolute]"
          "arg=[$fileUrl]"
        ) -Message "Absolute paths and file URLs should reach the app unchanged."

        $noArguments = Invoke-GpTestLauncher -From $callerDir -Arguments @()
        Assert-GpEqual -Actual $noArguments -Expected @("cwd=$workingDirectory") -Message "A launch without arguments should pass none."
      } finally {
        $env:GP_LAUNCHER_NONINTERACTIVE = $previousNonInteractive
        $env:GP_TEST_ARGV_PATH = $previousOutput
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $tempRoot
      }
    }

    It "writes a bundled notice report from compliance entries" {
      $noticeText = Get-Content -Raw -Path $script:transform.NoticeReportPath

      Assert-GpTrue -Condition (Test-Path $script:transform.NoticeReportPath) -Message "Transform should emit a third-party notice report."
      Assert-GpMatch -Actual $noticeText -Pattern "Runtime notice entries: 2" -Message "Notice report should summarize compliance entries."
      Assert-GpMatch -Actual $noticeText -Pattern "GNUstep Runtime Seed" -Message "Notice report should list configured runtime notices."
      Assert-GpMatch -Actual $noticeText -Pattern "metadata/licenses/GNUstep-runtime.txt" -Message "Notice report should preserve staged notice paths."
    }

    It "satisfies the semantic MSI package contract on the transformed install tree" {
      $contract = Invoke-GpPackageContractAssertions -Context $script:transformContext -Scope "package" -Backend "msi" -RootPath $script:transform.InstallRoot

      Assert-GpEqual -Actual $contract.HasIssues -Expected $false -Message "The transformed MSI install tree should satisfy the declared package contract."
      Assert-GpMatch -Actual ([string]::Join("`n", @($contract.Lines))) -Pattern "defaultTheme" -Message "The semantic MSI package contract should include declarative packaged defaults."
      Assert-GpMatch -Actual ([string]::Join("`n", @($contract.Lines))) -Pattern "bundled-theme" -Message "The semantic MSI package contract should include bundled theme assertions."
    }

    It "places the shortcut at the Start Menu root" {
      $templateText = Get-Content -Raw -Path $script:transformConfig.ProductTemplatePath

      Assert-GpMatch -Actual $templateText -Pattern '<DirectoryRef Id="ProgramMenuFolder">' -Message "Shortcut template should write directly to the Start Menu root."
      Assert-GpFalse -Condition ($templateText -match 'ApplicationProgramsFolder') -Message "Shortcut template should not create an extra Start Menu folder."
    }

    It "ends the runtime's daemons running from the install folder before files are replaced or removed" {
      $installRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-daemons-" + [guid]::NewGuid().ToString("N"))
      $toolsRoot = Join-Path $installRoot "runtime\System\Tools"
      New-Item -ItemType Directory -Force -Path $toolsRoot | Out-Null
      try {
        Assert-GpEqual -Actual @(Get-GpMsiRuntimeDaemonNames -InstallRoot $installRoot) -Expected @() -Message "An install tree without daemons should report none."
        Assert-GpEqual -Actual (Get-GpMsiStopRuntimeDaemonsXml -DaemonNames @() -InstallDirectoryName "SampleGui") -Expected "" -Message "No daemons should mean no custom action."

        foreach ($name in @("gdnc.exe", "gpbs.exe")) {
          Set-Content -Path (Join-Path $toolsRoot $name) -Value ""
        }
        $names = @(Get-GpMsiRuntimeDaemonNames -InstallRoot $installRoot)
        Assert-GpEqual -Actual $names -Expected @("gdnc", "gpbs") -Message "The bundled daemons should be found anywhere in the install tree."

        $xml = Get-GpMsiStopRuntimeDaemonsXml -DaemonNames $names -InstallDirectoryName "SampleGui"
        Assert-GpMatch -Actual $xml -Pattern 'DllEntry="WixQuietExec64" Execute="immediate" Return="ignore"' -Message "The daemons should be ended quietly, and a failure should not fail the install."
        Assert-GpMatch -Actual $xml -Pattern '<Custom Action="GpStopRuntimeDaemons" Before="InstallValidate" />' -Message "The daemons should be ended before Windows Installer checks for files in use."
        Assert-GpMatch -Actual $xml -Pattern 'Get-Process -Name gdnc,gpbs ' -Message "Only the bundled daemons should be ended."
        Assert-GpMatch -Actual $xml -Pattern ([regex]::Escape("Where-Object Path -Like &apos;*\SampleGui\*&apos;")) -Message "Only daemons running from this product's install folder should be ended."

        $escaped = Get-GpMsiStopRuntimeDaemonsXml -DaemonNames $names -InstallDirectoryName "Dan's [App]"
        Assert-GpMatch -Actual $escaped -Pattern ([regex]::Escape("-Like &apos;*\Dan&apos;&apos;s ``[\[]App``[\]]\*&apos;")) -Message "Quotes and brackets in the folder name should be escaped for PowerShell and for the MSI formatted string."
      } finally {
        Remove-Item -Recurse -Force -Path $installRoot -ErrorAction SilentlyContinue
      }
    }

    It "lists the app under Open with for its file extensions without taking over their defaults" {
      $registration = Get-GpMsiOpenWithRegistration -Config $script:transformConfig
      $xml = $registration.RegistrationXml

      Assert-GpEqual -Actual $registration.Extensions -Expected @(".sample") -Message "The manifest's extension associations should be registered."
      Assert-GpMatch -Actual $xml -Pattern ([regex]::Escape('Key="Software\Classes\.sample\OpenWithProgids"')) -Message "Each extension should list the app's ProgID under OpenWithProgids."
      Assert-GpMatch -Actual $xml -Pattern ([regex]::Escape('\SupportedTypes" Name=".sample"')) -Message "The launcher should declare the extension as a supported type."
      Assert-GpMatch -Actual $xml -Pattern ([regex]::Escape('Key="Software\RegisteredApplications"')) -Message "The app should be offered in Default Apps."
      Assert-GpMatch -Actual $xml -Pattern ([regex]::Escape('Value="&quot;[INSTALLDIR]')) -Message "Open commands should run the installed launcher."
      Assert-GpFalse -Condition ($xml -match ([regex]::Escape('Key="Software\Classes\.sample"'))) -Message "The extension's default handler should never be written."
      Assert-GpFalse -Condition ($xml -match 'UserChoice') -Message "The user's choice of default app should never be written."
      Assert-GpMatch -Actual $registration.ComponentRefXml -Pattern 'ComponentRef Id="OpenWithRegistration"' -Message "The registration should be part of the main feature."

      $none = Get-GpMsiOpenWithRegistration -Config ([pscustomobject]@{ FileAssociations = @(@{ kind = "mime"; value = "image/png" }) })
      Assert-GpEqual -Actual $none.RegistrationXml -Expected "" -Message "MIME associations have no MSI registration."
    }

    It "writes bundled updater metadata into the MSI install tree when enabled" {
      $manifestPath = New-GpSiblingManifest {
        param($manifest)
        $manifest["updates"] = @{
          enabled = $true
          provider = "github-release-feed"
          channel = "stable"
          github = @{
            owner = "example-org"
            repo = "sample-gnustep-app"
            tagPattern = "v{version}"
          }
        }
        $manifest["backends"]["msi"]["updates"] = @{
          feedUrl = "https://example.invalid/updates/windows/stable.json"
        }
      }
      $workPaths = $null

      try {
        $context = Get-GpManifestContext -Path $manifestPath
        $config = Get-GpMsiConfig -Context $context
        $workPaths = Get-GpMsiWorkPaths -Context $context
        $logPath = Join-Path $config.OutputPaths.LogRoot "pester-msi-transform-updates.log"
        $result = Prepare-GpMsiInstallTree -Context $context -Config $config -WorkPaths $workPaths -LogPath $logPath
        $updaterConfig = Get-GpJsonFile -Path $result.UpdateRuntimeConfigPath

        Assert-GpTrue -Condition (Test-Path $result.UpdateRuntimeConfigPath) -Message "Update-enabled MSI transforms should bundle a runtime updater config."
        Assert-GpEqual -Actual $updaterConfig["package"]["backend"] -Expected "msi" -Message "The bundled updater config should record the MSI backend."
        Assert-GpEqual -Actual $updaterConfig["updates"]["feedUrl"] -Expected "https://example.invalid/updates/windows/stable.json" -Message "The bundled updater config should preserve the resolved MSI feed URL."
      } finally {
        if (Test-Path $manifestPath) {
          Remove-Item -Force $manifestPath
        }
        if ($null -ne $workPaths -and (Test-Path $workPaths.Root)) {
          Remove-Item -Recurse -Force $workPaths.Root
        }
      }
    }
  }

  Context "Icon configuration and wrapper" {
    It "resolves a staged .ico path when configured" {
      $stageRoot = Join-Path $env:TEMP ("gp-icon-test-" + [guid]::NewGuid().ToString("N"))
      $iconPath = Join-Path $stageRoot "metadata\\icons\\sample.ico"
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $iconPath) | Out-Null
      Set-Content -Path $iconPath -Value "placeholder"

      try {
        $config = [pscustomobject]@{
          StageRoot = $stageRoot
          IconRelativePath = "metadata/icons/sample.ico"
        }

        $resolvedIconPath = [System.IO.Path]::GetFullPath((Resolve-GpMsiIconSourcePath -Config $config))
        $expectedIconPath = [System.IO.Path]::GetFullPath($iconPath)
        Assert-GpEqual -Actual $resolvedIconPath -Expected $expectedIconPath -Message "Configured MSI icon path should resolve inside the staged payload."
      } finally {
        if (Test-Path $stageRoot) {
          Remove-Item -Recurse -Force $stageRoot
        }
      }
    }

    It "shows the product icon in Installed apps when an icon is configured" {
      Assert-GpEqual -Actual (Get-GpMsiProductIconXml -IconPath "") -Expected "" -Message "No icon should mean no Icon element or ARPPRODUCTICON."
      Assert-GpEqual -Actual (Get-GpMsiProductIconXml -IconPath $null) -Expected "" -Message "An unset icon should mean no Icon element or ARPPRODUCTICON."

      $xml = Get-GpMsiProductIconXml -IconPath "C:\stage\metadata\icons\Dan's & App.ico"
      Assert-GpMatch -Actual $xml -Pattern ([regex]::Escape('<Icon Id="ProductIcon.ico" SourceFile="C:\stage\metadata\icons\Dan&apos;s &amp; App.ico" />')) -Message "The staged .ico should be embedded, with its path escaped for XML."
      Assert-GpMatch -Actual $xml -Pattern ([regex]::Escape('<Property Id="ARPPRODUCTICON" Value="ProductIcon.ico" />')) -Message "ARPPRODUCTICON should name the embedded icon."
    }

    It "supports dry-run packaging with a version override" {
      try {
        & (Join-Path $script:repoRoot "scripts\\run-packaging-pipeline.ps1") `
          -Manifest $script:manifestPath `
          -Backend msi `
          -PackageVersion "9.9.9" `
          -SkipBuild `
          -SkipStage `
          -SkipSharedValidation `
          -SkipBackendValidation `
          -DryRun | Out-Null
      } catch {
        throw "Dry-run pipeline wrapper should not throw. Error: $($_.Exception.Message)"
      }
    }
  }

  Context "Runtime closure policy" {
    It "fails by default on unresolved non-system dependencies after ignore filtering" {
      $config = [pscustomobject]@{
        UnresolvedDependencyPolicy = "fail"
      }
      $runtimeClosure = Resolve-GpMsiRuntimeClosureResult `
        -UnresolvedDependencies @("Missing.dll", "Optional.dll") `
        -IgnoredDependencies @("Optional.dll")
      $logPath = Join-Path $env:TEMP ("gp-msi-runtime-closure-" + [guid]::NewGuid().ToString("N") + ".log")
      $threw = $false

      try {
        Assert-GpEqual -Actual @($runtimeClosure.UnresolvedDependencies) -Expected @("Missing.dll") -Message "Ignored runtime dependencies should be filtered from the effective unresolved set."
        Assert-GpEqual -Actual @($runtimeClosure.IgnoredDependencies) -Expected @("Optional.dll") -Message "Ignored runtime dependencies should still be reported separately."
        try {
          Assert-GpMsiRuntimeClosurePolicy -Config $config -RuntimeClosure $runtimeClosure -LogPath $logPath
        } catch {
          $threw = $true
          Assert-GpMatch -Actual $_.Exception.Message -Pattern "Unresolved non-system runtime dependencies" -Message "The default MSI runtime policy should fail when unresolved DLLs remain."
        }
        Assert-GpTrue -Condition $threw -Message "The default MSI runtime policy should stop packaging when unresolved DLLs remain."
      } finally {
        if (Test-Path $logPath) {
          Remove-Item -Force $logPath
        }
      }
    }

    It "reports missing dependencies for runtime-extension DLLs with target provenance" {
      $tempRoot = Join-Path $env:TEMP ("gp-msi-runtime-audit-" + [guid]::NewGuid().ToString("N"))
      $appPath = Join-Path $tempRoot "app\\SampleGNUstepApp.app\\SampleGNUstepApp.exe"
      $bundlePath = Join-Path $tempRoot "runtime\\lib\\GNUstep\\Bundles\\libgnustep-back-032.bundle\\libgnustep-back-032.dll"
      $logPath = Join-Path $tempRoot "runtime-audit.log"
      $originalImportFunction = ${function:Get-GpPeImportedDllNames}

      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $appPath) | Out-Null
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $bundlePath) | Out-Null
      Set-Content -Path $appPath -Value "fixture"
      Set-Content -Path $bundlePath -Value "fixture"

      try {
        ${function:Get-GpPeImportedDllNames} = {
          param([string]$Path)

          $leaf = [System.IO.Path]::GetFileName($Path)
          switch ($leaf.ToLowerInvariant()) {
            "samplegnustepapp.exe" { return @("kernel32.dll") }
            "libgnustep-back-032.dll" { return @("libcairo-2.dll") }
            default { return @() }
          }
        }

        $context = [pscustomobject]@{
          Manifest = @{
            launch = @{
              entryRelativePath = "app/SampleGNUstepApp.app/SampleGNUstepApp.exe"
            }
          }
        }
        $config = [pscustomobject]@{
          RuntimeRootRelative = "runtime"
          RuntimeSeedPaths = @()
        }

        $analysis = Get-GpMsiRuntimeClosureAnalysis -Context $context -Config $config -InstallRoot $tempRoot -SearchRoots @() -LogPath $logPath
        $groups = @(Get-GpMsiMissingDependencyGroups -Analysis $analysis)
        $primaryMessage = Get-GpMsiPrimaryMissingDependencyMessage -Analysis $analysis

        Assert-GpEqual -Actual @($analysis.MissingDependencyNames) -Expected @("libcairo-2.dll") -Message "Runtime closure analysis should report the missing non-system dependency."
        Assert-GpEqual -Actual $groups.Count -Expected 1 -Message "Runtime closure analysis should group missing dependencies by target binary."
        Assert-GpMatch -Actual $groups[0].TargetRelativePath -Pattern "runtime/lib/GNUstep/Bundles/libgnustep-back-032\.bundle/libgnustep-back-032\.dll$" -Message "The missing dependency group should point at the bundle DLL."
        Assert-GpEqual -Actual $groups[0].TargetRole -Expected "runtime-extension" -Message "Bundle DLLs should be classified as runtime extensions."
        Assert-GpMatch -Actual $primaryMessage -Pattern "libgnustep-back-032\.dll" -Message "Primary missing-dependency diagnostics should mention the requiring DLL."
        Assert-GpMatch -Actual $primaryMessage -Pattern "libcairo-2\.dll" -Message "Primary missing-dependency diagnostics should mention the missing DLL."
      } finally {
        ${function:Get-GpPeImportedDllNames} = $originalImportFunction
        if (Test-Path $tempRoot) {
          Remove-Item -Recurse -Force $tempRoot
        }
      }
    }
  }
}
