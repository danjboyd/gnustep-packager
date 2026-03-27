Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-GpCaseInsensitiveDictionary {
  return [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
}

function New-GpCaseInsensitiveSet {
  return @{}
}

function Write-GpMsiLogLine {
  param(
    [string]$LogPath,
    [string]$Message
  )

  if ([string]::IsNullOrWhiteSpace($LogPath)) {
    return
  }

  Ensure-GpDirectory -Path (Split-Path -Parent $LogPath) | Out-Null
  Add-Content -Path $LogPath -Value ("[{0}] {1}" -f (Get-Date).ToString("o"), $Message)
}

function Invoke-GpMsiExternalTool {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [Parameter(Mandatory = $true)]
    [string[]]$ArgumentList,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  Write-GpMsiLogLine -LogPath $LogPath -Message ("RUN {0} {1}" -f $FilePath, ([string]::Join(' ', $ArgumentList)))
  $global:LASTEXITCODE = 0
  & $FilePath @ArgumentList 2>&1 | Tee-Object -FilePath $LogPath -Append | Out-Host
  $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
  if ($exitCode -ne 0) {
    throw "Command failed with exit code $exitCode. See log: $LogPath"
  }
}

function Normalize-GpMsiVersion {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Version
  )

  $matches = [System.Text.RegularExpressions.Regex]::Matches($Version, "\d+")
  $parts = @()
  foreach ($match in $matches) {
    $parts += $match.Value
  }

  if ($parts.Count -eq 0) {
    return "0.0.0.0"
  }

  while ($parts.Count -lt 4) {
    $parts += "0"
  }

  if ($parts.Count -gt 4) {
    $parts = $parts[0..3]
  }

  return ($parts -join ".")
}

function Get-GpPortableArtifactPlan {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [string]$Backend,
    [Parameter(Mandatory = $true)]
    [string]$Pattern
  )

  $manifest = $Context.Manifest
  $package = $manifest["package"]
  $outputPaths = Get-GpOutputPaths -Context $Context
  $artifactName = Resolve-GpPatternTokens -Pattern $Pattern -Tokens @{
    name = $package["name"]
    version = $package["version"]
    packageId = $package["id"]
    backend = $Backend
  }

  return [pscustomobject]@{
    Backend = $Backend
    ArtifactName = $artifactName
    ArtifactPath = Join-Path $outputPaths.PackageRoot $artifactName
    OutputRoot = $outputPaths.PackageRoot
  }
}

function Get-GpMsiConfig {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context
  )

  $manifest = $Context.Manifest
  $package = $manifest["package"]
  $integrations = $manifest["integrations"]
  $payload = $manifest["payload"]
  $backend = $manifest["backends"]["msi"]
  $artifactPlan = Get-GpArtifactPlan -Context $Context -Backend "msi"
  $portablePlan = Get-GpPortableArtifactPlan -Context $Context -Backend "msi" -Pattern ([string]$backend["portableArtifactNamePattern"])
  $outputPaths = Get-GpOutputPaths -Context $Context

  $displayName = if ($package.Contains("displayName") -and -not [string]::IsNullOrWhiteSpace([string]$package["displayName"])) {
    [string]$package["displayName"]
  } else {
    [string]$package["name"]
  }

  $productName = if (-not [string]::IsNullOrWhiteSpace([string]$backend["productName"])) {
    [string]$backend["productName"]
  } else {
    $displayName
  }

  $shortcutName = if (-not [string]::IsNullOrWhiteSpace([string]$backend["shortcutName"])) {
    [string]$backend["shortcutName"]
  } elseif ($integrations.Contains("shortcutName") -and -not [string]::IsNullOrWhiteSpace([string]$integrations["shortcutName"])) {
    [string]$integrations["shortcutName"]
  } else {
    $productName
  }

  $installDirectoryName = if (-not [string]::IsNullOrWhiteSpace([string]$backend["installDirectoryName"])) {
    [string]$backend["installDirectoryName"]
  } else {
    ($package["name"] -replace '[\\/:*?"<>|]', "")
  }

  $launcherFileName = if (-not [string]::IsNullOrWhiteSpace([string]$backend["launcherFileName"])) {
    [string]$backend["launcherFileName"]
  } else {
    ("{0}.exe" -f [string]$package["name"])
  }

  if (-not $launcherFileName.EndsWith(".exe", [System.StringComparison]::OrdinalIgnoreCase)) {
    $launcherFileName = $launcherFileName + ".exe"
  }

  $wixConfig = $backend["wix"]
  $signingConfig = $backend["signing"]
  $wixToolRoot = Resolve-GpPathRelativeToBase -BasePath $Context.ToolRoot -Path ([string]$wixConfig["toolRoot"])
  $stageRoot = Resolve-GpManifestPath -Context $Context -RelativePath ([string]$payload["stageRoot"])
  $normalizedVersion = Normalize-GpMsiVersion -Version ([string]$package["version"])

  return [pscustomobject]@{
    PackageId = [string]$package["id"]
    PackageName = [string]$package["name"]
    DisplayName = $displayName
    ProductName = $productName
    Manufacturer = [string]$package["manufacturer"]
    Version = [string]$package["version"]
    MsiVersion = $normalizedVersion
    UpgradeCode = [string]$backend["upgradeCode"]
    InstallScope = [string]$backend["installScope"]
    InstallDirectoryName = $installDirectoryName
    ShortcutName = $shortcutName
    LauncherFileName = $launcherFileName
    LauncherConfigName = ("{0}.launcher.ini" -f [System.IO.Path]::GetFileNameWithoutExtension($launcherFileName))
    FallbackRuntimeRoot = [string]$backend["fallbackRuntimeRoot"]
    RuntimeSearchRoots = [string[]]@($backend["runtimeSearchRoots"])
    ArtifactPlan = $artifactPlan
    PortablePlan = $portablePlan
    OutputPaths = $outputPaths
    StageRoot = $stageRoot
    AppRootRelative = [string]$payload["appRoot"]
    RuntimeRootRelative = [string]$payload["runtimeRoot"]
    MetadataRootRelative = [string]$payload["metadataRoot"]
    RuntimeSeedPaths = [string[]]@($payload["runtimeSeedPaths"])
    WixToolRoot = $wixToolRoot
    WixVersion = [string]$wixConfig["version"]
    WixDownloadUrl = [string]$wixConfig["downloadUrl"]
    SigningEnabled = [bool]$signingConfig["enabled"]
    SigningToolPath = [string]$signingConfig["toolPath"]
    SigningTimestampUrl = [string]$signingConfig["timestampUrl"]
    SigningCertificateSha1 = [string]$signingConfig["certificateSha1"]
    SigningDescription = [string]$signingConfig["description"]
    SigningAdditionalArguments = [string[]]@($signingConfig["additionalArguments"])
    LauncherSourcePath = Join-Path $Context.ToolRoot "backends\\msi\\assets\\GpWindowsLauncher.c"
    ProductTemplatePath = Join-Path $Context.ToolRoot "backends\\msi\\assets\\Product.wxs.template"
  }
}

function Get-GpMsiWorkPaths {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context
  )

  $outputPaths = Get-GpOutputPaths -Context $Context
  $workRoot = Join-Path (Join-Path $outputPaths.TempRoot "msi") (New-GpTimestamp)
  return [pscustomobject]@{
    Root = $workRoot
    BuildRoot = Join-Path $workRoot "build"
    InstallRoot = Join-Path $workRoot "install"
    WixRoot = Join-Path $workRoot "wix"
    DownloadRoot = Join-Path $workRoot "downloads"
  }
}

function Reset-GpDirectory {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (Test-Path $Path) {
    Remove-Item -Recurse -Force $Path
  }
  Ensure-GpDirectory -Path $Path | Out-Null
}

function Copy-GpRelativeStagePath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$StageRoot,
    [Parameter(Mandatory = $true)]
    [string]$RelativePath,
    [Parameter(Mandatory = $true)]
    [string]$InstallRoot
  )

  $source = Resolve-GpPathRelativeToBase -BasePath $StageRoot -Path $RelativePath
  if (-not (Test-Path $source)) {
    return $null
  }

  $parentRelative = Split-Path -Path $RelativePath -Parent
  $leafName = Split-Path -Path $RelativePath -Leaf
  $destinationParent = if ([string]::IsNullOrWhiteSpace($parentRelative) -or $parentRelative -eq ".") {
    $InstallRoot
  } else {
    Ensure-GpDirectory -Path (Join-Path $InstallRoot $parentRelative)
  }
  $destination = Join-Path $destinationParent $leafName

  if ((Get-Item $source) -is [System.IO.DirectoryInfo]) {
    Copy-Item -Recurse -Force $source $destination
  } else {
    Ensure-GpDirectory -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -Force $source $destination
  }

  return $destination
}

function Get-GpObjdumpPath {
  foreach ($name in @("llvm-objdump.exe", "llvm-objdump", "objdump.exe", "objdump")) {
    $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
      return $command.Source
    }
  }
  return $null
}

function Get-GpPeImportedDllNames {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $objdump = Get-GpObjdumpPath
  if (-not $objdump -or -not (Test-Path $Path)) {
    return @()
  }

  $output = & $objdump -p $Path 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $output) {
    return @()
  }

  $results = [System.Collections.Generic.List[string]]::new()
  foreach ($line in $output) {
    if ($line -match 'DLL Name:\s+(.+)$') {
      $name = $Matches[1].Trim()
      if (-not [string]::IsNullOrWhiteSpace($name)) {
        $results.Add($name) | Out-Null
      }
    }
  }

  return [string[]]($results | Select-Object -Unique)
}

function Test-GpMsiSystemDllName {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  $lowerName = $Name.ToLowerInvariant()
  foreach ($pattern in @(
    "api-ms-win-*.dll",
    "ext-ms-*.dll"
  )) {
    if ($lowerName -like $pattern) {
      return $true
    }
  }

  return $lowerName -in @(
    "advapi32.dll",
    "bcrypt.dll",
    "cabinet.dll",
    "cfgmgr32.dll",
    "combase.dll",
    "comctl32.dll",
    "comdlg32.dll",
    "crypt32.dll",
    "dwmapi.dll",
    "gdi32.dll",
    "gdi32full.dll",
    "imm32.dll",
    "kernel32.dll",
    "msi.dll",
    "msvcrt.dll",
    "mpr.dll",
    "netapi32.dll",
    "ncrypt.dll",
    "ntdll.dll",
    "ole32.dll",
    "oleaut32.dll",
    "rpcrt4.dll",
    "sechost.dll",
    "secur32.dll",
    "setupapi.dll",
    "shell32.dll",
    "shcore.dll",
    "shlwapi.dll",
    "ucrtbase.dll",
    "user32.dll",
    "userenv.dll",
    "uxtheme.dll",
    "version.dll",
    "win32u.dll",
    "winmm.dll",
    "ws2_32.dll"
  )
}

function Build-GpDllIndex {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Roots
  )

  $index = New-GpCaseInsensitiveDictionary
  foreach ($root in $Roots) {
    if (-not [string]::IsNullOrWhiteSpace($root) -and (Test-Path $root)) {
      foreach ($file in Get-ChildItem -Path $root -Recurse -File -Include *.dll, *.exe) {
        $leaf = $file.Name
        if (-not $index.ContainsKey($leaf)) {
          $index[$leaf] = $file.FullName
        }
      }
    }
  }
  return $index
}

function Complete-GpMsiRuntimeClosure {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [string]$InstallRoot,
    [string]$LogPath
  )

  $runtimeRoot = Resolve-GpPathRelativeToBase -BasePath $InstallRoot -Path $Config.RuntimeRootRelative
  $runtimeBin = Ensure-GpDirectory -Path (Join-Path $runtimeRoot "bin")
  $localIndex = Build-GpDllIndex -Roots @($InstallRoot)
  $searchIndex = Build-GpDllIndex -Roots $Config.RuntimeSearchRoots
  $queue = [System.Collections.Generic.Queue[string]]::new()
  $seenTargets = New-GpCaseInsensitiveSet
  $unresolved = New-GpCaseInsensitiveSet

  $entryPath = Resolve-GpPathRelativeToBase -BasePath $InstallRoot -Path $Context.Manifest["launch"]["entryRelativePath"]
  if (Test-Path $entryPath) {
    $queue.Enqueue($entryPath)
  }

  foreach ($relativePath in $Config.RuntimeSeedPaths) {
    $seedPath = Resolve-GpPathRelativeToBase -BasePath $InstallRoot -Path $relativePath
    if (Test-Path $seedPath) {
      $queue.Enqueue($seedPath)
    }
  }

  foreach ($file in Get-ChildItem -Path $runtimeRoot -Recurse -File -Include *.dll, *.exe -ErrorAction SilentlyContinue) {
    $queue.Enqueue($file.FullName)
  }

  while ($queue.Count -gt 0) {
    $target = $queue.Dequeue()
    if (-not (Test-Path $target)) {
      continue
    }

    if ($seenTargets.ContainsKey($target)) {
      continue
    }
    $seenTargets[$target] = $true

    foreach ($dllName in Get-GpPeImportedDllNames -Path $target) {
      if (Test-GpMsiSystemDllName -Name $dllName) {
        continue
      }

      if ($localIndex.ContainsKey($dllName)) {
        continue
      }

      if ($searchIndex.ContainsKey($dllName)) {
        $source = $searchIndex[$dllName]
        $destination = Join-Path $runtimeBin $dllName
        if (-not (Test-Path $destination)) {
          Copy-Item -Force $source $destination
          Write-GpMsiLogLine -LogPath $LogPath -Message ("Copied dependency {0} -> {1}" -f $source, $destination)
        }
        $localIndex[$dllName] = $destination
        $queue.Enqueue($destination)
      } else {
        if (-not $unresolved.ContainsKey($dllName)) {
          $unresolved[$dllName] = $true
        }
      }
    }
  }

  return [string[]]@($unresolved.Keys | Sort-Object)
}

function Get-GpPreferredWindowsClang {
  $candidates = @(
    "C:\msys64\clang64\bin\clang.exe",
    "C:\msys64\mingw64\bin\clang.exe"
  )

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  $command = Get-Command clang -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($command) {
    return $command.Source
  }

  throw "clang not found. MSI launcher compilation requires a Windows-capable clang."
}

function Get-GpMsiSigningSettings {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Config
  )

  $enabled = $Config.SigningEnabled -or ($env:GP_SIGN_ENABLED -eq "1") -or ($env:GP_SIGN_ENABLED -eq "true")
  $toolPath = if (-not [string]::IsNullOrWhiteSpace($env:GP_SIGNTOOL_PATH)) {
    [string]$env:GP_SIGNTOOL_PATH
  } elseif (-not [string]::IsNullOrWhiteSpace($Config.SigningToolPath)) {
    [string]$Config.SigningToolPath
  } else {
    $null
  }

  if (-not [string]::IsNullOrWhiteSpace($toolPath)) {
    $toolPath = Resolve-GpPathRelativeToBase -BasePath (Get-Location).Path -Path $toolPath
  } else {
    $command = Get-Command signtool.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
      $toolPath = $command.Source
    }
  }

  $timestampUrl = if (-not [string]::IsNullOrWhiteSpace($env:GP_SIGN_TIMESTAMP_URL)) {
    [string]$env:GP_SIGN_TIMESTAMP_URL
  } else {
    [string]$Config.SigningTimestampUrl
  }

  $certificateSha1 = if (-not [string]::IsNullOrWhiteSpace($env:GP_SIGN_CERT_SHA1)) {
    [string]$env:GP_SIGN_CERT_SHA1
  } else {
    [string]$Config.SigningCertificateSha1
  }

  $description = if (-not [string]::IsNullOrWhiteSpace($env:GP_SIGN_DESCRIPTION)) {
    [string]$env:GP_SIGN_DESCRIPTION
  } elseif (-not [string]::IsNullOrWhiteSpace($Config.SigningDescription)) {
    [string]$Config.SigningDescription
  } else {
    [string]$Config.ProductName
  }

  $pfxPath = if (-not [string]::IsNullOrWhiteSpace($env:GP_SIGN_PFX_PATH)) {
    Resolve-GpPathRelativeToBase -BasePath (Get-Location).Path -Path ([string]$env:GP_SIGN_PFX_PATH)
  } else {
    $null
  }

  $pfxPassword = if (-not [string]::IsNullOrWhiteSpace($env:GP_SIGN_PFX_PASSWORD)) {
    [string]$env:GP_SIGN_PFX_PASSWORD
  } else {
    $null
  }

  return [pscustomobject]@{
    Enabled = [bool]$enabled
    ToolPath = $toolPath
    TimestampUrl = $timestampUrl
    CertificateSha1 = $certificateSha1
    Description = $description
    PfxPath = $pfxPath
    PfxPassword = $pfxPassword
    AdditionalArguments = [string[]]@($Config.SigningAdditionalArguments)
  }
}

function Invoke-GpMsiSignFile {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Signing,
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  if (-not $Signing.Enabled) {
    return
  }

  if (-not (Test-Path $Path)) {
    throw "Cannot sign missing file: $Path"
  }

  if ([string]::IsNullOrWhiteSpace($Signing.ToolPath) -or -not (Test-Path $Signing.ToolPath)) {
    throw "Signing enabled but signtool was not found."
  }

  $args = [System.Collections.Generic.List[string]]::new()
  $args.Add("sign") | Out-Null
  $args.Add("/fd") | Out-Null
  $args.Add("SHA256") | Out-Null

  if (-not [string]::IsNullOrWhiteSpace($Signing.Description)) {
    $args.Add("/d") | Out-Null
    $args.Add($Signing.Description) | Out-Null
  }

  if (-not [string]::IsNullOrWhiteSpace($Signing.TimestampUrl)) {
    $args.Add("/tr") | Out-Null
    $args.Add($Signing.TimestampUrl) | Out-Null
    $args.Add("/td") | Out-Null
    $args.Add("SHA256") | Out-Null
  }

  if (-not [string]::IsNullOrWhiteSpace($Signing.CertificateSha1)) {
    $args.Add("/sha1") | Out-Null
    $args.Add($Signing.CertificateSha1) | Out-Null
  } elseif (-not [string]::IsNullOrWhiteSpace($Signing.PfxPath)) {
    $args.Add("/f") | Out-Null
    $args.Add($Signing.PfxPath) | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($Signing.PfxPassword)) {
      $args.Add("/p") | Out-Null
      $args.Add($Signing.PfxPassword) | Out-Null
    }
  } else {
    throw "Signing enabled but neither GP_SIGN_CERT_SHA1 nor GP_SIGN_PFX_PATH is configured."
  }

  foreach ($argument in @($Signing.AdditionalArguments)) {
    if (-not [string]::IsNullOrWhiteSpace($argument)) {
      $args.Add($argument) | Out-Null
    }
  }

  $args.Add($Path) | Out-Null
  Invoke-GpMsiExternalTool -FilePath $Signing.ToolPath -ArgumentList ([string[]]$args.ToArray()) -LogPath $LogPath
}

function Build-GpMsiLauncher {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  $clang = Get-GpPreferredWindowsClang
  Ensure-GpDirectory -Path (Split-Path -Parent $OutputPath) | Out-Null

  Invoke-GpMsiExternalTool -FilePath $clang -ArgumentList @(
    "-O2",
    "-municode",
    "-mwindows",
    "-DWIN32_LEAN_AND_MEAN",
    "-o", $OutputPath,
    $Config.LauncherSourcePath,
    "-lshell32",
    "-lshlwapi"
  ) -LogPath $LogPath
}

function Get-GpLaunchEnvironmentForMsi {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [psobject]$Config
  )

  $launch = Get-GpLaunchContract -Context $Context
  $environment = [hashtable](Copy-GpValue -Value $launch.Environment)
  if (-not $environment.ContainsKey("GNUSTEP_PATHPREFIX_LIST")) {
    $environment["GNUSTEP_PATHPREFIX_LIST"] = "{@runtimeRoot}"
  }
  return $environment
}

function Write-GpMsiLauncherConfig {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [string]$InstallRoot
  )

  $launch = Get-GpLaunchContract -Context $Context
  $environment = Get-GpLaunchEnvironmentForMsi -Context $Context -Config $Config
  $configPath = Join-Path $InstallRoot $Config.LauncherConfigName
  $lines = [System.Collections.Generic.List[string]]::new()

  $lines.Add(("displayName={0}" -f $Config.ProductName)) | Out-Null
  $lines.Add(("entryRelativePath={0}" -f $launch.EntryRelativePath)) | Out-Null
  $lines.Add(("workingDirectoryRelative={0}" -f $launch.WorkingDirectory)) | Out-Null
  $lines.Add(("runtimeRootRelative={0}" -f $Config.RuntimeRootRelative)) | Out-Null
  $lines.Add(("appRootRelative={0}" -f $Config.AppRootRelative)) | Out-Null
  $lines.Add(("metadataRootRelative={0}" -f $Config.MetadataRootRelative)) | Out-Null
  $lines.Add(("fallbackRuntimeRoot={0}" -f $Config.FallbackRuntimeRoot)) | Out-Null

  foreach ($item in @($launch.PathPrepend)) {
    if (-not [string]::IsNullOrWhiteSpace($item)) {
      $lines.Add(("pathPrepend={0}" -f $item)) | Out-Null
    }
  }

  foreach ($item in @($launch.Arguments)) {
    if (-not [string]::IsNullOrWhiteSpace($item)) {
      $lines.Add(("baseArgument={0}" -f $item)) | Out-Null
    }
  }

  foreach ($key in ($environment.Keys | Sort-Object)) {
    $lines.Add(("env={0}={1}" -f $key, [string]$environment[$key])) | Out-Null
  }

  Set-Content -Path $configPath -Value $lines
  return $configPath
}

function Prepare-GpMsiInstallTree {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [psobject]$WorkPaths,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  Reset-GpDirectory -Path $WorkPaths.InstallRoot

  foreach ($relativeRoot in @($Config.AppRootRelative, $Config.RuntimeRootRelative, $Config.MetadataRootRelative)) {
    if (-not [string]::IsNullOrWhiteSpace($relativeRoot)) {
      $destination = Copy-GpRelativeStagePath -StageRoot $Config.StageRoot -RelativePath $relativeRoot -InstallRoot $WorkPaths.InstallRoot
      if ($destination) {
        Write-GpMsiLogLine -LogPath $LogPath -Message ("Copied staged root {0} -> {1}" -f $relativeRoot, $destination)
      }
    }
  }

  $signing = Get-GpMsiSigningSettings -Config $Config
  $launcherOutputPath = Join-Path $WorkPaths.InstallRoot $Config.LauncherFileName
  Build-GpMsiLauncher -Config $Config -OutputPath $launcherOutputPath -LogPath $LogPath
  Invoke-GpMsiSignFile -Signing $signing -Path $launcherOutputPath -LogPath $LogPath
  $launcherConfigPath = Write-GpMsiLauncherConfig -Context $Context -Config $Config -InstallRoot $WorkPaths.InstallRoot
  Write-GpMsiLogLine -LogPath $LogPath -Message ("Generated launcher config: {0}" -f $launcherConfigPath)

  [string[]]$unresolved = @()
  $unresolvedRaw = Complete-GpMsiRuntimeClosure -Context $Context -Config $Config -InstallRoot $WorkPaths.InstallRoot -LogPath $LogPath
  if ($null -ne $unresolvedRaw) {
    $unresolved = [string[]]@($unresolvedRaw)
  }
  if ($unresolved.Count -gt 0) {
    Write-GpMsiLogLine -LogPath $LogPath -Message ("Unresolved runtime dependencies: {0}" -f ([string]::Join(", ", $unresolved)))
  }

  return [pscustomobject]@{
    InstallRoot = $WorkPaths.InstallRoot
    LauncherPath = $launcherOutputPath
    LauncherConfigPath = $launcherConfigPath
    UnresolvedDependencies = $unresolved
  }
}

function Ensure-GpWixTools {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [psobject]$WorkPaths,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  function Resolve-Tool([string]$toolName) {
    $cmd = Get-Command $toolName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) {
      return $cmd.Source
    }
    $localPath = Join-Path $Config.WixToolRoot $toolName
    if (Test-Path $localPath) {
      return $localPath
    }
    return $null
  }

  $heat = Resolve-Tool -toolName "heat.exe"
  $candle = Resolve-Tool -toolName "candle.exe"
  $light = Resolve-Tool -toolName "light.exe"

  if ($heat -and $candle -and $light) {
    return [pscustomobject]@{ Heat = $heat; Candle = $candle; Light = $light }
  }

  Write-GpMsiLogLine -LogPath $LogPath -Message ("Bootstrapping WiX {0} into {1}" -f $Config.WixVersion, $Config.WixToolRoot)
  Ensure-GpDirectory -Path $Config.WixToolRoot | Out-Null
  Ensure-GpDirectory -Path $WorkPaths.DownloadRoot | Out-Null
  $zipPath = Join-Path $WorkPaths.DownloadRoot ("wix-{0}.zip" -f $Config.WixVersion)
  Invoke-WebRequest -Uri $Config.WixDownloadUrl -OutFile $zipPath
  Expand-Archive -Path $zipPath -DestinationPath $Config.WixToolRoot -Force

  $heat = Resolve-Tool -toolName "heat.exe"
  $candle = Resolve-Tool -toolName "candle.exe"
  $light = Resolve-Tool -toolName "light.exe"

  if (-not $heat -or -not $candle -or -not $light) {
    throw "WiX tools not found after bootstrap. Expected tools under $($Config.WixToolRoot)."
  }

  return [pscustomobject]@{ Heat = $heat; Candle = $candle; Light = $light }
}

function Escape-GpXmlText {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value
  )

  return [System.Security.SecurityElement]::Escape($Value)
}

function Render-GpMsiTemplateText {
  param(
    [Parameter(Mandatory = $true)]
    [string]$TemplatePath,
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Tokens
  )

  $text = Get-Content -Raw -Path $TemplatePath
  foreach ($key in $Tokens.Keys) {
    $text = $text.Replace($key, [string]$Tokens[$key])
  }
  return $text
}

function Write-GpMsiSources {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [psobject]$WorkPaths,
    [Parameter(Mandatory = $true)]
    [psobject]$WixTools,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  Reset-GpDirectory -Path $WorkPaths.WixRoot
  $harvestPath = Join-Path $WorkPaths.WixRoot "InstalledFiles.wxs"
  $productPath = Join-Path $WorkPaths.WixRoot "Product.wxs"

  Invoke-GpMsiExternalTool -FilePath $WixTools.Heat -ArgumentList @(
    "dir",
    $WorkPaths.InstallRoot,
    "-cg", "InstalledFiles",
    "-dr", "INSTALLDIR",
    "-srd",
    "-sreg",
    "-sfrag",
    "-gg",
    "-g1",
    "-var", "var.InstallSourceDir",
    "-out", $harvestPath
  ) -LogPath $LogPath

  $registryRoot = "HKCU"
  $rootDirectoryId = if ($Config.InstallScope -eq "perMachine") { "ProgramFiles64Folder" } else { "LocalAppDataFolder" }
  $tokens = @{
    "__PRODUCT_NAME__" = Escape-GpXmlText -Value $Config.ProductName
    "__MANUFACTURER__" = Escape-GpXmlText -Value $Config.Manufacturer
    "__PRODUCT_VERSION__" = Escape-GpXmlText -Value $Config.MsiVersion
    "__UPGRADE_CODE__" = Escape-GpXmlText -Value $Config.UpgradeCode
    "__INSTALL_SCOPE__" = Escape-GpXmlText -Value $Config.InstallScope
    "__INSTALL_PRIVILEGES__" = $(if ($Config.InstallScope -eq "perUser") { "limited" } else { "elevated" })
    "__ROOT_DIRECTORY_ID__" = $rootDirectoryId
    "__INSTALL_DIRECTORY_NAME__" = Escape-GpXmlText -Value $Config.InstallDirectoryName
    "__PROGRAM_MENU_FOLDER_NAME__" = Escape-GpXmlText -Value $Config.ProductName
    "__SHORTCUT_COMPONENT_GUID__" = ([guid]::NewGuid().ToString())
    "__SHORTCUT_NAME__" = Escape-GpXmlText -Value $Config.ShortcutName
    "__LAUNCHER_FILE_NAME__" = Escape-GpXmlText -Value $Config.LauncherFileName
    "__REGISTRY_ROOT__" = $registryRoot
    "__REGISTRY_MANUFACTURER__" = Escape-GpXmlText -Value $Config.Manufacturer
    "__REGISTRY_PRODUCT_NAME__" = Escape-GpXmlText -Value $Config.ProductName
  }

  $productContent = Render-GpMsiTemplateText -TemplatePath $Config.ProductTemplatePath -Tokens $tokens
  Set-Content -Path $productPath -Value $productContent

  return [pscustomobject]@{
    HarvestPath = $harvestPath
    ProductPath = $productPath
  }
}

function Build-GpMsiArtifacts {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [psobject]$WorkPaths,
    [Parameter(Mandatory = $true)]
    [psobject]$WixTools,
    [Parameter(Mandatory = $true)]
    [psobject]$Sources,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  Ensure-GpDirectory -Path $Config.ArtifactPlan.OutputRoot | Out-Null
  $msiPath = $Config.ArtifactPlan.ArtifactPath
  $zipPath = $Config.PortablePlan.ArtifactPath
  $signing = Get-GpMsiSigningSettings -Config $Config

  if (Test-Path $msiPath) {
    Remove-Item -Force $msiPath
  }
  if (Test-Path $zipPath) {
    Remove-Item -Force $zipPath
  }

  $outputBase = Join-Path $WorkPaths.WixRoot ""
  Invoke-GpMsiExternalTool -FilePath $WixTools.Candle -ArgumentList @(
    "-arch", "x64",
    "-dInstallSourceDir=$($WorkPaths.InstallRoot)",
    "-out", $outputBase,
    $Sources.ProductPath,
    $Sources.HarvestPath
  ) -LogPath $LogPath

  $lightArgs = [System.Collections.Generic.List[string]]::new()
  $lightArgs.Add("-out") | Out-Null
  $lightArgs.Add($msiPath) | Out-Null
  if ($Config.InstallScope -eq "perUser") {
    foreach ($ice in @("ICE38", "ICE64", "ICE91")) {
      $lightArgs.Add("-sice:$ice") | Out-Null
    }
  }
  $lightArgs.Add((Join-Path $WorkPaths.WixRoot "Product.wixobj")) | Out-Null
  $lightArgs.Add((Join-Path $WorkPaths.WixRoot "InstalledFiles.wixobj")) | Out-Null

  Invoke-GpMsiExternalTool -FilePath $WixTools.Light -ArgumentList ([string[]]$lightArgs.ToArray()) -LogPath $LogPath

  Invoke-GpMsiSignFile -Signing $signing -Path $msiPath -LogPath $LogPath
  Compress-Archive -Path (Join-Path $WorkPaths.InstallRoot "*") -DestinationPath $zipPath -Force
  Write-GpMsiLogLine -LogPath $LogPath -Message ("Created portable ZIP: {0}" -f $zipPath)

  return [pscustomobject]@{
    ArtifactPath = $msiPath
    PortableArtifactPath = $zipPath
  }
}

function Invoke-GpMsiPackage {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [switch]$DryRun,
    [string]$LogPath
  )

  $config = Get-GpMsiConfig -Context $Context
  $workPaths = Get-GpMsiWorkPaths -Context $Context
  $launch = Get-GpLaunchContract -Context $Context
  $summary = [ordered]@{
    Backend = "msi"
    ManifestPath = $Context.ManifestPath
    ProductName = $config.ProductName
    Version = $config.Version
    MsiVersion = $config.MsiVersion
    StageRoot = $config.StageRoot
    EntryPath = $launch.EntryPath
    ArtifactPath = $config.ArtifactPlan.ArtifactPath
    PortableArtifactPath = $config.PortablePlan.ArtifactPath
    WorkRoot = $workPaths.Root
    LauncherFileName = $config.LauncherFileName
  }

  if ($DryRun) {
    Write-GpMsiLogLine -LogPath $LogPath -Message ("MSI package dry-run for {0}" -f $config.ProductName)
    return [pscustomobject]$summary
  }

  Write-GpMsiLogLine -LogPath $LogPath -Message ("Starting MSI package build for {0}" -f $config.ProductName)
  Ensure-GpDirectory -Path $config.OutputPaths.TempRoot | Out-Null
  Ensure-GpDirectory -Path $config.OutputPaths.PackageRoot | Out-Null

  $installTree = Prepare-GpMsiInstallTree -Context $Context -Config $config -WorkPaths $workPaths -LogPath $LogPath
  $wixTools = Ensure-GpWixTools -Config $config -WorkPaths $workPaths -LogPath $LogPath
  $sources = Write-GpMsiSources -Context $Context -Config $config -WorkPaths $workPaths -WixTools $wixTools -LogPath $LogPath
  $artifacts = Build-GpMsiArtifacts -Context $Context -Config $config -WorkPaths $workPaths -WixTools $wixTools -Sources $sources -LogPath $LogPath

  return [pscustomobject]@{
    Backend = "msi"
    ManifestPath = $Context.ManifestPath
    ProductName = $config.ProductName
    ArtifactPath = $artifacts.ArtifactPath
    PortableArtifactPath = $artifacts.PortableArtifactPath
    InstallRoot = $installTree.InstallRoot
    LauncherPath = $installTree.LauncherPath
    LauncherConfigPath = $installTree.LauncherConfigPath
    UnresolvedDependencies = $installTree.UnresolvedDependencies
    LogPath = $LogPath
  }
}

function Get-GpMsiInstallPathGuess {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Config
  )

  if ($Config.InstallScope -eq "perUser") {
    return (Join-Path $env:LOCALAPPDATA $Config.InstallDirectoryName)
  }

  return (Join-Path $env:ProgramFiles $Config.InstallDirectoryName)
}

function Get-GpMsiProcessesByExecutablePath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ExecutablePath
  )

  $expectedPath = [System.IO.Path]::GetFullPath($ExecutablePath)
  $processName = [System.IO.Path]::GetFileNameWithoutExtension($expectedPath)
  $matches = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()

  foreach ($process in @(Get-Process -Name $processName -ErrorAction SilentlyContinue)) {
    try {
      if ([string]::IsNullOrWhiteSpace($process.Path)) {
        continue
      }

      $actualPath = [System.IO.Path]::GetFullPath([string]$process.Path)
      if ([string]::Equals($actualPath, $expectedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        $matches.Add($process) | Out-Null
      }
    } catch {
      continue
    }
  }

  return @($matches.ToArray())
}

function Invoke-GpMsiValidation {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [switch]$DryRun,
    [switch]$RunSmoke,
    [string]$LogPath
  )

  $config = Get-GpMsiConfig -Context $Context
  $validationPlan = Get-GpValidationPlan -Context $Context
  $launchContract = Get-GpLaunchContract -Context $Context
  $artifactPath = $config.ArtifactPlan.ArtifactPath
  $installPath = Get-GpMsiInstallPathGuess -Config $config
  $launcherPath = Join-Path $installPath $config.LauncherFileName
  $appPath = Resolve-GpPathRelativeToBase -BasePath $installPath -Path $launchContract.EntryRelativePath
  $runtimePath = Resolve-GpPathRelativeToBase -BasePath $installPath -Path $config.RuntimeRootRelative

  if ($DryRun) {
    Write-GpMsiLogLine -LogPath $LogPath -Message ("MSI validation dry-run for {0}" -f $artifactPath)
    return [pscustomobject]@{
      Backend = "msi"
      Mode = "dry-run"
      ArtifactPath = $artifactPath
      InstallPath = $installPath
      LauncherPath = $launcherPath
      AppPath = $appPath
      RuntimePath = $runtimePath
      RunSmoke = [bool]$RunSmoke
      TimeoutSeconds = $validationPlan.TimeoutSeconds
      LogPath = $LogPath
    }
  }

  if (-not (Test-Path $artifactPath)) {
    throw "MSI artifact not found: $artifactPath"
  }

  Ensure-GpDirectory -Path (Split-Path -Parent $LogPath) | Out-Null
  $validationRoot = Split-Path -Parent $LogPath
  $installLog = Join-Path $validationRoot "install.log"
  $uninstallLog = Join-Path $validationRoot "uninstall.log"

  Write-GpMsiLogLine -LogPath $LogPath -Message ("Installing MSI: {0}" -f $artifactPath)
  $installProcess = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @("/i", $artifactPath, "/qn", "/norestart", "/l*v", $installLog)
  if ($installProcess.ExitCode -ne 0) {
    throw "MSI install failed with exit code $($installProcess.ExitCode). See $installLog"
  }

  if (-not (Test-Path $launcherPath)) {
    throw "Expected launcher was not installed: $launcherPath"
  }

  if (-not (Test-Path $runtimePath)) {
    throw "Expected runtime root was not installed: $runtimePath"
  }

  if (-not (Test-Path $appPath)) {
    throw "Expected packaged application executable was not installed: $appPath"
  }

  Write-GpMsiLogLine -LogPath $LogPath -Message ("Installed launcher path: {0}" -f $launcherPath)
  Write-GpMsiLogLine -LogPath $LogPath -Message ("Installed app path: {0}" -f $appPath)
  Write-GpMsiLogLine -LogPath $LogPath -Message ("Installed runtime path: {0}" -f $runtimePath)

  if ($RunSmoke -or $validationPlan.Enabled) {
    $smokeArgument = Join-Path $env:TEMP "gnustep-packager-smoke.txt"
    $probeDeadline = (Get-Date).AddSeconds([Math]::Max($validationPlan.TimeoutSeconds, 1))
    $childProcesses = @()
    Set-Content -Path $smokeArgument -Value "gnustep-packager smoke"
    Write-GpMsiLogLine -LogPath $LogPath -Message ("Running MSI smoke launch: {0}" -f $launcherPath)
    $proc = Start-Process $launcherPath -ArgumentList @($smokeArgument) -PassThru -WorkingDirectory $installPath

    do {
      Start-Sleep -Milliseconds 500
      $proc.Refresh()
      $childProcesses = @(Get-GpMsiProcessesByExecutablePath -ExecutablePath $appPath)
    } while (((-not $proc.HasExited) -or $childProcesses.Count -eq 0) -and (Get-Date) -lt $probeDeadline)

    $proc.Refresh()
    if (-not $proc.HasExited) {
      try {
        $proc | Stop-Process -Force
      } catch {
      }
      throw "Smoke launcher did not exit within $($validationPlan.TimeoutSeconds) seconds: $launcherPath"
    }

    Write-GpMsiLogLine -LogPath $LogPath -Message ("Smoke process exit code: {0}" -f $proc.ExitCode)
    if ($proc.ExitCode -ne 0) {
      throw "Smoke launcher exited with code $($proc.ExitCode): $launcherPath"
    }

    $childProcesses = @(Get-GpMsiProcessesByExecutablePath -ExecutablePath $appPath)
    if ($childProcesses.Count -eq 0) {
      throw "Smoke launch did not leave the packaged application running: $appPath"
    }

    Write-GpMsiLogLine -LogPath $LogPath -Message ("Smoke child process count: {0}" -f $childProcesses.Count)
    foreach ($child in $childProcesses) {
      try {
        $child | Stop-Process -Force
      } catch {
      }
    }
  }

  Write-GpMsiLogLine -LogPath $LogPath -Message ("Uninstalling MSI: {0}" -f $artifactPath)
  $uninstallProcess = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @("/x", $artifactPath, "/qn", "/norestart", "/l*v", $uninstallLog)
  if ($uninstallProcess.ExitCode -ne 0) {
    throw "MSI uninstall failed with exit code $($uninstallProcess.ExitCode). See $uninstallLog"
  }

  if (Test-Path $launcherPath) {
    throw "Launcher still present after MSI uninstall: $launcherPath"
  }

  return [pscustomobject]@{
    Backend = "msi"
    Mode = "execute"
    ArtifactPath = $artifactPath
    InstallPath = $installPath
    LauncherPath = $launcherPath
    AppPath = $appPath
    RuntimePath = $runtimePath
    InstallLog = $installLog
    UninstallLog = $uninstallLog
    LogPath = $LogPath
  }
}
