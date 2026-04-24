Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-GpToolRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "..\\..")).Path
}

function Copy-GpValue {
  param(
    [Parameter(Mandatory = $true)]
    [AllowNull()]
    [object]$Value
  )

  if ($null -eq $Value) {
    return $null
  }

  if ($Value -is [System.Collections.IDictionary]) {
    $copy = @{}
    foreach ($key in $Value.Keys) {
      $copy[$key] = Copy-GpValue -Value $Value[$key]
    }
    return $copy
  }

  if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
    $items = @()
    foreach ($item in $Value) {
      $items += ,(Copy-GpValue -Value $item)
    }
    return ,$items
  }

  return $Value
}

function Convert-GpJsonObjectToHashtable {
  param(
    [Parameter(Mandatory = $true)]
    [AllowNull()]
    [object]$Value
  )

  if ($null -eq $Value) {
    return $null
  }

  if ($Value -is [System.Collections.IDictionary]) {
    $copy = @{}
    foreach ($key in $Value.Keys) {
      $copy[$key] = Convert-GpJsonObjectToHashtable -Value $Value[$key]
    }
    return $copy
  }

  if ($Value -is [System.Management.Automation.PSCustomObject]) {
    $copy = @{}
    foreach ($property in $Value.PSObject.Properties) {
      $copy[$property.Name] = Convert-GpJsonObjectToHashtable -Value $property.Value
    }
    return $copy
  }

  if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
    $items = @()
    foreach ($item in $Value) {
      $items += ,(Convert-GpJsonObjectToHashtable -Value $item)
    }
    return ,$items
  }

  return $Value
}

function Merge-GpHashtable {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Base,
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Overlay
  )

  $merged = Copy-GpValue -Value $Base

  foreach ($key in $Overlay.Keys) {
    if ($merged.ContainsKey($key) -and
        ($merged[$key] -is [System.Collections.IDictionary]) -and
        ($Overlay[$key] -is [System.Collections.IDictionary])) {
      $merged[$key] = Merge-GpHashtable -Base $merged[$key] -Overlay $Overlay[$key]
    } else {
      $merged[$key] = Copy-GpValue -Value $Overlay[$key]
    }
  }

  return $merged
}

function Resolve-GpPathRelativeToBase {
  param(
    [Parameter(Mandatory = $true)]
    [string]$BasePath,
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }

  return [System.IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}

function Test-GpWildcardPathPattern {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  return ($Path.IndexOfAny([char[]]@('*', '?', '[')) -ge 0)
}

function Resolve-GpValidationPathMatches {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ResolvedPath
  )

  $matches = [System.Collections.Generic.List[string]]::new()
  foreach ($item in @(Resolve-Path -Path $ResolvedPath -ErrorAction SilentlyContinue)) {
    if ($null -ne $item -and -not [string]::IsNullOrWhiteSpace([string]$item.Path)) {
      $matches.Add([string]$item.Path) | Out-Null
    }
  }

  return [string[]]@($matches.ToArray() | Sort-Object -Unique)
}

function Convert-GpNativePathToPosix {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $normalized = $Path -replace "\\", "/"
  if ($normalized -match "^([A-Za-z]):(/.*)?$") {
    $drive = $Matches[1].ToLowerInvariant()
    $rest = if ($Matches[2]) { $Matches[2] } else { "" }
    return "/$drive$rest"
  }

  return $normalized
}

function Convert-GpNativePathToWindows {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if ($Path -match "^/([A-Za-z])(\/.*)?$") {
    $drive = $Matches[1].ToUpperInvariant()
    $rest = if ($Matches[2]) { $Matches[2] -replace "/", "\" } else { "" }
    return "${drive}:$rest"
  }

  return ($Path -replace "/", "\")
}

function Resolve-GpPatternTokens {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Pattern,
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Tokens
  )

  $resolved = $Pattern
  foreach ($key in $Tokens.Keys) {
    $resolved = $resolved.Replace("{$key}", [string]$Tokens[$key])
  }
  return $resolved
}

function Get-GpJsonFile {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $resolvedPath = (Resolve-Path $Path).Path
  $json = Get-Content -Raw -Path $resolvedPath
  $command = Get-Command ConvertFrom-Json -ErrorAction Stop
  $supportsAsHashtable = $false
  foreach ($parameterSet in $command.ParameterSets) {
    foreach ($parameter in $parameterSet.Parameters) {
      if ($parameter.Name -eq "AsHashtable") {
        $supportsAsHashtable = $true
        break
      }
    }
    if ($supportsAsHashtable) {
      break
    }
  }

  if ($supportsAsHashtable) {
    return ($json | ConvertFrom-Json -AsHashtable)
  }

  return (Convert-GpJsonObjectToHashtable -Value ($json | ConvertFrom-Json))
}

function Get-GpManifestSchemaPath {
  return (Join-Path (Get-GpToolRoot) "schemas\\gnustep-packager.schema.json")
}

function Test-GpManifestSchema {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $issues = [System.Collections.Generic.List[string]]::new()
  $schemaPath = Get-GpManifestSchemaPath
  if (-not (Test-Path $schemaPath)) {
    $issues.Add("Manifest schema not found: $schemaPath") | Out-Null
    return [string[]]$issues.ToArray()
  }

  if (-not (Get-Command Test-Json -ErrorAction SilentlyContinue)) {
    return [string[]]$issues.ToArray()
  }

  $json = Get-Content -Raw -Path (Resolve-Path $Path).Path
  $schemaErrors = @()
  $isValid = Test-Json -Json $json -SchemaFile $schemaPath -ErrorVariable schemaErrors -ErrorAction SilentlyContinue
  if (-not $isValid) {
    foreach ($schemaError in @($schemaErrors)) {
      $message = [string]$schemaError.ToString()
      if (-not [string]::IsNullOrWhiteSpace($message)) {
        $issues.Add($message) | Out-Null
      }
    }

    if ($issues.Count -eq 0) {
      $issues.Add("Manifest JSON did not satisfy the documented schema.") | Out-Null
    }
  }

  return [string[]]$issues.ToArray()
}

function Get-GpRequestedProfiles {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Manifest
  )

  $profiles = [System.Collections.Generic.List[string]]::new()
  if ($Manifest.Contains("profiles")) {
    foreach ($profile in @($Manifest["profiles"])) {
      if (($profile -is [string]) -and (-not [string]::IsNullOrWhiteSpace($profile))) {
        $profiles.Add($profile.Trim()) | Out-Null
      }
    }
  }

  return [string[]]@($profiles | Select-Object -Unique)
}

function Resolve-GpProfileDefaultsPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ProfileName
  )

  $toolRoot = Get-GpToolRoot
  $profilePath = Join-Path $toolRoot ("defaults\\profiles\\{0}.json" -f $ProfileName)
  if (-not (Test-Path $profilePath)) {
    throw "Unknown manifest profile '$ProfileName'. Expected defaults file: $profilePath"
  }

  return $profilePath
}

function Get-GpDefaultManifest {
  param(
    [string[]]$Profiles = @()
  )

  $toolRoot = Get-GpToolRoot
  $merged = @{}

  foreach ($path in @(
    (Join-Path $toolRoot "defaults\\core\\defaults.json"),
    (Join-Path $toolRoot "defaults\\backends\\msi\\defaults.json"),
    (Join-Path $toolRoot "defaults\\backends\\appimage\\defaults.json")
  )) {
    $merged = Merge-GpHashtable -Base $merged -Overlay (Get-GpJsonFile -Path $path)
  }

  foreach ($profileName in @($Profiles)) {
    if (-not [string]::IsNullOrWhiteSpace($profileName)) {
      $merged = Merge-GpHashtable -Base $merged -Overlay (Get-GpJsonFile -Path (Resolve-GpProfileDefaultsPath -ProfileName $profileName))
    }
  }

  return $merged
}

function Resolve-GpManifestData {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Manifest
  )

  $defaults = Get-GpDefaultManifest -Profiles (Get-GpRequestedProfiles -Manifest $Manifest)
  $resolved = Merge-GpHashtable -Base $defaults -Overlay $Manifest
  $resolved = Apply-GpDeclarativeThemeDefaults -Manifest $resolved
  return (Apply-GpDeclarativePackagedDefaults -Manifest $resolved)
}

function Resolve-GpPackageVersionOverride {
  param(
    [string]$RequestedVersion
  )

  if (-not [string]::IsNullOrWhiteSpace($RequestedVersion)) {
    return $RequestedVersion
  }

  if (-not [string]::IsNullOrWhiteSpace($env:GP_PACKAGE_VERSION_OVERRIDE)) {
    return [string]$env:GP_PACKAGE_VERSION_OVERRIDE
  }

  return $null
}

function Apply-GpManifestOverrides {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Manifest,
    [string]$PackageVersion
  )

  $overridden = Copy-GpValue -Value $Manifest

  if (-not [string]::IsNullOrWhiteSpace($PackageVersion)) {
    if (-not $overridden.Contains("package") -or -not ($overridden["package"] -is [System.Collections.IDictionary])) {
      $overridden["package"] = @{}
    }
    $overridden["package"]["version"] = $PackageVersion
  }

  return $overridden
}

function Get-GpHostPlatform {
  try {
    $platform = [System.Environment]::OSVersion.Platform
    if ($platform -eq [System.PlatformID]::Win32NT) {
      return "windows"
    }

    if ($platform -eq [System.PlatformID]::Unix) {
      return "linux"
    }
  } catch {
  }

  if ($env:OS -eq "Windows_NT") {
    return "windows"
  }

  return "unknown"
}

function Get-GpHostDependencyProviders {
  $providers = [System.Collections.Generic.List[psobject]]::new()

  $providers.Add([pscustomobject]@{
    Id                      = "windows-msys2"
    Platform                = "windows"
    PackageManager          = "msys2"
    ManifestPlatformKey     = "windows"
    ManifestPackageListKey  = "msys2Packages"
    WorkflowInputName       = "msys2-packages"
    WorkflowOutputPrefix    = "msys2"
    DisplayName             = "Windows MSYS2"
  }) | Out-Null

  $providers.Add([pscustomobject]@{
    Id                      = "linux-apt"
    Platform                = "linux"
    PackageManager          = "apt"
    ManifestPlatformKey     = "linux"
    ManifestPackageListKey  = "aptPackages"
    WorkflowInputName       = "appimage-apt-packages"
    WorkflowOutputPrefix    = "apt"
    DisplayName             = "Linux apt"
  }) | Out-Null

  return @($providers.ToArray())
}

function Get-GpHostDependencyProvider {
  param(
    [string]$Id,
    [string]$Platform,
    [string]$PackageManager
  )

  foreach ($provider in @(Get-GpHostDependencyProviders)) {
    if (-not [string]::IsNullOrWhiteSpace($Id) -and $provider.Id -eq $Id) {
      return $provider
    }

    if (-not [string]::IsNullOrWhiteSpace($Platform) -and
        -not [string]::IsNullOrWhiteSpace($PackageManager) -and
        $provider.Platform -eq $Platform -and
        $provider.PackageManager -eq $PackageManager) {
      return $provider
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($Id)) {
    throw "Unsupported host dependency provider: $Id"
  }

  throw "Unsupported host dependency provider for platform '$Platform' and package manager '$PackageManager'."
}

function Get-GpNonEmptyStringList {
  param(
    [AllowNull()]
    [object[]]$Values
  )

  $items = [System.Collections.Generic.List[string]]::new()
  foreach ($value in @($Values)) {
    if ($value -is [string] -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
      $items.Add(([string]$value).Trim()) | Out-Null
    }
  }

  return [string[]]@($items.ToArray())
}

function Join-GpUniquePackageList {
  param(
    [AllowNull()]
    [object[]]$Values
  )

  $items = [System.Collections.Generic.List[string]]::new()
  foreach ($value in @($Values)) {
    if ($null -eq $value) {
      continue
    }

    foreach ($line in @(([string]$value) -split '\s+')) {
      $trimmed = $line.Trim()
      if (-not [string]::IsNullOrWhiteSpace($trimmed) -and -not $items.Contains($trimmed)) {
        $items.Add($trimmed) | Out-Null
      }
    }
  }

  return [string]::Join(' ', @($items))
}

function Get-GpManifestHostDependencyGroups {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Manifest
  )

  $hostDependencies = if ($Manifest.Contains("hostDependencies") -and ($Manifest["hostDependencies"] -is [System.Collections.IDictionary])) {
    $Manifest["hostDependencies"]
  } else {
    @{}
  }

  $groups = [System.Collections.Generic.List[psobject]]::new()
  foreach ($provider in @(Get-GpHostDependencyProviders)) {
    $platformConfig = if ($hostDependencies.Contains($provider.ManifestPlatformKey) -and ($hostDependencies[$provider.ManifestPlatformKey] -is [System.Collections.IDictionary])) {
      $hostDependencies[$provider.ManifestPlatformKey]
    } else {
      @{}
    }

    $packages = @(Get-GpNonEmptyStringList -Values @($platformConfig[$provider.ManifestPackageListKey]))
    if ($packages.Count -le 0) {
      continue
    }

    $groups.Add([pscustomobject]@{
      ProviderId             = $provider.Id
      Platform               = $provider.Platform
      PackageManager         = $provider.PackageManager
      ManifestPlatformKey    = $provider.ManifestPlatformKey
      ManifestPackageListKey = $provider.ManifestPackageListKey
      Packages               = [string[]]@($packages)
    }) | Out-Null
  }

  return @($groups.ToArray())
}

function Get-GpHostDependencies {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context
  )

  $groups = @(Get-GpManifestHostDependencyGroups -Manifest $Context.Manifest)
  $windowsMsys2 = @($groups | Where-Object { $_.ProviderId -eq "windows-msys2" } | Select-Object -First 1)
  $linuxApt = @($groups | Where-Object { $_.ProviderId -eq "linux-apt" } | Select-Object -First 1)

  return [pscustomobject]@{
    Groups = @($groups)
    WindowsMsys2Packages = [string[]]@($(if ($windowsMsys2.Count -gt 0) { $windowsMsys2[0].Packages } else { @() }))
    LinuxAptPackages = [string[]]@($(if ($linuxApt.Count -gt 0) { $linuxApt[0].Packages } else { @() }))
  }
}

function Get-GpHostDependencyPlan {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [string]$Backend
  )

  $platform = Get-GpHostPlatform
  $groups = [System.Collections.Generic.List[psobject]]::new()
  foreach ($group in @(Get-GpManifestHostDependencyGroups -Manifest $Context.Manifest)) {
    if ($group.Platform -ne $platform) {
      continue
    }

    $groups.Add([pscustomobject]@{
      ProviderId = $group.ProviderId
      Platform = $group.Platform
      PackageManager = $group.PackageManager
      Packages = [string[]]@($group.Packages)
      Backend = $(if (-not [string]::IsNullOrWhiteSpace($Backend)) { $Backend } else { $null })
    }) | Out-Null
  }

  return [pscustomobject]@{
    HostPlatform = $platform
    Groups = @($groups.ToArray())
  }
}

function Get-GpThemeTargetPlatform {
  param(
    [string]$Backend
  )

  if (-not [string]::IsNullOrWhiteSpace($Backend)) {
    $platform = Get-GpBackendRequiredPlatform -Backend $Backend
    if (-not [string]::IsNullOrWhiteSpace($platform)) {
      return $platform
    }
  }

  return Get-GpHostPlatform
}

function Test-GpThemeInputApplies {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$ThemeInput,
    [string]$Backend,
    [string]$Platform
  )

  $targetPlatform = if (-not [string]::IsNullOrWhiteSpace($Platform)) {
    $Platform
  } else {
    Get-GpThemeTargetPlatform -Backend $Backend
  }

  $platforms = @()
  if ($ThemeInput.Contains("platforms")) {
    $platforms = @($ThemeInput["platforms"])
  }

  foreach ($item in @($platforms)) {
    if (-not ($item -is [string])) {
      continue
    }

    $value = ([string]$item).Trim().ToLowerInvariant()
    if ($value -eq $targetPlatform) {
      return $true
    }

    if (-not [string]::IsNullOrWhiteSpace($Backend) -and $value -eq $Backend.ToLowerInvariant()) {
      return $true
    }
  }

  return $false
}

function Get-GpThemeInputs {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Manifest,
    [string]$Backend,
    [string]$Platform,
    [switch]$ActiveOnly
  )

  $items = [System.Collections.Generic.List[psobject]]::new()
  if (-not $Manifest.Contains("themeInputs")) {
    return @()
  }

  $index = 0
  foreach ($item in @($Manifest["themeInputs"])) {
    if (-not ($item -is [System.Collections.IDictionary])) {
      $index += 1
      continue
    }

    $applies = Test-GpThemeInputApplies -ThemeInput $item -Backend $Backend -Platform $Platform
    if ($ActiveOnly -and -not $applies) {
      $index += 1
      continue
    }

    $build = if ($item.Contains("build") -and ($item["build"] -is [System.Collections.IDictionary])) {
      $item["build"]
    } else {
      @{}
    }

    $items.Add([pscustomobject]@{
      Index = $index
      Name = $(if ($item.Contains("name")) { [string]$item["name"] } else { $null })
      Repo = $(if ($item.Contains("repo")) { [string]$item["repo"] } else { $null })
      Ref = $(if ($item.Contains("ref")) { [string]$item["ref"] } else { $null })
      Platforms = [string[]]@($item["platforms"])
      Required = [bool]($item.Contains("required") -and $item["required"])
      Default = [bool]($item.Contains("default") -and $item["default"])
      WorkspacePath = $(if ($item.Contains("workspacePath")) { [string]$item["workspacePath"] } else { $null })
      BuildCommand = $(if ($build.Contains("command")) { [string]$build["command"] } else { $null })
      InstallCommand = $(if ($build.Contains("installCommand")) { [string]$build["installCommand"] } else { $null })
      BuildEnvironment = $(if ($build.Contains("environment") -and ($build["environment"] -is [System.Collections.IDictionary])) { [hashtable](Copy-GpValue -Value $build["environment"]) } else { @{} })
      Applies = [bool]$applies
      Source = ("themeInputs[{0}]" -f $index)
    }) | Out-Null
    $index += 1
  }

  return @($items.ToArray())
}

function Apply-GpDeclarativeThemeDefaults {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Manifest
  )

  $resolved = Copy-GpValue -Value $Manifest
  $packagedDefaults = if ($resolved.Contains("packagedDefaults") -and ($resolved["packagedDefaults"] -is [System.Collections.IDictionary])) {
    $resolved["packagedDefaults"]
  } else {
    @{}
  }

  if ($packagedDefaults.Contains("defaultTheme") -and -not [string]::IsNullOrWhiteSpace([string]$packagedDefaults["defaultTheme"])) {
    return $resolved
  }

  $defaults = [System.Collections.Generic.List[string]]::new()
  foreach ($theme in @(Get-GpThemeInputs -Manifest $resolved)) {
    if ($theme.Default -and -not [string]::IsNullOrWhiteSpace([string]$theme.Name) -and -not $defaults.Contains([string]$theme.Name)) {
      $defaults.Add([string]$theme.Name) | Out-Null
    }
  }

  if ($defaults.Count -eq 1) {
    if (-not $resolved.Contains("packagedDefaults") -or -not ($resolved["packagedDefaults"] -is [System.Collections.IDictionary])) {
      $resolved["packagedDefaults"] = @{}
    }
    $resolved["packagedDefaults"]["defaultTheme"] = $defaults[0]
  }

  return $resolved
}

function Get-GpWorkflowHostSetupPlan {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [string]$Backend,
    [switch]$SkipDefaultHostSetup,
    [string]$AdditionalMsys2Packages,
    [string]$AdditionalAptPackages
  )

  $hostDependencies = Get-GpHostDependencies -Context $Context
  $errors = [System.Collections.Generic.List[string]]::new()
  $mode = if ($SkipDefaultHostSetup) { "verify-only" } else { "install-and-verify" }

  $manifestMsys2Packages = [string[]]@($hostDependencies.WindowsMsys2Packages)
  $manifestAptPackages = [string[]]@($hostDependencies.LinuxAptPackages)
  $additionalMsys2Text = Join-GpUniquePackageList -Values @($AdditionalMsys2Packages)
  $additionalAptText = Join-GpUniquePackageList -Values @($AdditionalAptPackages)

  if ($SkipDefaultHostSetup -and $Backend -eq "msi" -and -not [string]::IsNullOrWhiteSpace($additionalMsys2Text)) {
    $errors.Add('`msys2-packages` is not applied when `skip-default-host-setup: true`. Declare app-specific MSYS2 packages under `hostDependencies.windows.msys2Packages` or install them in your caller preflight.') | Out-Null
  }

  if ($SkipDefaultHostSetup -and $Backend -eq "appimage" -and -not [string]::IsNullOrWhiteSpace($additionalAptText)) {
    $errors.Add('`appimage-apt-packages` is not applied when `skip-default-host-setup: true`. Declare app-specific apt packages under `hostDependencies.linux.aptPackages` or install them in your caller preflight.') | Out-Null
  }

  $summary = if ($SkipDefaultHostSetup) {
    "Default host setup disabled; the workflow will rely on caller preflight and shared manifest-driven verification on the target runner."
  } else {
    "Default host setup enabled; the workflow will install the documented backend baseline plus manifest-declared and additive host packages before packaging."
  }

  return [pscustomobject]@{
    Backend = $Backend
    HostSetupMode = $mode
    Summary = $summary
    ShouldInstallManifestDependencies = (-not [bool]$SkipDefaultHostSetup)
    ManifestMsys2Packages = [string[]]@($manifestMsys2Packages)
    ManifestAptPackages = [string[]]@($manifestAptPackages)
    ManifestMsys2PackageText = Join-GpUniquePackageList -Values @($manifestMsys2Packages)
    ManifestAptPackageText = Join-GpUniquePackageList -Values @($manifestAptPackages)
    ResolvedMsys2PackageText = Join-GpUniquePackageList -Values @($AdditionalMsys2Packages, (Join-GpUniquePackageList -Values @($manifestMsys2Packages)))
    ResolvedAptPackageText = Join-GpUniquePackageList -Values @($AdditionalAptPackages, (Join-GpUniquePackageList -Values @($manifestAptPackages)))
    Errors = [string[]]@($errors.ToArray())
  }
}

function Get-GpManifestContext {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [string]$PackageVersion
  )

  $resolvedPath = (Resolve-Path $Path).Path
  $rawManifest = Get-GpJsonFile -Path $resolvedPath
  $versionOverride = Resolve-GpPackageVersionOverride -RequestedVersion $PackageVersion
  $resolvedManifest = Resolve-GpManifestData -Manifest $rawManifest
  $resolvedManifest = Apply-GpManifestOverrides -Manifest $resolvedManifest -PackageVersion $versionOverride
  $manifestRoot = Split-Path -Parent $resolvedPath
  $toolRoot = Get-GpToolRoot

  return [pscustomobject]@{
    ToolRoot               = $toolRoot
    ManifestPath           = $resolvedPath
    ManifestRoot           = $manifestRoot
    RawManifest            = $rawManifest
    Manifest               = $resolvedManifest
    PackageVersionOverride = $versionOverride
  }
}

function New-GpLaunchEnvironmentEntry {
  param(
    [AllowNull()]
    [string]$Value,
    [ValidateSet("override", "ifUnset")]
    [string]$Policy = "override"
  )

  return [ordered]@{
    value = $Value
    policy = $Policy
  }
}

function Get-GpNormalizedLaunchEnvironment {
  param(
    [AllowNull()]
    [object]$Environment
  )

  $normalized = @{}
  if (-not ($Environment -is [System.Collections.IDictionary])) {
    return $normalized
  }

  foreach ($key in $Environment.Keys) {
    if ([string]::IsNullOrWhiteSpace([string]$key)) {
      continue
    }

    $entry = $Environment[$key]
    if ($entry -is [System.Collections.IDictionary]) {
      $value = if ($entry.Contains("value")) { [string]$entry["value"] } else { $null }
      $policy = if ($entry.Contains("policy") -and -not [string]::IsNullOrWhiteSpace([string]$entry["policy"])) {
        [string]$entry["policy"]
      } else {
        "override"
      }
      $normalized[[string]$key] = New-GpLaunchEnvironmentEntry -Value $value -Policy $policy
    } else {
      $normalized[[string]$key] = New-GpLaunchEnvironmentEntry -Value ([string]$entry) -Policy "override"
    }
  }

  return $normalized
}

function Get-GpPackagedDefaults {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Manifest
  )

  function Get-GpPackagedDefaultScalarType {
    param(
      [Parameter(Mandatory = $true)]
      [AllowNull()]
      [object]$Value
    )

    if ($Value -is [string]) {
      return "string"
    }
    if ($Value -is [bool]) {
      return "bool"
    }
    if ($Value -is [byte] -or
        $Value -is [sbyte] -or
        $Value -is [int16] -or
        $Value -is [uint16] -or
        $Value -is [int32] -or
        $Value -is [uint32] -or
        $Value -is [int64] -or
        $Value -is [uint64]) {
      return "integer"
    }
    if ($Value -is [single] -or
        $Value -is [double] -or
        $Value -is [decimal]) {
      return "number"
    }

    return $null
  }

  $packagedDefaults = if ($Manifest.Contains("packagedDefaults") -and ($Manifest["packagedDefaults"] -is [System.Collections.IDictionary])) {
    $Manifest["packagedDefaults"]
  } else {
    @{}
  }

  $defaultTheme = if ($packagedDefaults.Contains("defaultTheme") -and -not [string]::IsNullOrWhiteSpace([string]$packagedDefaults["defaultTheme"])) {
    [string]$packagedDefaults["defaultTheme"]
  } else {
    $null
  }

  $packageId = $null
  if ($Manifest.Contains("package") -and ($Manifest["package"] -is [System.Collections.IDictionary]) -and
      $Manifest["package"].Contains("id") -and -not [string]::IsNullOrWhiteSpace([string]$Manifest["package"]["id"])) {
    $packageId = [string]$Manifest["package"]["id"]
  }

  $appDomainDefaults = $null
  if ($packagedDefaults.Contains("appDomain") -and ($packagedDefaults["appDomain"] -is [System.Collections.IDictionary])) {
    $appDomain = $packagedDefaults["appDomain"]
    $domainName = if ($appDomain.Contains("domain") -and -not [string]::IsNullOrWhiteSpace([string]$appDomain["domain"])) {
      [string]$appDomain["domain"]
    } else {
      $packageId
    }

    $entries = [System.Collections.Generic.List[psobject]]::new()
    if ($appDomain.Contains("values") -and ($appDomain["values"] -is [System.Collections.IDictionary])) {
      foreach ($key in ($appDomain["values"].Keys | Sort-Object)) {
        $value = $appDomain["values"][$key]
        $type = Get-GpPackagedDefaultScalarType -Value $value
        if (-not [string]::IsNullOrWhiteSpace([string]$key) -and -not [string]::IsNullOrWhiteSpace($type)) {
          $entries.Add([pscustomobject]@{
            Key = [string]$key
            Type = $type
            Value = $value
          }) | Out-Null
        }
      }
    }

    if (-not [string]::IsNullOrWhiteSpace($domainName) -and $entries.Count -gt 0) {
      $appDomainDefaults = [pscustomobject]@{
        Domain = $domainName
        Entries = @($entries.ToArray())
      }
    }
  }

  return [pscustomobject]@{
    DefaultTheme = $defaultTheme
    AppDomain = $appDomainDefaults
  }
}

function Apply-GpDeclarativePackagedDefaults {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Manifest
  )

  $resolved = Copy-GpValue -Value $Manifest
  $packagedDefaults = Get-GpPackagedDefaults -Manifest $resolved
  if ([string]::IsNullOrWhiteSpace([string]$packagedDefaults.DefaultTheme)) {
    return $resolved
  }

  if (-not $resolved.Contains("launch") -or -not ($resolved["launch"] -is [System.Collections.IDictionary])) {
    $resolved["launch"] = @{}
  }

  if (-not $resolved["launch"].Contains("env") -or -not ($resolved["launch"]["env"] -is [System.Collections.IDictionary])) {
    $resolved["launch"]["env"] = @{}
  }

  if (-not $resolved["launch"]["env"].Contains("GSTheme")) {
    $resolved["launch"]["env"]["GSTheme"] = New-GpLaunchEnvironmentEntry -Value $packagedDefaults.DefaultTheme -Policy "ifUnset"
  }

  return $resolved
}

function Test-GpManifest {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Manifest
  )

  $issues = [System.Collections.Generic.List[string]]::new()

  function Add-Issue {
    param([string]$Message)
    $issues.Add($Message) | Out-Null
  }

  function Test-StringValue {
    param([object]$Value)
    return ($Value -is [string]) -and (-not [string]::IsNullOrWhiteSpace($Value))
  }

  function Require-Object {
    param(
      [System.Collections.IDictionary]$Parent,
      [string]$Key,
      [string]$Label
    )

    if (-not $Parent.Contains($Key) -or -not ($Parent[$Key] -is [System.Collections.IDictionary])) {
      Add-Issue "Missing required object: $Label"
      return $null
    }
    return $Parent[$Key]
  }

  function Require-String {
    param(
      [System.Collections.IDictionary]$Parent,
      [string]$Key,
      [string]$Label
    )

    if (-not $Parent.Contains($Key) -or -not (Test-StringValue $Parent[$Key])) {
      Add-Issue "Missing required string: $Label"
    }
  }

  function Require-Boolean {
    param(
      [System.Collections.IDictionary]$Parent,
      [string]$Key,
      [string]$Label
    )

    if (-not $Parent.Contains($Key) -or -not ($Parent[$Key] -is [bool])) {
      Add-Issue "Missing required boolean: $Label"
    }
  }

  function Test-LaunchEnvEntry {
    param(
      [string]$Key,
      [AllowNull()]
      [object]$Value,
      [string]$Label
    )

    if ($Value -is [string]) {
      return
    }

    if (-not ($Value -is [System.Collections.IDictionary])) {
      Add-Issue "$Label.$Key must be a string or an object."
      return
    }

    if (-not $Value.Contains("value") -or -not ($Value["value"] -is [string])) {
      Add-Issue "$Label.$Key.value must be a string."
    }

    if ($Value.Contains("policy")) {
      if (-not (Test-StringValue $Value["policy"])) {
        Add-Issue "$Label.$Key.policy must be a non-empty string when present."
      } elseif ([string]$Value["policy"] -notin @("override", "ifUnset")) {
        Add-Issue "$Label.$Key.policy must be one of: override, ifUnset."
      }
    }
  }

  function Test-IntegerAtLeast {
    param(
      [AllowNull()]
      [object]$Value,
      [int]$Minimum
    )

    $parsedValue = 0
    return [int]::TryParse([string]$Value, [ref]$parsedValue) -and ($parsedValue -ge $Minimum)
  }

  function Test-PackageContractContentItem {
    param(
      [AllowNull()]
      [object]$Item,
      [string]$Label
    )

    if (-not ($Item -is [System.Collections.IDictionary])) {
      Add-Issue "$Label entries must be objects."
      return
    }

    if (-not $Item.Contains("kind") -or -not (Test-StringValue $Item["kind"])) {
      Add-Issue "$Label.kind must be a non-empty string."
      return
    }

    $kind = [string]$Item["kind"]
    $validKinds = @("notice-report", "update-runtime-config", "default-theme", "metadata-file", "updater-helper", "bundled-theme", "theme-resource")
    if ($kind -notin $validKinds) {
      Add-Issue "$Label.kind must be one of: $([string]::Join(', ', $validKinds))."
    }

    if ($Item.Contains("name") -and -not (Test-StringValue $Item["name"])) {
      Add-Issue "$Label.name must be a non-empty string when present."
    }

    if ($Item.Contains("value") -and -not (Test-StringValue $Item["value"])) {
      Add-Issue "$Label.value must be a non-empty string when present."
    }

    if ($Item.Contains("path") -and -not (Test-StringValue $Item["path"])) {
      Add-Issue "$Label.path must be a non-empty string when present."
    }

    if ($Item.Contains("theme") -and -not (Test-StringValue $Item["theme"])) {
      Add-Issue "$Label.theme must be a non-empty string when present."
    }

    if ($kind -eq "metadata-file" -and (-not $Item.Contains("path") -or -not (Test-StringValue $Item["path"]))) {
      Add-Issue "$Label.path is required when $Label.kind is metadata-file."
    }

    if ($kind -eq "bundled-theme" -and (-not $Item.Contains("name") -or -not (Test-StringValue $Item["name"]))) {
      Add-Issue "$Label.name is required when $Label.kind is bundled-theme."
    }

    if ($kind -eq "theme-resource") {
      if (-not $Item.Contains("theme") -or -not (Test-StringValue $Item["theme"])) {
        Add-Issue "$Label.theme is required when $Label.kind is theme-resource."
      }
      if (-not $Item.Contains("path") -or -not (Test-StringValue $Item["path"])) {
        Add-Issue "$Label.path is required when $Label.kind is theme-resource."
      }
    }
  }

  function Test-PackageContractSection {
    param(
      [AllowNull()]
      [object]$Section,
      [string]$Label
    )

    if ($null -eq $Section) {
      return
    }

    if (-not ($Section -is [System.Collections.IDictionary])) {
      Add-Issue "$Label must be an object when present."
      return
    }

    if ($Section.Contains("requiredPaths")) {
      foreach ($path in @($Section["requiredPaths"])) {
        if (-not (Test-StringValue $path)) {
          Add-Issue "$Label.requiredPaths must contain non-empty strings."
        }
      }
    }

    if ($Section.Contains("requiredContent")) {
      $index = 0
      foreach ($item in @($Section["requiredContent"])) {
        Test-PackageContractContentItem -Item $item -Label ("{0}.requiredContent[{1}]" -f $Label, $index)
        $index += 1
      }
    }
  }

  if (-not $Manifest.Contains("schemaVersion")) {
    Add-Issue "Missing required value: schemaVersion"
  } elseif ($Manifest["schemaVersion"] -ne 1) {
    Add-Issue "Unsupported schemaVersion '$($Manifest["schemaVersion"])'. Expected 1."
  }

  if ($Manifest.Contains("profiles")) {
    foreach ($profile in @($Manifest["profiles"])) {
      if (-not (($profile -is [string]) -and (-not [string]::IsNullOrWhiteSpace($profile)))) {
        Add-Issue "Manifest profiles must contain non-empty strings."
      }
    }
  }

  $package = Require-Object -Parent $Manifest -Key "package" -Label "package"
  if ($package) {
    Require-String -Parent $package -Key "id" -Label "package.id"
    Require-String -Parent $package -Key "name" -Label "package.name"
    Require-String -Parent $package -Key "version" -Label "package.version"
    Require-String -Parent $package -Key "manufacturer" -Label "package.manufacturer"
  }

  $pipeline = Require-Object -Parent $Manifest -Key "pipeline" -Label "pipeline"
  if ($pipeline) {
    Require-String -Parent $pipeline -Key "workingDirectory" -Label "pipeline.workingDirectory"
    $shell = Require-Object -Parent $pipeline -Key "shell" -Label "pipeline.shell"
    if ($shell) {
      Require-String -Parent $shell -Key "kind" -Label "pipeline.shell.kind"
    }

    $build = Require-Object -Parent $pipeline -Key "build" -Label "pipeline.build"
    if ($build) {
      Require-String -Parent $build -Key "command" -Label "pipeline.build.command"
    }

    $stage = Require-Object -Parent $pipeline -Key "stage" -Label "pipeline.stage"
    if ($stage) {
      Require-String -Parent $stage -Key "command" -Label "pipeline.stage.command"
      Require-String -Parent $stage -Key "outputRoot" -Label "pipeline.stage.outputRoot"
    }
  }

  $payload = Require-Object -Parent $Manifest -Key "payload" -Label "payload"
  if ($payload) {
    if (-not $payload.Contains("layoutVersion")) {
      Add-Issue "Missing required value: payload.layoutVersion"
    } elseif ($payload["layoutVersion"] -ne 1) {
      Add-Issue "Unsupported payload.layoutVersion '$($payload["layoutVersion"])'. Expected 1."
    }

    Require-String -Parent $payload -Key "stageRoot" -Label "payload.stageRoot"
    Require-String -Parent $payload -Key "appRoot" -Label "payload.appRoot"
    Require-String -Parent $payload -Key "runtimeRoot" -Label "payload.runtimeRoot"
    Require-String -Parent $payload -Key "metadataRoot" -Label "payload.metadataRoot"
  }

  $launch = Require-Object -Parent $Manifest -Key "launch" -Label "launch"
  if ($launch) {
    Require-String -Parent $launch -Key "entryRelativePath" -Label "launch.entryRelativePath"
    Require-String -Parent $launch -Key "workingDirectory" -Label "launch.workingDirectory"
    if ($launch.Contains("env")) {
      if (-not ($launch["env"] -is [System.Collections.IDictionary])) {
        Add-Issue "launch.env must be an object when present."
      } else {
        foreach ($key in $launch["env"].Keys) {
          Test-LaunchEnvEntry -Key ([string]$key) -Value $launch["env"][$key] -Label "launch.env"
        }
      }
    }
  }

  $outputs = Require-Object -Parent $Manifest -Key "outputs" -Label "outputs"
  if ($outputs) {
    foreach ($key in @("root", "packageRoot", "logRoot", "tempRoot", "validationRoot")) {
      Require-String -Parent $outputs -Key $key -Label ("outputs." + $key)
    }
  }

  if ($Manifest.Contains("hostDependencies")) {
    if (-not ($Manifest["hostDependencies"] -is [System.Collections.IDictionary])) {
      Add-Issue "hostDependencies must be an object when present."
    } else {
      $hostDependencies = $Manifest["hostDependencies"]
      foreach ($platform in @("windows", "linux")) {
        if (-not $hostDependencies.Contains($platform)) {
          continue
        }

        if (-not ($hostDependencies[$platform] -is [System.Collections.IDictionary])) {
          Add-Issue "hostDependencies.$platform must be an object when present."
          continue
        }

        $platformConfig = $hostDependencies[$platform]
        $listKey = $(if ($platform -eq "windows") { "msys2Packages" } else { "aptPackages" })
        if ($platformConfig.Contains($listKey)) {
          foreach ($packageName in @($platformConfig[$listKey])) {
            if (-not (($packageName -is [string]) -and (-not [string]::IsNullOrWhiteSpace([string]$packageName)))) {
              Add-Issue "hostDependencies.$platform.$listKey must contain non-empty strings."
            }
          }
        }
      }
    }
  }

  if ($Manifest.Contains("themeInputs")) {
    if (-not ($Manifest["themeInputs"] -is [System.Collections.IEnumerable]) -or ($Manifest["themeInputs"] -is [string])) {
      Add-Issue "themeInputs must be an array when present."
    } else {
      $themeIndex = 0
      $defaultByPlatform = @{}
      foreach ($themeInput in @($Manifest["themeInputs"])) {
        $label = "themeInputs[$themeIndex]"
        if (-not ($themeInput -is [System.Collections.IDictionary])) {
          Add-Issue "$label must be an object."
          $themeIndex += 1
          continue
        }

        if (-not $themeInput.Contains("name") -or -not (Test-StringValue $themeInput["name"])) {
          Add-Issue "$label.name must be a non-empty string."
        }

        $hasRepo = $themeInput.Contains("repo") -and (Test-StringValue $themeInput["repo"])
        $hasWorkspacePath = $themeInput.Contains("workspacePath") -and (Test-StringValue $themeInput["workspacePath"])
        if (-not $hasRepo -and -not $hasWorkspacePath) {
          Add-Issue "$label must declare either repo or workspacePath."
        }

        if ($themeInput.Contains("repo") -and -not (Test-StringValue $themeInput["repo"])) {
          Add-Issue "$label.repo must be a non-empty string when present."
        }
        if ($themeInput.Contains("ref") -and -not (Test-StringValue $themeInput["ref"])) {
          Add-Issue "$label.ref must be a non-empty string when present."
        }
        if ($themeInput.Contains("workspacePath") -and -not (Test-StringValue $themeInput["workspacePath"])) {
          Add-Issue "$label.workspacePath must be a non-empty string when present."
        }
        if (-not $themeInput.Contains("required") -or -not ($themeInput["required"] -is [bool])) {
          Add-Issue "$label.required must be a boolean."
        }
        if ($themeInput.Contains("default") -and -not ($themeInput["default"] -is [bool])) {
          Add-Issue "$label.default must be a boolean when present."
        }

        if (-not $themeInput.Contains("platforms")) {
          Add-Issue "$label.platforms must contain at least one platform."
        } else {
          $platformValues = @($themeInput["platforms"])
          if ($platformValues.Count -eq 0) {
            Add-Issue "$label.platforms must contain at least one platform."
          }
          foreach ($platformValue in $platformValues) {
            if (-not (Test-StringValue $platformValue)) {
              Add-Issue "$label.platforms must contain non-empty strings."
              continue
            }
            if ([string]$platformValue -notin @("windows", "linux", "msi", "appimage")) {
              Add-Issue "$label.platforms entries must be one of: windows, linux, msi, appimage."
            }
            if ($themeInput.Contains("default") -and $themeInput["default"]) {
              $platformKey = [string]$platformValue
              if ($defaultByPlatform.ContainsKey($platformKey)) {
                Add-Issue ("Only one default theme input may apply to platform '{0}'." -f $platformKey)
              } else {
                $defaultByPlatform[$platformKey] = [string]$themeInput["name"]
              }
            }
          }
        }

        if ($themeInput.Contains("build")) {
          if (-not ($themeInput["build"] -is [System.Collections.IDictionary])) {
            Add-Issue "$label.build must be an object when present."
          } else {
            $build = $themeInput["build"]
            foreach ($buildKey in @("command", "installCommand")) {
              if ($build.Contains($buildKey) -and -not (Test-StringValue $build[$buildKey])) {
                Add-Issue "$label.build.$buildKey must be a non-empty string when present."
              }
            }
            if ($build.Contains("environment")) {
              if (-not ($build["environment"] -is [System.Collections.IDictionary])) {
                Add-Issue "$label.build.environment must be an object when present."
              } else {
                foreach ($environmentKey in @($build["environment"].Keys)) {
                  if (-not (Test-StringValue $environmentKey) -or -not ($build["environment"][$environmentKey] -is [string])) {
                    Add-Issue "$label.build.environment entries must be string keys and string values."
                  }
                }
              }
            }
          }
        }

        $themeIndex += 1
      }
    }
  }

  if ($Manifest.Contains("packagedDefaults")) {
    if (-not ($Manifest["packagedDefaults"] -is [System.Collections.IDictionary])) {
      Add-Issue "packagedDefaults must be an object when present."
    } else {
      $packagedDefaults = $Manifest["packagedDefaults"]
      if ($packagedDefaults.Contains("defaultTheme") -and -not (Test-StringValue $packagedDefaults["defaultTheme"])) {
        Add-Issue "packagedDefaults.defaultTheme must be a non-empty string when present."
      }

      if ($packagedDefaults.Contains("defaultTheme") -and (Test-StringValue $packagedDefaults["defaultTheme"])) {
        $launchEnv = if ($Manifest.Contains("launch") -and ($Manifest["launch"] -is [System.Collections.IDictionary]) -and $Manifest["launch"].Contains("env") -and ($Manifest["launch"]["env"] -is [System.Collections.IDictionary])) {
          $Manifest["launch"]["env"]
        } else {
          @{}
        }

        if ($launchEnv.Contains("GSTheme")) {
          $declaredThemeValue = $null
          $declaredThemePolicy = "override"
          $themeEntry = $launchEnv["GSTheme"]
          if ($themeEntry -is [System.Collections.IDictionary]) {
            if ($themeEntry.Contains("value")) {
              $declaredThemeValue = [string]$themeEntry["value"]
            }
            if ($themeEntry.Contains("policy") -and (Test-StringValue $themeEntry["policy"])) {
              $declaredThemePolicy = [string]$themeEntry["policy"]
            }
          } elseif ($themeEntry -is [string]) {
            $declaredThemeValue = [string]$themeEntry
          }

          if ($declaredThemeValue -ne [string]$packagedDefaults["defaultTheme"]) {
            Add-Issue "packagedDefaults.defaultTheme must match launch.env.GSTheme when both are present."
          }
          if ($declaredThemePolicy -ne "ifUnset") {
            Add-Issue "launch.env.GSTheme.policy must be 'ifUnset' when packagedDefaults.defaultTheme is declared."
          }
        }
      }

      if ($packagedDefaults.Contains("appDomain")) {
        if (-not ($packagedDefaults["appDomain"] -is [System.Collections.IDictionary])) {
          Add-Issue "packagedDefaults.appDomain must be an object when present."
        } else {
          $appDomain = $packagedDefaults["appDomain"]
          if ($appDomain.Contains("domain") -and -not (Test-StringValue $appDomain["domain"])) {
            Add-Issue "packagedDefaults.appDomain.domain must be a non-empty string when present."
          }

          if (-not $appDomain.Contains("values")) {
            Add-Issue "packagedDefaults.appDomain.values must be present when packagedDefaults.appDomain is declared."
          } elseif (-not ($appDomain["values"] -is [System.Collections.IDictionary])) {
            Add-Issue "packagedDefaults.appDomain.values must be an object."
          } elseif (@($appDomain["values"].Keys).Count -eq 0) {
            Add-Issue "packagedDefaults.appDomain.values must contain at least one key."
          } else {
            foreach ($key in @($appDomain["values"].Keys)) {
              if (-not (Test-StringValue $key)) {
                Add-Issue "packagedDefaults.appDomain.values keys must be non-empty strings."
                continue
              }

              if ([string]$key -eq "GSTheme") {
                Add-Issue "packagedDefaults.appDomain.values.GSTheme is not supported; use packagedDefaults.defaultTheme instead."
                continue
              }

              $value = $appDomain["values"][$key]
              $supported = ($value -is [string]) -or
                ($value -is [bool]) -or
                ($value -is [byte]) -or
                ($value -is [sbyte]) -or
                ($value -is [int16]) -or
                ($value -is [uint16]) -or
                ($value -is [int32]) -or
                ($value -is [uint32]) -or
                ($value -is [int64]) -or
                ($value -is [uint64]) -or
                ($value -is [single]) -or
                ($value -is [double]) -or
                ($value -is [decimal])
              if (-not $supported) {
                Add-Issue ("packagedDefaults.appDomain.values.{0} must be a string, boolean, integer, or number." -f [string]$key)
              }
            }
          }
        }
      }
    }
  }

  $resolvedDefaultTheme = $null
  if ($Manifest.Contains("packagedDefaults") -and ($Manifest["packagedDefaults"] -is [System.Collections.IDictionary]) -and
      $Manifest["packagedDefaults"].Contains("defaultTheme") -and (Test-StringValue $Manifest["packagedDefaults"]["defaultTheme"])) {
    $resolvedDefaultTheme = [string]$Manifest["packagedDefaults"]["defaultTheme"]
  }
  if (-not [string]::IsNullOrWhiteSpace($resolvedDefaultTheme) -and $Manifest.Contains("themeInputs")) {
    $themeDefaults = @(Get-GpThemeInputs -Manifest $Manifest | Where-Object { $_.Default })
    foreach ($themeDefault in @($themeDefaults)) {
      if ([string]$themeDefault.Name -ne $resolvedDefaultTheme) {
        Add-Issue "packagedDefaults.defaultTheme must match the default theme input when both are present."
      }
    }

    $declaredThemeNames = @(Get-GpThemeInputs -Manifest $Manifest | ForEach-Object { [string]$_.Name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    $hasDeclaredDefaultTheme = $resolvedDefaultTheme -in $declaredThemeNames
    if (-not $hasDeclaredDefaultTheme) {
      $stageRoot = if ($Manifest.Contains("payload") -and ($Manifest["payload"] -is [System.Collections.IDictionary]) -and $Manifest["payload"].Contains("stageRoot") -and (Test-StringValue $Manifest["payload"]["stageRoot"])) {
        Resolve-GpPathRelativeToBase -BasePath (Get-Location).Path -Path ([string]$Manifest["payload"]["stageRoot"])
      } else {
        $null
      }
      $stagedThemePresent = $false
      if (-not [string]::IsNullOrWhiteSpace($stageRoot)) {
        foreach ($candidate in @(Get-GpBundledThemeCandidatePaths -ThemeName $resolvedDefaultTheme)) {
          if (Test-Path (Resolve-GpPathRelativeToBase -BasePath $stageRoot -Path $candidate)) {
            $stagedThemePresent = $true
            break
          }
        }
      }
      if (-not $stagedThemePresent) {
        Add-Issue "packagedDefaults.defaultTheme must name a declared themeInputs entry or an already staged bundled theme."
      }
    }
  }

  $validation = Require-Object -Parent $Manifest -Key "validation" -Label "validation"
  if ($validation) {
    $smoke = Require-Object -Parent $validation -Key "smoke" -Label "validation.smoke"
    if ($smoke) {
      Require-Boolean -Parent $smoke -Key "enabled" -Label "validation.smoke.enabled"
      Require-String -Parent $smoke -Key "kind" -Label "validation.smoke.kind"
    }

    $logs = Require-Object -Parent $validation -Key "logs" -Label "validation.logs"
    if ($logs) {
      Require-Boolean -Parent $logs -Key "retainOnSuccess" -Label "validation.logs.retainOnSuccess"
    }

    Test-PackageContractSection -Section $(if ($validation.Contains("packageContract")) { $validation["packageContract"] } else { $null }) -Label "validation.packageContract"
    Test-PackageContractSection -Section $(if ($validation.Contains("installedResult")) { $validation["installedResult"] } else { $null }) -Label "validation.installedResult"
  }

  if ($Manifest.Contains("updates")) {
    if (-not ($Manifest["updates"] -is [System.Collections.IDictionary])) {
      Add-Issue "updates must be an object when present."
    } else {
      $updates = $Manifest["updates"]

      if ($updates.Contains("enabled") -and -not ($updates["enabled"] -is [bool])) {
        Add-Issue "updates.enabled must be a boolean when present."
      }

      if ($updates.Contains("provider")) {
        if (-not (Test-StringValue $updates["provider"])) {
          Add-Issue "updates.provider must be a non-empty string when present."
        } elseif ([string]$updates["provider"] -ne "github-release-feed") {
          Add-Issue "updates.provider must be 'github-release-feed' when present."
        }
      }

      if ($updates.Contains("channel") -and -not (Test-StringValue $updates["channel"])) {
        Add-Issue "updates.channel must be a non-empty string when present."
      }

      if ($updates.Contains("feedUrl") -and ($updates["feedUrl"] -ne $null) -and (-not ($updates["feedUrl"] -is [string]))) {
        Add-Issue "updates.feedUrl must be a string when present."
      }

      if ($updates.Contains("minimumCheckIntervalHours") -and (-not (Test-IntegerAtLeast -Value $updates["minimumCheckIntervalHours"] -Minimum 1))) {
        Add-Issue "updates.minimumCheckIntervalHours must be an integer greater than or equal to 1."
      }

      if ($updates.Contains("startupDelaySeconds") -and (-not (Test-IntegerAtLeast -Value $updates["startupDelaySeconds"] -Minimum 0))) {
        Add-Issue "updates.startupDelaySeconds must be an integer greater than or equal to 0."
      }

      if ($updates.Contains("github")) {
        if (-not ($updates["github"] -is [System.Collections.IDictionary])) {
          Add-Issue "updates.github must be an object when present."
        } else {
          $github = $updates["github"]
          foreach ($optionalKey in @("owner", "repo", "tagPattern", "releaseNotesUrlPattern")) {
            if ($github.Contains($optionalKey) -and ($github[$optionalKey] -ne $null) -and (-not ($github[$optionalKey] -is [string]))) {
              Add-Issue "updates.github.$optionalKey must be a string when present."
            }
          }
        }
      }
    }
  }

  if ($Manifest.Contains("backends") -and ($Manifest["backends"] -is [System.Collections.IDictionary])) {
    $backends = $Manifest["backends"]

    if ($backends.Contains("msi") -and ($backends["msi"] -is [System.Collections.IDictionary])) {
      $msi = $backends["msi"]
      if ($msi.Contains("enabled") -and $msi["enabled"]) {
        Require-String -Parent $msi -Key "upgradeCode" -Label "backends.msi.upgradeCode"
        Require-String -Parent $msi -Key "artifactNamePattern" -Label "backends.msi.artifactNamePattern"

        if ($msi.Contains("unresolvedDependencyPolicy")) {
          if (-not (Test-StringValue $msi["unresolvedDependencyPolicy"])) {
            Add-Issue "backends.msi.unresolvedDependencyPolicy must be a non-empty string when present."
          } elseif ([string]$msi["unresolvedDependencyPolicy"] -notin @("fail", "warn")) {
            Add-Issue "backends.msi.unresolvedDependencyPolicy must be one of: fail, warn."
          }
        }

        if ($msi.Contains("updates")) {
          if (-not ($msi["updates"] -is [System.Collections.IDictionary])) {
            Add-Issue "backends.msi.updates must be an object when present."
          } else {
            $msiUpdates = $msi["updates"]
            if ($msiUpdates.Contains("feedUrl") -and ($msiUpdates["feedUrl"] -ne $null) -and (-not ($msiUpdates["feedUrl"] -is [string]))) {
              Add-Issue "backends.msi.updates.feedUrl must be a string when present."
            }
          }
        }
      }
    }

    if ($backends.Contains("appimage") -and ($backends["appimage"] -is [System.Collections.IDictionary])) {
      $appimage = $backends["appimage"]
      if ($appimage.Contains("enabled") -and $appimage["enabled"]) {
        Require-String -Parent $appimage -Key "desktopEntryName" -Label "backends.appimage.desktopEntryName"
        Require-String -Parent $appimage -Key "iconRelativePath" -Label "backends.appimage.iconRelativePath"
        Require-String -Parent $appimage -Key "artifactNamePattern" -Label "backends.appimage.artifactNamePattern"
        if ($appimage.Contains("iconRelativePath") -and (Test-StringValue $appimage["iconRelativePath"])) {
          $iconRelativePath = [string]$appimage["iconRelativePath"]
          if (-not $iconRelativePath.EndsWith(".png", [System.StringComparison]::OrdinalIgnoreCase)) {
            Add-Issue "backends.appimage.iconRelativePath must point to a staged .png icon for AppImage packaging."
          }
        }

        if ($appimage.Contains("smoke")) {
          if (-not ($appimage["smoke"] -is [System.Collections.IDictionary])) {
            Add-Issue "backends.appimage.smoke must be an object when present."
          } else {
            $appimageSmoke = $appimage["smoke"]
            $validSmokeModes = @("launch-only", "open-file", "custom-arguments", "marker-file")

            if ($appimageSmoke.Contains("mode")) {
              if (-not (Test-StringValue $appimageSmoke["mode"])) {
                Add-Issue "backends.appimage.smoke.mode must be a non-empty string when present."
              } elseif ([string]$appimageSmoke["mode"] -notin $validSmokeModes) {
                Add-Issue "backends.appimage.smoke.mode must be one of: launch-only, open-file, custom-arguments, marker-file."
              } elseif (($appimageSmoke["mode"] -eq "open-file") -and (-not $appimageSmoke.Contains("documentStageRelativePath") -or -not (Test-StringValue $appimageSmoke["documentStageRelativePath"]))) {
                Add-Issue "backends.appimage.smoke.documentStageRelativePath is required when backends.appimage.smoke.mode is open-file."
              }
            }

            if ($appimageSmoke.Contains("startupSeconds")) {
              $startupSecondsValue = 0
              if (-not [int]::TryParse([string]$appimageSmoke["startupSeconds"], [ref]$startupSecondsValue) -or ($startupSecondsValue -lt 1)) {
                Add-Issue "backends.appimage.smoke.startupSeconds must be an integer greater than or equal to 1."
              }
            }
          }
        }

        if ($appimage.Contains("validation")) {
          if (-not ($appimage["validation"] -is [System.Collections.IDictionary])) {
            Add-Issue "backends.appimage.validation must be an object when present."
          } else {
            $appimageValidation = $appimage["validation"]
            if ($appimageValidation.Contains("runtimeClosure")) {
              if (-not (Test-StringValue $appimageValidation["runtimeClosure"])) {
                Add-Issue "backends.appimage.validation.runtimeClosure must be a non-empty string when present."
              } elseif ([string]$appimageValidation["runtimeClosure"] -notin @("strict", "off")) {
                Add-Issue "backends.appimage.validation.runtimeClosure must be one of: strict, off."
              }
            }
          }
        }

        if ($appimage.Contains("updates")) {
          if (-not ($appimage["updates"] -is [System.Collections.IDictionary])) {
            Add-Issue "backends.appimage.updates must be an object when present."
          } else {
            $appimageUpdates = $appimage["updates"]

            if ($appimageUpdates.Contains("feedUrl") -and ($appimageUpdates["feedUrl"] -ne $null) -and (-not ($appimageUpdates["feedUrl"] -is [string]))) {
              Add-Issue "backends.appimage.updates.feedUrl must be a string when present."
            }

            if ($appimageUpdates.Contains("embedUpdateInformation") -and -not ($appimageUpdates["embedUpdateInformation"] -is [bool])) {
              Add-Issue "backends.appimage.updates.embedUpdateInformation must be a boolean when present."
            }

            foreach ($optionalKey in @("updateInformation", "releaseSelector", "zsyncArtifactNamePattern")) {
              if ($appimageUpdates.Contains($optionalKey) -and ($appimageUpdates[$optionalKey] -ne $null) -and (-not ($appimageUpdates[$optionalKey] -is [string]))) {
                Add-Issue "backends.appimage.updates.$optionalKey must be a string when present."
              }
            }
          }
        }
      }
    }
  }

  if ($Manifest.Contains("updates") -and ($Manifest["updates"] -is [System.Collections.IDictionary])) {
    $updates = $Manifest["updates"]
    if ($updates.Contains("enabled") -and $updates["enabled"]) {
      $github = if ($updates.Contains("github") -and ($updates["github"] -is [System.Collections.IDictionary])) { $updates["github"] } else { $null }
      if ($null -eq $github) {
        Add-Issue "updates.github must be an object when updates.enabled is true."
      } else {
        foreach ($requiredKey in @("owner", "repo", "tagPattern")) {
          if (-not $github.Contains($requiredKey) -or -not (Test-StringValue $github[$requiredKey])) {
            Add-Issue "Missing required string: updates.github.$requiredKey"
          }
        }
      }

      $sharedFeedUrl = if ($updates.Contains("feedUrl") -and (Test-StringValue $updates["feedUrl"])) { [string]$updates["feedUrl"] } else { $null }
      foreach ($backendName in @(Get-GpEnabledBackends -Manifest $Manifest)) {
        $backendFeedUrl = $null
        if ($Manifest["backends"].Contains($backendName)) {
          $backendConfig = $Manifest["backends"][$backendName]
          if (($backendConfig -is [System.Collections.IDictionary]) -and $backendConfig.Contains("updates") -and ($backendConfig["updates"] -is [System.Collections.IDictionary])) {
            $backendUpdates = $backendConfig["updates"]
            if ($backendUpdates.Contains("feedUrl") -and (Test-StringValue $backendUpdates["feedUrl"])) {
              $backendFeedUrl = [string]$backendUpdates["feedUrl"]
            }
          }
        }

        if ([string]::IsNullOrWhiteSpace($backendFeedUrl) -and [string]::IsNullOrWhiteSpace($sharedFeedUrl)) {
          Add-Issue "A feed URL is required for backend '$backendName' when updates.enabled is true. Set updates.feedUrl or backends.$backendName.updates.feedUrl."
        }
      }
    }
  }

  if ($Manifest.Contains("compliance")) {
    if (-not ($Manifest["compliance"] -is [System.Collections.IDictionary])) {
      Add-Issue "compliance must be an object when present."
    } else {
      $compliance = $Manifest["compliance"]
      if ($compliance.Contains("runtimeNotices")) {
        foreach ($entry in @($compliance["runtimeNotices"])) {
          if (-not ($entry -is [System.Collections.IDictionary])) {
            Add-Issue "compliance.runtimeNotices entries must be objects."
            continue
          }

          if (-not $entry.Contains("name") -or -not (Test-StringValue $entry["name"])) {
            Add-Issue "Missing required string: compliance.runtimeNotices[].name"
          }

          foreach ($optionalKey in @("version", "license", "source", "homepage", "stageRelativePath")) {
            if ($entry.Contains($optionalKey) -and ($entry[$optionalKey] -ne $null) -and (-not ($entry[$optionalKey] -is [string]))) {
              Add-Issue "compliance.runtimeNotices[].$optionalKey must be a string when present."
            }
          }
        }
      }
    }
  }

  return [string[]]$issues.ToArray()
}

function Get-GpEnabledBackends {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Manifest
  )

  $enabled = [System.Collections.Generic.List[string]]::new()

  if ($Manifest.Contains("backends") -and ($Manifest["backends"] -is [System.Collections.IDictionary])) {
    foreach ($backendName in @("msi", "appimage")) {
      if ($Manifest["backends"].Contains($backendName)) {
        $backend = $Manifest["backends"][$backendName]
        if (($backend -is [System.Collections.IDictionary]) -and $backend.Contains("enabled") -and $backend["enabled"]) {
          $enabled.Add($backendName) | Out-Null
        }
      }
    }
  }

  return [string[]]$enabled.ToArray()
}

function Test-GpBackendEnabled {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Manifest,
    [Parameter(Mandatory = $true)]
    [string]$Backend
  )

  return $Backend -in @(Get-GpEnabledBackends -Manifest $Manifest)
}

function Get-GpBackendRequiredPlatform {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Backend
  )

  switch ($Backend) {
    "msi" { return "windows" }
    "appimage" { return "linux" }
    default { return $null }
  }
}

function Get-GpBackendSupport {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Backend
  )

  $hostEnvironment = Get-GpHostEnvironment
  $requiredPlatform = Get-GpBackendRequiredPlatform -Backend $Backend
  $supported = [string]::IsNullOrWhiteSpace($requiredPlatform) -or ($requiredPlatform -eq $hostEnvironment.Platform)

  return [pscustomobject]@{
    Backend          = $Backend
    HostPlatform     = $hostEnvironment.Platform
    RequiredPlatform = $requiredPlatform
    Supported        = [bool]$supported
  }
}

function Resolve-GpManifestPath {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [string]$RelativePath
  )

  return Resolve-GpPathRelativeToBase -BasePath $Context.ManifestRoot -Path $RelativePath
}

function Resolve-GpStagePath {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [string]$RelativePath
  )

  $stageRoot = Resolve-GpManifestPath -Context $Context -RelativePath $Context.Manifest["payload"]["stageRoot"]
  return Resolve-GpPathRelativeToBase -BasePath $stageRoot -Path $RelativePath
}

function Resolve-GpBackendPath {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [string]$RelativePath,
    [Parameter(Mandatory = $true)]
    [string]$Backend
  )

  $nativePath = Resolve-GpStagePath -Context $Context -RelativePath $RelativePath
  switch ($Backend) {
    "msi" { return (Convert-GpNativePathToWindows -Path $nativePath) }
    "appimage" { return (Convert-GpNativePathToPosix -Path $nativePath) }
    default { return $nativePath }
  }
}

function Get-GpHostEnvironment {
  $platform = if ($IsWindows) {
    "windows"
  } elseif ($IsLinux) {
    "linux"
  } elseif ($IsMacOS) {
    "macos"
  } else {
    "unknown"
  }

  return [pscustomobject]@{
    Platform      = $platform
    PwshVersion   = $PSVersionTable.PSVersion.ToString()
    CurrentPath   = (Get-Location).Path
    ToolRoot      = Get-GpToolRoot
  }
}

function Get-GpComplianceEntries {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Manifest
  )

  $entries = [System.Collections.Generic.List[hashtable]]::new()
  if ($Manifest.Contains("compliance") -and ($Manifest["compliance"] -is [System.Collections.IDictionary])) {
    $compliance = $Manifest["compliance"]
    if ($compliance.Contains("runtimeNotices")) {
      foreach ($entry in @($compliance["runtimeNotices"])) {
        if ($entry -is [System.Collections.IDictionary]) {
          $entries.Add([hashtable](Copy-GpValue -Value $entry)) | Out-Null
        }
      }
    }
  }

  return [hashtable[]]@($entries.ToArray())
}

function Get-GpFileSha256 {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (-not (Test-Path $Path)) {
    return $null
  }

  return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
}

function Get-GpPackageDisplayName {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Manifest
  )

  $package = $Manifest["package"]
  if ($package.Contains("displayName") -and -not [string]::IsNullOrWhiteSpace([string]$package["displayName"])) {
    return [string]$package["displayName"]
  }

  return [string]$package["name"]
}

function Get-GpArtifactSidecarPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ArtifactPath,
    [Parameter(Mandatory = $true)]
    [string]$Suffix
  )

  $artifactDirectory = Split-Path -Parent $ArtifactPath
  $artifactBaseName = [System.IO.Path]::GetFileNameWithoutExtension($ArtifactPath)
  return (Join-Path $artifactDirectory ("{0}.{1}" -f $artifactBaseName, $Suffix))
}

function Get-GpUpdateProviderKind {
  return "github-release-feed"
}

function Get-GpUpdatePlatform {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Backend
  )

  switch ($Backend) {
    "msi" { return "windows-x64" }
    "appimage" { return "linux-x64" }
    default { return $Backend }
  }
}

function Get-GpUpdateRuntimeConfigRelativePath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$MetadataRootRelative
  )

  return (Join-Path (Join-Path $MetadataRootRelative "updates") "gnustep-packager-update.json")
}

function Get-GpUpdateFeedSidecarPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ArtifactPath
  )

  return (Get-GpArtifactSidecarPath -ArtifactPath $ArtifactPath -Suffix "update-feed.json")
}

function Get-GpUpdateSettings {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [string]$Backend
  )

  $manifest = $Context.Manifest
  $package = $manifest["package"]
  $payload = $manifest["payload"]
  $updates = if ($manifest.Contains("updates") -and ($manifest["updates"] -is [System.Collections.IDictionary])) {
    $manifest["updates"]
  } else {
    @{}
  }
  $backendConfig = if ($manifest.Contains("backends") -and ($manifest["backends"] -is [System.Collections.IDictionary]) -and $manifest["backends"].Contains($Backend) -and ($manifest["backends"][$Backend] -is [System.Collections.IDictionary])) {
    $manifest["backends"][$Backend]
  } else {
    @{}
  }
  $backendUpdates = if ($backendConfig.Contains("updates") -and ($backendConfig["updates"] -is [System.Collections.IDictionary])) {
    $backendConfig["updates"]
  } else {
    @{}
  }
  $github = if ($updates.Contains("github") -and ($updates["github"] -is [System.Collections.IDictionary])) {
    $updates["github"]
  } else {
    @{}
  }

  $provider = if ($updates.Contains("provider") -and -not [string]::IsNullOrWhiteSpace([string]$updates["provider"])) {
    [string]$updates["provider"]
  } else {
    Get-GpUpdateProviderKind
  }
  $channel = if ($updates.Contains("channel") -and -not [string]::IsNullOrWhiteSpace([string]$updates["channel"])) {
    [string]$updates["channel"]
  } else {
    "stable"
  }
  $githubOwner = if ($github.Contains("owner")) { [string]$github["owner"] } else { $null }
  $githubRepo = if ($github.Contains("repo")) { [string]$github["repo"] } else { $null }
  $tagPattern = if ($github.Contains("tagPattern") -and -not [string]::IsNullOrWhiteSpace([string]$github["tagPattern"])) {
    [string]$github["tagPattern"]
  } else {
    "v{version}"
  }
  $tokenMap = @{
    name = [string]$package["name"]
    version = [string]$package["version"]
    packageId = [string]$package["id"]
    backend = $Backend
    channel = $channel
    owner = $(if ($null -ne $githubOwner) { $githubOwner } else { "" })
    repo = $(if ($null -ne $githubRepo) { $githubRepo } else { "" })
  }
  $resolvedTag = Resolve-GpPatternTokens -Pattern $tagPattern -Tokens $tokenMap
  $releaseNotesUrlPattern = if ($github.Contains("releaseNotesUrlPattern") -and -not [string]::IsNullOrWhiteSpace([string]$github["releaseNotesUrlPattern"])) {
    [string]$github["releaseNotesUrlPattern"]
  } elseif (-not [string]::IsNullOrWhiteSpace($githubOwner) -and -not [string]::IsNullOrWhiteSpace($githubRepo)) {
    "https://github.com/{owner}/{repo}/releases/tag/{tag}"
  } else {
    $null
  }
  $releaseNotesUrl = if (-not [string]::IsNullOrWhiteSpace($releaseNotesUrlPattern)) {
    Resolve-GpPatternTokens -Pattern $releaseNotesUrlPattern -Tokens (@{
      owner = $(if ($null -ne $githubOwner) { $githubOwner } else { "" })
      repo = $(if ($null -ne $githubRepo) { $githubRepo } else { "" })
      tag = $resolvedTag
      version = [string]$package["version"]
      name = [string]$package["name"]
      packageId = [string]$package["id"]
      backend = $Backend
      channel = $channel
    })
  } else {
    $null
  }
  $feedUrl = if ($backendUpdates.Contains("feedUrl") -and -not [string]::IsNullOrWhiteSpace([string]$backendUpdates["feedUrl"])) {
    [string]$backendUpdates["feedUrl"]
  } elseif ($updates.Contains("feedUrl") -and -not [string]::IsNullOrWhiteSpace([string]$updates["feedUrl"])) {
    [string]$updates["feedUrl"]
  } else {
    $null
  }

  return [pscustomobject]@{
    Enabled = [bool]($updates.Contains("enabled") -and $updates["enabled"])
    Provider = $provider
    Channel = $channel
    FeedUrl = $feedUrl
    MinimumCheckIntervalHours = $(if ($updates.Contains("minimumCheckIntervalHours")) { [int]$updates["minimumCheckIntervalHours"] } else { 24 })
    StartupDelaySeconds = $(if ($updates.Contains("startupDelaySeconds")) { [int]$updates["startupDelaySeconds"] } else { 15 })
    Backend = $Backend
    Platform = Get-GpUpdatePlatform -Backend $Backend
    RuntimeConfigRelativePath = Get-GpUpdateRuntimeConfigRelativePath -MetadataRootRelative ([string]$payload["metadataRoot"])
    GitHub = [pscustomobject]@{
      Owner = $githubOwner
      Repo = $githubRepo
      TagPattern = $tagPattern
      Tag = $resolvedTag
      ReleaseNotesUrlPattern = $releaseNotesUrlPattern
      ReleaseNotesUrl = $releaseNotesUrl
    }
    BackendSettings = [hashtable](Copy-GpValue -Value $backendUpdates)
  }
}

function Get-GpGitHubReleaseAssetUrl {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$UpdateSettings,
    [Parameter(Mandatory = $true)]
    [string]$AssetName
  )

  if ([string]::IsNullOrWhiteSpace([string]$UpdateSettings.GitHub.Owner) -or
      [string]::IsNullOrWhiteSpace([string]$UpdateSettings.GitHub.Repo) -or
      [string]::IsNullOrWhiteSpace([string]$UpdateSettings.GitHub.Tag)) {
    return $null
  }

  return ("https://github.com/{0}/{1}/releases/download/{2}/{3}" -f
    [string]$UpdateSettings.GitHub.Owner,
    [string]$UpdateSettings.GitHub.Repo,
    [System.Uri]::EscapeDataString([string]$UpdateSettings.GitHub.Tag),
    [System.Uri]::EscapeDataString($AssetName))
}

function Write-GpUpdateRuntimeConfig {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [string]$Backend,
    [Parameter(Mandatory = $true)]
    [string]$MetadataRoot
  )

  $settings = Get-GpUpdateSettings -Context $Context -Backend $Backend
  if (-not $settings.Enabled) {
    return $null
  }

  $package = $Context.Manifest["package"]
  $configRoot = Ensure-GpDirectory -Path (Join-Path $MetadataRoot "updates")
  $configPath = Join-Path $configRoot "gnustep-packager-update.json"
  $document = [ordered]@{
    formatVersion = 1
    package = [ordered]@{
      id = [string]$package["id"]
      name = [string]$package["name"]
      displayName = Get-GpPackageDisplayName -Manifest $Context.Manifest
      version = [string]$package["version"]
      manufacturer = [string]$package["manufacturer"]
      backend = $Backend
      platform = $settings.Platform
    }
    updates = [ordered]@{
      enabled = [bool]$settings.Enabled
      provider = $settings.Provider
      channel = $settings.Channel
      feedUrl = $settings.FeedUrl
      minimumCheckIntervalHours = [int]$settings.MinimumCheckIntervalHours
      startupDelaySeconds = [int]$settings.StartupDelaySeconds
      releaseNotesUrl = $settings.GitHub.ReleaseNotesUrl
      github = [ordered]@{
        owner = $settings.GitHub.Owner
        repo = $settings.GitHub.Repo
        tag = $settings.GitHub.Tag
      }
    }
  }

  $document | ConvertTo-Json -Depth 20 | Set-Content -Path $configPath -Encoding utf8
  return $configPath
}

function New-GpUpdateFeedDocument {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [string]$Backend,
    [Parameter(Mandatory = $true)]
    [object[]]$Assets
  )

  $settings = Get-GpUpdateSettings -Context $Context -Backend $Backend
  if (-not $settings.Enabled) {
    return $null
  }

  $package = $Context.Manifest["package"]
  return [ordered]@{
    formatVersion = 1
    provider = $settings.Provider
    generatedAt = (Get-Date).ToString("o")
    channel = $settings.Channel
    feedUrl = $settings.FeedUrl
    package = [ordered]@{
      id = [string]$package["id"]
      name = [string]$package["name"]
      displayName = Get-GpPackageDisplayName -Manifest $Context.Manifest
      version = [string]$package["version"]
      manufacturer = [string]$package["manufacturer"]
    }
    source = [ordered]@{
      github = [ordered]@{
        owner = $settings.GitHub.Owner
        repo = $settings.GitHub.Repo
      }
    }
    releases = @(
      [ordered]@{
        version = [string]$package["version"]
        tag = $settings.GitHub.Tag
        releaseNotesUrl = $settings.GitHub.ReleaseNotesUrl
        assets = @($Assets)
      }
    )
  }
}

function Write-GpUpdateFeedDocument {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [string]$Backend,
    [Parameter(Mandatory = $true)]
    [string]$ArtifactPath,
    [Parameter(Mandatory = $true)]
    [object[]]$Assets
  )

  $document = New-GpUpdateFeedDocument -Context $Context -Backend $Backend -Assets $Assets
  if ($null -eq $document) {
    return $null
  }

  $feedPath = Get-GpUpdateFeedSidecarPath -ArtifactPath $ArtifactPath
  $document | ConvertTo-Json -Depth 20 | Set-Content -Path $feedPath -Encoding utf8
  return $feedPath
}

function Escape-GpPwshLiteral {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value
  )

  return ($Value -replace "'", "''")
}

function Escape-GpBashLiteral {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value
  )

  $replacement = "'`"`'`"`'"
  return ($Value -replace "'", $replacement)
}

function Resolve-GpDefaultPosixShellProgram {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("bash", "sh")]
    [string]$Name
  )

  if ($IsWindows) {
    return $Name
  }

  foreach ($candidate in @("/usr/bin/$Name", "/bin/$Name")) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      return $candidate
    }
  }

  return $Name
}

function Move-GpPathEntryToEnd {
  param(
    [Parameter(Mandatory = $true)]
    [string]$PathValue,
    [Parameter(Mandatory = $true)]
    [string]$Entry
  )

  $separator = [System.IO.Path]::PathSeparator
  $normalizedEntry = $Entry.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  $kept = [System.Collections.Generic.List[string]]::new()
  $found = $false

  foreach ($item in ($PathValue -split [regex]::Escape([string]$separator))) {
    if ([string]::IsNullOrWhiteSpace($item)) {
      continue
    }

    $normalizedItem = $item.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    if ($normalizedItem -eq $normalizedEntry) {
      $found = $true
      continue
    }

    $kept.Add($item) | Out-Null
  }

  if ($found) {
    $kept.Add($Entry) | Out-Null
  }

  return [string]::Join([string]$separator, $kept)
}

function Get-GpShellCommandPath {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Invocation
  )

  if (($Invocation.ShellKind -notin @("bash", "sh")) -or [string]::IsNullOrWhiteSpace($env:GP_GNUSTEP_CLI_ROOT)) {
    return $env:PATH
  }

  $pathValue = $env:PATH
  foreach ($toolPath in @(
    (Join-Path $env:GP_GNUSTEP_CLI_ROOT "bin"),
    (Join-Path $env:GP_GNUSTEP_CLI_ROOT "Tools"),
    (Join-Path $env:GP_GNUSTEP_CLI_ROOT "System/Tools")
  )) {
    $pathValue = Move-GpPathEntryToEnd -PathValue $pathValue -Entry $toolPath
  }

  return $pathValue
}

function Get-GpShellInvocation {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$ShellConfig,
    [Parameter(Mandatory = $true)]
    [string]$Command
  )

  $bootstrapCommands = @()
  if ($ShellConfig.Contains("bootstrapCommands")) {
    $bootstrapCommands = @($ShellConfig["bootstrapCommands"])
  }

  $environment = @{}
  if ($ShellConfig.Contains("environment") -and ($ShellConfig["environment"] -is [System.Collections.IDictionary])) {
    $environment = $ShellConfig["environment"]
  }

  $kind = [string]$ShellConfig["kind"]

  switch ($kind) {
    "pwsh" {
      $parts = @()
      foreach ($key in $environment.Keys) {
        $parts += "`$env:$key = '$(Escape-GpPwshLiteral -Value ([string]$environment[$key]))'"
      }
      foreach ($bootstrap in $bootstrapCommands) {
        if (-not [string]::IsNullOrWhiteSpace($bootstrap)) {
          $parts += $bootstrap
        }
      }
      $parts += $Command
      $program = if ($ShellConfig.Contains("program")) {
        [string]$ShellConfig["program"]
      } elseif (($env:OS -eq "Windows_NT") -and -not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        "powershell"
      } else {
        "pwsh"
      }
      return [pscustomobject]@{
        FilePath     = $program
        ArgumentList = @("-NoProfile", "-Command", ($parts -join "; "))
        ShellKind    = $kind
      }
    }

    "powershell" {
      $parts = @()
      foreach ($key in $environment.Keys) {
        $parts += "`$env:$key = '$(Escape-GpPwshLiteral -Value ([string]$environment[$key]))'"
      }
      foreach ($bootstrap in $bootstrapCommands) {
        if (-not [string]::IsNullOrWhiteSpace($bootstrap)) {
          $parts += $bootstrap
        }
      }
      $parts += $Command
      return [pscustomobject]@{
        FilePath     = $(if ($ShellConfig.Contains("program")) { [string]$ShellConfig["program"] } else { "powershell" })
        ArgumentList = @("-NoProfile", "-Command", ($parts -join "; "))
        ShellKind    = $kind
      }
    }

    "bash" {
      $parts = @()
      foreach ($key in $environment.Keys) {
        $parts += "export $key='$(Escape-GpBashLiteral -Value ([string]$environment[$key]))'"
      }
      foreach ($bootstrap in $bootstrapCommands) {
        if (-not [string]::IsNullOrWhiteSpace($bootstrap)) {
          $parts += $bootstrap
        }
      }
      $parts += $Command
      return [pscustomobject]@{
        FilePath     = $(if ($ShellConfig.Contains("program")) { [string]$ShellConfig["program"] } else { Resolve-GpDefaultPosixShellProgram -Name "bash" })
        ArgumentList = @("-lc", ($parts -join "; "))
        ShellKind    = $kind
      }
    }

    "sh" {
      $parts = @()
      foreach ($key in $environment.Keys) {
        $parts += "export $key='$(Escape-GpBashLiteral -Value ([string]$environment[$key]))'"
      }
      foreach ($bootstrap in $bootstrapCommands) {
        if (-not [string]::IsNullOrWhiteSpace($bootstrap)) {
          $parts += $bootstrap
        }
      }
      $parts += $Command
      return [pscustomobject]@{
        FilePath     = $(if ($ShellConfig.Contains("program")) { [string]$ShellConfig["program"] } else { Resolve-GpDefaultPosixShellProgram -Name "sh" })
        ArgumentList = @("-lc", ($parts -join "; "))
        ShellKind    = $kind
      }
    }

    "msys2-bash" {
      $msysRoot = if ($ShellConfig.Contains("msysRoot")) { [string]$ShellConfig["msysRoot"] } else { "C:\msys64" }
      $envExe = Join-Path $msysRoot "usr\bin\env.exe"
      $parts = @()
      foreach ($key in $environment.Keys) {
        $parts += "export $key='$(Escape-GpBashLiteral -Value ([string]$environment[$key]))'"
      }
      foreach ($bootstrap in $bootstrapCommands) {
        if (-not [string]::IsNullOrWhiteSpace($bootstrap)) {
          $parts += $bootstrap
        }
      }
      $parts += $Command
      return [pscustomobject]@{
        FilePath     = $envExe
        ArgumentList = @("MSYSTEM=CLANG64", "CHERE_INVOKING=1", "/usr/bin/bash", "-lc", ($parts -join "; "))
        ShellKind    = $kind
      }
    }
  }

  throw "Unsupported shell kind: $kind"
}

function Invoke-GpCapturedProcess {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [string[]]$ArgumentList = @(),
    [string]$WorkingDirectory
  )

  $tempRoot = [System.IO.Path]::GetTempPath()
  $streamId = [guid]::NewGuid().ToString("N")
  $stdoutPath = Join-Path $tempRoot ("gp-process-{0}.stdout.tmp" -f $streamId)
  $stderrPath = Join-Path $tempRoot ("gp-process-{0}.stderr.tmp" -f $streamId)

  try {
    $parameters = @{
      FilePath = $FilePath
      ArgumentList = @($ArgumentList)
      Wait = $true
      PassThru = $true
      RedirectStandardOutput = $stdoutPath
      RedirectStandardError = $stderrPath
    }
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
      $parameters["WorkingDirectory"] = $WorkingDirectory
    }

    $process = Start-Process @parameters
    $stdout = if (Test-Path $stdoutPath) { Get-Content -Raw -Path $stdoutPath } else { "" }
    $stderr = if (Test-Path $stderrPath) { Get-Content -Raw -Path $stderrPath } else { "" }

    return [pscustomobject]@{
      ExitCode = [int]$process.ExitCode
      StdOut = [string]$stdout
      StdErr = [string]$stderr
    }
  } finally {
    foreach ($path in @($stdoutPath, $stderrPath)) {
      if (Test-Path $path) {
        Remove-Item -Force $path
      }
    }
  }
}

function Get-GpMsys2PacmanPath {
  $candidates = [System.Collections.Generic.List[string]]::new()
  if (-not [string]::IsNullOrWhiteSpace($env:MSYS2_LOCATION)) {
    $candidates.Add((Join-Path $env:MSYS2_LOCATION "usr\\bin\\pacman.exe")) | Out-Null
  }
  $candidates.Add("C:\\msys64\\usr\\bin\\pacman.exe") | Out-Null

  foreach ($candidate in @($candidates)) {
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
      return $candidate
    }
  }

  $command = Get-Command pacman.exe -ErrorAction SilentlyContinue
  if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source)) {
    return [string]$command.Source
  }

  return $null
}

function Get-GpMissingMsys2Packages {
  param(
    [string[]]$Packages = @()
  )

  $pacmanPath = Get-GpMsys2PacmanPath
  if ([string]::IsNullOrWhiteSpace($pacmanPath)) {
    throw "MSYS2 pacman.exe was not found. Set MSYS2_LOCATION or install the documented MSYS2 CLANG64 baseline."
  }

  $missing = [System.Collections.Generic.List[string]]::new()
  foreach ($packageName in @($Packages)) {
    $result = Invoke-GpCapturedProcess -FilePath $pacmanPath -ArgumentList @("-Q", "--", $packageName)
    if ($result.ExitCode -ne 0) {
      $missing.Add($packageName) | Out-Null
    }
  }

  return [string[]]@($missing.ToArray())
}

function Install-GpMsys2Packages {
  param(
    [string[]]$Packages = @()
  )

  $pacmanPath = Get-GpMsys2PacmanPath
  if ([string]::IsNullOrWhiteSpace($pacmanPath)) {
    throw "MSYS2 pacman.exe was not found. Set MSYS2_LOCATION or install the documented MSYS2 CLANG64 baseline."
  }

  $result = Invoke-GpCapturedProcess -FilePath $pacmanPath -ArgumentList @("-S", "--needed", "--noconfirm", "--") + @($Packages)
  if ($result.ExitCode -ne 0) {
    $detail = @($result.StdOut, $result.StdErr) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    throw ("MSYS2 package installation failed for: {0}. {1}" -f ([string]::Join(", ", @($Packages))), ([string]::Join(" ", $detail)).Trim())
  }
}

function Get-GpAptProgram {
  $command = Get-Command apt-get -ErrorAction SilentlyContinue
  if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source)) {
    return [string]$command.Source
  }
  return $null
}

function Get-GpMissingAptPackages {
  param(
    [string[]]$Packages = @()
  )

  $dpkgQuery = Get-Command dpkg-query -ErrorAction SilentlyContinue
  if ($null -eq $dpkgQuery -or [string]::IsNullOrWhiteSpace([string]$dpkgQuery.Source)) {
    throw "dpkg-query was not found. Linux apt host dependency verification requires a Debian/Ubuntu-style host with dpkg-query available."
  }

  $missing = [System.Collections.Generic.List[string]]::new()
  foreach ($packageName in @($Packages)) {
    $result = Invoke-GpCapturedProcess -FilePath ([string]$dpkgQuery.Source) -ArgumentList @("-W", '-f=${Status}', "--", $packageName)
    if (($result.ExitCode -ne 0) -or ($result.StdOut -notmatch "install ok installed")) {
      $missing.Add($packageName) | Out-Null
    }
  }

  return [string[]]@($missing.ToArray())
}

function Install-GpAptPackages {
  param(
    [string[]]$Packages = @()
  )

  $aptGet = Get-GpAptProgram
  if ([string]::IsNullOrWhiteSpace($aptGet)) {
    throw "apt-get was not found. Linux apt host dependency installation requires a Debian/Ubuntu-style host with apt-get available."
  }

  $sudo = Get-Command sudo -ErrorAction SilentlyContinue
  $prefix = @()
  if ((Get-Command id -ErrorAction SilentlyContinue) -and ((& id -u) -ne "0")) {
    if ($null -eq $sudo -or [string]::IsNullOrWhiteSpace([string]$sudo.Source)) {
      throw "Installing Linux host dependencies requires root or sudo access."
    }
    $prefix = @([string]$sudo.Source)
  }

  foreach ($command in @(
    @($aptGet, "update"),
    @($aptGet, "install", "-y", "--no-install-recommends") + @($Packages)
  )) {
    $filePath = if ($prefix.Count -gt 0) { $prefix[0] } else { $command[0] }
    $argumentList = if ($prefix.Count -gt 0) { @($command) } else { @($command | Select-Object -Skip 1) }
    if ($prefix.Count -eq 0) {
      $filePath = $command[0]
    }

    $result = Invoke-GpCapturedProcess -FilePath $filePath -ArgumentList $argumentList
    if ($result.ExitCode -ne 0) {
      $detail = @($result.StdOut, $result.StdErr) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
      throw ("apt dependency command failed: {0}. {1}" -f ([string]::Join(" ", @($command))), ([string]::Join(" ", $detail)).Trim())
    }
  }
}

function Get-GpMissingHostDependencyPackages {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Provider,
    [string[]]$Packages = @()
  )

  switch ($Provider.PackageManager) {
    "msys2" { return @(Get-GpMissingMsys2Packages -Packages @($Packages)) }
    "apt" { return @(Get-GpMissingAptPackages -Packages @($Packages)) }
    default { throw "Unsupported host package manager: $($Provider.PackageManager)" }
  }
}

function Install-GpHostDependencyPackages {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Provider,
    [string[]]$Packages = @()
  )

  switch ($Provider.PackageManager) {
    "msys2" { Install-GpMsys2Packages -Packages @($Packages); break }
    "apt" { Install-GpAptPackages -Packages @($Packages); break }
    default { throw "Unsupported host package manager: $($Provider.PackageManager)" }
  }
}

function Invoke-GpHostDependencyPreflight {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [string]$Backend,
    [string]$LogPath,
    [switch]$InstallMissing,
    [switch]$DryRun
  )

  if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $LogPath = New-GpCommandLogPath -Context $Context -CommandName "host-preflight"
  }

  Ensure-GpDirectory -Path (Split-Path -Parent $LogPath) | Out-Null
  $plan = Get-GpHostDependencyPlan -Context $Context -Backend $Backend
  $lines = [System.Collections.Generic.List[string]]::new()
  $lines.Add(("[{0}] host-platform={1}" -f (Get-Date).ToString("o"), $plan.HostPlatform)) | Out-Null

  if (@($plan.Groups).Count -eq 0) {
    $lines.Add("No manifest-declared host dependencies apply to this host.") | Out-Null
    Set-Content -Path $LogPath -Value $lines
    return [pscustomobject]@{
      HostPlatform = $plan.HostPlatform
      Groups = @()
      LogPath = $LogPath
      InstallMode = [bool]$InstallMissing
      DryRun = [bool]$DryRun
    }
  }

  foreach ($group in @($plan.Groups)) {
    $provider = Get-GpHostDependencyProvider -Id $group.ProviderId
    $lines.Add(("Checking {0} packages: {1}" -f $group.PackageManager, ([string]::Join(", ", @($group.Packages))))) | Out-Null
    if ($DryRun) {
      $lines.Add(("DRYRUN  would verify {0} packages" -f $group.PackageManager)) | Out-Null
      continue
    }

    $missing = @(Get-GpMissingHostDependencyPackages -Provider $provider -Packages @($group.Packages))

    if ($missing.Count -eq 0) {
      $lines.Add(("OK      all declared {0} packages are already present" -f $group.PackageManager)) | Out-Null
      continue
    }

    $lines.Add(("MISSING {0}" -f ([string]::Join(", ", $missing)))) | Out-Null
    if (-not $InstallMissing) {
      Set-Content -Path $LogPath -Value $lines
      throw ("Missing declared {0} host dependencies: {1}. Re-run with -InstallHostDependencies or set GP_INSTALL_HOST_DEPENDENCIES=1. See log: {2}" -f $group.PackageManager, ([string]::Join(", ", $missing)), $LogPath)
    }

    $lines.Add(("INSTALL {0}" -f ([string]::Join(", ", $missing)))) | Out-Null
    Install-GpHostDependencyPackages -Provider $provider -Packages $missing
    $lines.Add(("OK      installed missing {0} packages" -f $group.PackageManager)) | Out-Null
  }

  Set-Content -Path $LogPath -Value $lines
  return [pscustomobject]@{
    HostPlatform = $plan.HostPlatform
    Groups = @($plan.Groups)
    LogPath = $LogPath
    InstallMode = [bool]$InstallMissing
    DryRun = [bool]$DryRun
  }
}

function New-GpTimestamp {
  return (Get-Date -Format "yyyyMMdd-HHmmss-fff")
}

function Ensure-GpDirectory {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  New-Item -ItemType Directory -Force -Path $Path | Out-Null
  return $Path
}

function Get-GpOutputPaths {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context
  )

  $outputs = $Context.Manifest["outputs"]
  return [pscustomobject]@{
    Root           = Resolve-GpManifestPath -Context $Context -RelativePath $outputs["root"]
    PackageRoot    = Resolve-GpManifestPath -Context $Context -RelativePath $outputs["packageRoot"]
    LogRoot        = Resolve-GpManifestPath -Context $Context -RelativePath $outputs["logRoot"]
    TempRoot       = Resolve-GpManifestPath -Context $Context -RelativePath $outputs["tempRoot"]
    ValidationRoot = Resolve-GpManifestPath -Context $Context -RelativePath $outputs["validationRoot"]
  }
}

function New-GpCommandLogPath {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [string]$CommandName
  )

  $outputPaths = Get-GpOutputPaths -Context $Context
  $commandLogRoot = Ensure-GpDirectory -Path (Join-Path $outputPaths.LogRoot $CommandName)
  return (Join-Path $commandLogRoot ("{0}.log" -f (New-GpTimestamp)))
}

function Get-GpLaunchContract {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context
  )

  $manifest = $Context.Manifest
  $payload = $manifest["payload"]
  $launch = $manifest["launch"]
  $stageRoot = Resolve-GpManifestPath -Context $Context -RelativePath $payload["stageRoot"]
  $combinedResourceRoots = @()

  foreach ($item in @($payload["resourceRoots"])) {
    $combinedResourceRoots += @($item)
  }
  foreach ($item in @($launch["resourceRoots"])) {
    $combinedResourceRoots += @($item)
  }
  $combinedResourceRoots = @($combinedResourceRoots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

  $nativePathPrepend = @()
  foreach ($item in @($launch["pathPrepend"])) {
    if (-not [string]::IsNullOrWhiteSpace($item)) {
      $nativePathPrepend += @(Resolve-GpPathRelativeToBase -BasePath $stageRoot -Path $item)
    }
  }

  $nativeResourceRoots = @()
  foreach ($item in $combinedResourceRoots) {
    $nativeResourceRoots += @(Resolve-GpPathRelativeToBase -BasePath $stageRoot -Path $item)
  }

  $entryPath = Resolve-GpPathRelativeToBase -BasePath $stageRoot -Path $launch["entryRelativePath"]
  $workingDirectoryPath = Resolve-GpPathRelativeToBase -BasePath $stageRoot -Path $launch["workingDirectory"]

  return [pscustomobject]@{
    StageRoot             = $stageRoot
    EntryRelativePath     = [string]$launch["entryRelativePath"]
    EntryPath             = $entryPath
    WorkingDirectory      = [string]$launch["workingDirectory"]
    WorkingDirectoryPath  = $workingDirectoryPath
    Arguments             = [string[]]@($launch["arguments"])
    PathPrepend           = [string[]]@($launch["pathPrepend"])
    PathPrependPaths      = [string[]]$nativePathPrepend
    ResourceRoots         = [string[]]$combinedResourceRoots
    ResourceRootPaths     = [string[]]$nativeResourceRoots
    Environment           = [hashtable](Get-GpNormalizedLaunchEnvironment -Environment $launch["env"])
    WindowsEntryPath      = Convert-GpNativePathToWindows -Path $entryPath
    PosixEntryPath        = Convert-GpNativePathToPosix -Path $entryPath
  }
}

function Get-GpValidationSection {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Manifest,
    [Parameter(Mandatory = $true)]
    [string]$SectionName
  )

  if ($Manifest.Contains("validation") -and
      ($Manifest["validation"] -is [System.Collections.IDictionary]) -and
      $Manifest["validation"].Contains($SectionName) -and
      ($Manifest["validation"][$SectionName] -is [System.Collections.IDictionary])) {
    return $Manifest["validation"][$SectionName]
  }

  return @{}
}

function Get-GpPackageContractDeclarations {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [ValidateSet("packageContract", "installedResult")]
    [string]$SectionName = "packageContract",
    [string]$Backend
  )

  $manifest = $Context.Manifest
  $section = Get-GpValidationSection -Manifest $manifest -SectionName $SectionName
  $declarations = [System.Collections.Generic.List[psobject]]::new()
  $autoKinds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  $declaredThemeNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

  $index = 0
  foreach ($item in @($section["requiredContent"])) {
    if (-not ($item -is [System.Collections.IDictionary])) {
      $index += 1
      continue
    }

    $kind = if ($item.Contains("kind")) { [string]$item["kind"] } else { $null }
    if ([string]::IsNullOrWhiteSpace($kind)) {
      $index += 1
      continue
    }

    $null = $autoKinds.Add($kind)
    if ($kind -eq "bundled-theme" -and $item.Contains("name") -and -not [string]::IsNullOrWhiteSpace([string]$item["name"])) {
      $null = $declaredThemeNames.Add([string]$item["name"])
    }
    $declarations.Add([pscustomobject]@{
      Kind = $kind
      Path = $(if ($item.Contains("path")) { [string]$item["path"] } else { $null })
      Value = $(if ($item.Contains("value")) { [string]$item["value"] } else { $null })
      Name = $(if ($item.Contains("name")) { [string]$item["name"] } else { $null })
      Theme = $(if ($item.Contains("theme")) { [string]$item["theme"] } else { $null })
      Source = ("validation.{0}.requiredContent[{1}]" -f $SectionName, $index)
    }) | Out-Null
    $index += 1
  }

  $packagedDefaults = Get-GpPackagedDefaults -Manifest $manifest
  if (-not [string]::IsNullOrWhiteSpace([string]$packagedDefaults.DefaultTheme) -and -not $autoKinds.Contains("default-theme")) {
    $declarations.Add([pscustomobject]@{
      Kind = "default-theme"
      Path = $null
      Value = [string]$packagedDefaults.DefaultTheme
      Name = "defaultTheme"
      Source = "packagedDefaults.defaultTheme"
    }) | Out-Null
  }

  $contextBackend = if (-not [string]::IsNullOrWhiteSpace($Backend)) {
    $Backend
  } elseif ($Context.PSObject.Properties["Backend"]) {
    [string]$Context.Backend
  } else {
    $null
  }
  foreach ($theme in @(Get-GpThemeInputs -Manifest $manifest -Backend $contextBackend -ActiveOnly)) {
    if (($theme.Required -or $theme.Default) -and -not [string]::IsNullOrWhiteSpace([string]$theme.Name) -and -not $declaredThemeNames.Contains([string]$theme.Name)) {
      $declarations.Add([pscustomobject]@{
        Kind = "bundled-theme"
        Path = $null
        Value = $null
        Name = [string]$theme.Name
        Theme = $null
        Source = $theme.Source
      }) | Out-Null
      $null = $declaredThemeNames.Add([string]$theme.Name)
    }
  }

  return @($declarations.ToArray())
}

function Get-GpValidationRelativePaths {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [ValidateSet("packageContract", "installedResult")]
    [string]$SectionName
  )

  $section = Get-GpValidationSection -Manifest $Context.Manifest -SectionName $SectionName
  return [string[]]@($section["requiredPaths"] | Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace([string]$_) })
}

function Get-GpAppPayloadRoot {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RootPath,
    [Parameter(Mandatory = $true)]
    [string]$Backend
  )

  if ($Backend -eq "appimage") {
    return (Join-Path $RootPath "usr")
  }

  return $RootPath
}

function Get-GpUpdaterHelperCandidates {
  param(
    [Parameter(Mandatory = $true)]
    [string]$EntryRelativePath
  )

  $entryDirectory = Split-Path -Parent $EntryRelativePath
  if ([string]::IsNullOrWhiteSpace($entryDirectory)) {
    $entryDirectory = "."
  }

  return [string[]]@(
    (Join-Path $entryDirectory "gp-update-helper"),
    (Join-Path $entryDirectory "gp-update-helper.exe"),
    (Join-Path (Join-Path $entryDirectory "Helpers") "gp-update-helper"),
    (Join-Path (Join-Path $entryDirectory "Helpers") "gp-update-helper.exe")
  )
}

function Get-GpBundledThemeCandidatePaths {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ThemeName
  )

  return [string[]]@(
    (Join-Path "runtime/System/Library/Themes" ("{0}.theme" -f $ThemeName)),
    (Join-Path "runtime/lib/GNUstep/Themes" ("{0}.theme" -f $ThemeName)),
    (Join-Path "runtime/share/GNUstep/Themes" ("{0}.theme" -f $ThemeName))
  )
}

function Get-GpThemeExecutableCandidates {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ThemePath,
    [Parameter(Mandatory = $true)]
    [string]$ThemeName,
    [string]$Backend
  )

  if ($Backend -eq "msi") {
    return [string[]]@((Join-Path $ThemePath ("{0}.dll" -f $ThemeName)))
  }

  if ($Backend -eq "appimage") {
    return [string[]]@(
      (Join-Path $ThemePath $ThemeName),
      (Join-Path $ThemePath ("lib{0}.so" -f $ThemeName)),
      (Join-Path $ThemePath ("{0}.so" -f $ThemeName))
    )
  }

  return [string[]]@()
}

function Get-GpThemeBundleResourceInventory {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ThemePath
  )

  if (-not (Test-Path $ThemePath)) {
    return @()
  }

  $rootLength = $ThemePath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar).Length
  $items = [System.Collections.Generic.List[string]]::new()
  foreach ($file in @(Get-ChildItem -Path $ThemePath -File -Recurse -ErrorAction SilentlyContinue)) {
    $relative = $file.FullName.Substring($rootLength).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $items.Add(($relative -replace "\\", "/")) | Out-Null
  }

  return [string[]]@($items.ToArray() | Sort-Object)
}

function Get-GpThemeImageReferences {
  param(
    [Parameter(Mandatory = $true)]
    [string]$InfoPath
  )

  if (-not (Test-Path $InfoPath)) {
    return @()
  }

  $text = Get-Content -Raw -Path $InfoPath
  if ($text -notmatch "GSThemeImages") {
    return @()
  }

  $references = [System.Collections.Generic.List[string]]::new()
  foreach ($match in [regex]::Matches($text, "[A-Za-z0-9_.\-/]+\.png|[A-Za-z0-9_.\-/]+\.tiff|[A-Za-z0-9_.\-/]+\.jpg|[A-Za-z0-9_.\-/]+\.jpeg|[A-Za-z0-9_.\-/]+\.gif")) {
    $value = [string]$match.Value
    if (-not $references.Contains($value)) {
      $references.Add($value) | Out-Null
    }
  }

  return [string[]]@($references.ToArray())
}

function Test-GpThemeBundleStructure {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ThemePath,
    [Parameter(Mandatory = $true)]
    [string]$ThemeName,
    [string]$Backend
  )

  $lines = [System.Collections.Generic.List[string]]::new()
  $issues = [System.Collections.Generic.List[string]]::new()

  if (-not (Test-Path $ThemePath -PathType Container)) {
    $issues.Add("theme directory is missing") | Out-Null
    return [pscustomobject]@{
      Lines = @("MISSING theme directory: $ThemePath")
      Issues = @($issues.ToArray())
      Executable = $null
      InfoPath = $null
      Resources = @()
    }
  }

  $lines.Add(("OK      theme directory: {0}" -f $ThemePath)) | Out-Null
  $executable = $null
  $executableCandidates = @(Get-GpThemeExecutableCandidates -ThemePath $ThemePath -ThemeName $ThemeName -Backend $Backend)
  if ($executableCandidates.Count -gt 0) {
    foreach ($candidate in $executableCandidates) {
      if (Test-Path $candidate -PathType Leaf) {
        $executable = $candidate
        break
      }
    }

    if ([string]::IsNullOrWhiteSpace($executable)) {
      $issues.Add(("theme executable is missing; checked {0}" -f ([string]::Join(", ", $executableCandidates)))) | Out-Null
    } else {
      $lines.Add(("OK      theme executable: {0}" -f $executable)) | Out-Null
    }
  }

  $resourcesRoot = Join-Path $ThemePath "Resources"
  $infoPath = Join-Path $resourcesRoot "Info-gnustep.plist"
  if (Test-Path $resourcesRoot -PathType Container) {
    if (Test-Path $infoPath -PathType Leaf) {
      $lines.Add(("OK      theme info: {0}" -f $infoPath)) | Out-Null
      $infoText = Get-Content -Raw -Path $infoPath
      if ($infoText -match "NSExecutable" -and $infoText -notmatch [regex]::Escape($ThemeName)) {
        $issues.Add("Resources/Info-gnustep.plist declares NSExecutable metadata that does not mention the theme name") | Out-Null
      }
      if ($infoText -match "NSPrincipalClass" -and [string]::IsNullOrWhiteSpace(($infoText -replace "(?s).*NSPrincipalClass.*", "$&"))) {
        $issues.Add("Resources/Info-gnustep.plist contains empty NSPrincipalClass metadata") | Out-Null
      }
      foreach ($reference in @(Get-GpThemeImageReferences -InfoPath $infoPath)) {
        $candidate = Join-Path $resourcesRoot $reference
        if (-not (Test-Path $candidate -PathType Leaf)) {
          $issues.Add(("GSThemeImages resource is missing: {0}" -f $reference)) | Out-Null
        } else {
          $lines.Add(("OK      theme image: {0}" -f $reference)) | Out-Null
        }
      }
    } else {
      $issues.Add("Resources/Info-gnustep.plist is missing") | Out-Null
    }
  }

  $resources = @(Get-GpThemeBundleResourceInventory -ThemePath $ThemePath)
  return [pscustomobject]@{
    Lines = @($lines.ToArray())
    Issues = @($issues.ToArray())
    Executable = $executable
    InfoPath = $(if (Test-Path $infoPath -PathType Leaf) { $infoPath } else { $null })
    Resources = [string[]]@($resources)
  }
}

function Find-GpBundledThemePath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$PayloadRoot,
    [Parameter(Mandatory = $true)]
    [string]$ThemeName
  )

  foreach ($candidate in @(Get-GpBundledThemeCandidatePaths -ThemeName $ThemeName)) {
    $candidatePath = Resolve-GpPathRelativeToBase -BasePath $PayloadRoot -Path $candidate
    if (Test-Path $candidatePath -PathType Container) {
      return $candidatePath
    }
  }

  return $null
}

function Get-GpDefaultThemeContractValue {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [AllowNull()]
    [string]$DeclaredValue
  )

  if (-not [string]::IsNullOrWhiteSpace($DeclaredValue)) {
    return $DeclaredValue
  }

  $launch = Get-GpLaunchContract -Context $Context
  if ($launch.Environment.ContainsKey("GSTheme") -and -not [string]::IsNullOrWhiteSpace([string]$launch.Environment["GSTheme"]["value"])) {
    return [string]$launch.Environment["GSTheme"]["value"]
  }

  return $null
}

function Invoke-GpPackageContractAssertions {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [ValidateSet("stage", "package", "installed")]
    [string]$Scope,
    [string]$Backend,
    [string]$RootPath,
    [string]$LogPath,
    [switch]$Append
  )

  $manifest = $Context.Manifest
  $payload = $manifest["payload"]
  $launch = Get-GpLaunchContract -Context $Context
  $sectionName = if ($Scope -eq "installed") { "installedResult" } else { "packageContract" }
  $lines = [System.Collections.Generic.List[string]]::new()
  $issues = [System.Collections.Generic.List[string]]::new()
  $declarations = @(Get-GpPackageContractDeclarations -Context $Context -SectionName $sectionName -Backend $Backend)
  $payloadRoot = if ($Scope -eq "stage") { $launch.StageRoot } elseif (-not [string]::IsNullOrWhiteSpace($Backend)) { Get-GpAppPayloadRoot -RootPath $RootPath -Backend $Backend } else { $RootPath }
  $phaseLabel = if ($Scope -eq "stage") { "stage contract" } elseif ($Scope -eq "package") { "$Backend package contract" } else { "$Backend installed-result contract" }

  foreach ($entry in @($declarations)) {
    $label = if (-not [string]::IsNullOrWhiteSpace([string]$entry.Name)) { $entry.Name } else { $entry.Kind }
    switch ($entry.Kind) {
      "bundled-theme" {
        $bundledThemeLabel = ("bundled-theme:{0}" -f $entry.Name)
        $candidatePaths = [System.Collections.Generic.List[string]]::new()
        $matchedPaths = [System.Collections.Generic.List[string]]::new()
        foreach ($candidate in @(Get-GpBundledThemeCandidatePaths -ThemeName $entry.Name)) {
          $candidatePath = Resolve-GpPathRelativeToBase -BasePath $payloadRoot -Path $candidate
          $candidatePaths.Add($candidatePath) | Out-Null
          if (Test-Path $candidatePath) {
            $matchedPaths.Add($candidatePath) | Out-Null
          }
        }

        if ($matchedPaths.Count -gt 0) {
          $lines.Add(("OK      {0} [{1}] -> matched {2}" -f $bundledThemeLabel, $entry.Source, ([string]::Join(", ", @($matchedPaths.ToArray()))))) | Out-Null
          $structure = Test-GpThemeBundleStructure -ThemePath $matchedPaths[0] -ThemeName $entry.Name -Backend $Backend
          foreach ($structureLine in @($structure.Lines)) {
            $lines.Add($structureLine) | Out-Null
          }
          foreach ($structureIssue in @($structure.Issues)) {
            $message = ("INVALID {0} [{1}] -> {2}" -f $bundledThemeLabel, $entry.Source, $structureIssue)
            $lines.Add($message) | Out-Null
            $issues.Add($message) | Out-Null
          }
        } else {
          $message = ("MISSING {0} [{1}] -> checked {2}" -f $bundledThemeLabel, $entry.Source, ([string]::Join(", ", @($candidatePaths.ToArray()))))
          $lines.Add($message) | Out-Null
          $issues.Add($message) | Out-Null
        }
      }

      "theme-resource" {
        $themeName = if (-not [string]::IsNullOrWhiteSpace([string]$entry.Theme)) { [string]$entry.Theme } else { [string]$entry.Name }
        $themePath = Find-GpBundledThemePath -PayloadRoot $payloadRoot -ThemeName $themeName
        if ([string]::IsNullOrWhiteSpace($themePath)) {
          $message = ("MISSING theme-resource:{0}:{1} [{2}] -> no bundled theme found" -f $themeName, $entry.Path, $entry.Source)
          $lines.Add($message) | Out-Null
          $issues.Add($message) | Out-Null
          continue
        }

        $resourcePath = Resolve-GpPathRelativeToBase -BasePath $themePath -Path $entry.Path
        if (Test-Path $resourcePath -PathType Leaf) {
          $lines.Add(("OK      theme-resource:{0}:{1} -> {2}" -f $themeName, $entry.Path, $resourcePath)) | Out-Null
        } else {
          $message = ("MISSING theme-resource:{0}:{1} [{2}] -> {3}" -f $themeName, $entry.Path, $entry.Source, $resourcePath)
          $lines.Add($message) | Out-Null
          $issues.Add($message) | Out-Null
        }
      }

      "metadata-file" {
        $path = Resolve-GpPathRelativeToBase -BasePath $payloadRoot -Path $entry.Path
        if (Test-Path $path) {
          $lines.Add(("OK      {0}: {1}" -f $label, $path)) | Out-Null
        } else {
          $message = ("MISSING {0}: {1}" -f $label, $path)
          $lines.Add($message) | Out-Null
          $issues.Add($message) | Out-Null
        }
      }

      "updater-helper" {
        $matches = [System.Collections.Generic.List[string]]::new()
        foreach ($candidate in @(Get-GpUpdaterHelperCandidates -EntryRelativePath $launch.EntryRelativePath)) {
          $candidatePath = Resolve-GpPathRelativeToBase -BasePath $payloadRoot -Path $candidate
          if (Test-Path $candidatePath) {
            $matches.Add($candidatePath) | Out-Null
          }
        }

        if ($matches.Count -gt 0) {
          $lines.Add(("OK      {0}: {1}" -f $label, ([string]::Join(", ", @($matches.ToArray()))))) | Out-Null
        } else {
          $message = ("MISSING {0}: no updater helper found near {1}" -f $label, $launch.EntryRelativePath)
          $lines.Add($message) | Out-Null
          $issues.Add($message) | Out-Null
        }
      }

      "notice-report" {
        if ($Scope -eq "stage") {
          $lines.Add(("SKIP    {0}: generated during packaging" -f $label)) | Out-Null
          continue
        }

        $reportPath = Resolve-GpPathRelativeToBase -BasePath $payloadRoot -Path (Join-Path ([string]$payload["metadataRoot"]) "THIRD-PARTY-NOTICES.txt")
        if (Test-Path $reportPath) {
          $lines.Add(("OK      {0}: {1}" -f $label, $reportPath)) | Out-Null
        } else {
          $message = ("MISSING {0}: {1}" -f $label, $reportPath)
          $lines.Add($message) | Out-Null
          $issues.Add($message) | Out-Null
        }
      }

      "update-runtime-config" {
        if ($Scope -eq "stage") {
          $lines.Add(("SKIP    {0}: generated during packaging" -f $label)) | Out-Null
          continue
        }

        $configPath = Resolve-GpPathRelativeToBase -BasePath $payloadRoot -Path (Get-GpUpdateRuntimeConfigRelativePath -MetadataRootRelative ([string]$payload["metadataRoot"]))
        if (Test-Path $configPath) {
          $lines.Add(("OK      {0}: {1}" -f $label, $configPath)) | Out-Null
        } else {
          $message = ("MISSING {0}: {1}" -f $label, $configPath)
          $lines.Add($message) | Out-Null
          $issues.Add($message) | Out-Null
        }
      }

      "default-theme" {
        $themeValue = Get-GpDefaultThemeContractValue -Context $Context -DeclaredValue $entry.Value
        if ([string]::IsNullOrWhiteSpace($themeValue)) {
          $message = ("MISSING {0}: no theme value is available from the manifest contract" -f $label)
          $lines.Add($message) | Out-Null
          $issues.Add($message) | Out-Null
          continue
        }

        if ($Scope -eq "stage") {
          $themeEntry = $launch.Environment["GSTheme"]
          $actualValue = if ($null -ne $themeEntry) { [string]$themeEntry["value"] } else { $null }
          $actualPolicy = if ($null -ne $themeEntry) { [string]$themeEntry["policy"] } else { $null }
          if (($actualValue -eq $themeValue) -and ($actualPolicy -eq "ifUnset")) {
            $lines.Add(("OK      {0}: launch.env.GSTheme={1} (ifUnset)" -f $label, $themeValue)) | Out-Null
          } else {
            $message = ("MISSING {0}: expected launch.env.GSTheme={1} with policy ifUnset" -f $label, $themeValue)
            $lines.Add($message) | Out-Null
            $issues.Add($message) | Out-Null
          }
          continue
        }

        if ($Backend -eq "msi") {
          $config = Get-GpMsiConfig -Context $Context
          $configPath = Join-Path $RootPath $config.LauncherConfigName
          $configText = if (Test-Path $configPath) { Get-Content -Raw -Path $configPath } else { "" }
          $envPattern = [regex]::Escape(("env=ifUnset|GSTheme={0}" -f $themeValue))
          $seedPattern = [regex]::Escape(("appDefault=GSTheme=""{0}""" -f $themeValue))
          if (($configText -match $envPattern) -and ($configText -match $seedPattern)) {
            $lines.Add(("OK      {0}: {1}" -f $label, $configPath)) | Out-Null
          } else {
            $message = ("MISSING {0}: launcher config does not preserve both GSTheme env fallback and seeded GSTheme default at {1}" -f $label, $configPath)
            $lines.Add($message) | Out-Null
            $issues.Add($message) | Out-Null
          }
        } elseif ($Backend -eq "appimage") {
          $appRunPath = Join-Path $RootPath "AppRun"
          $appRunText = if (Test-Path $appRunPath) { Get-Content -Raw -Path $appRunPath } else { "" }
          $policyPattern = 'if \[ -z "\$\{GSTheme\+x\}" \]; then'
          $valuePattern = [regex]::Escape(("export GSTheme=""{0}""" -f $themeValue))
          $seedPattern = ('write ".+" "GSTheme" "\\"' + [regex]::Escape($themeValue) + '\\""')
          $toolPattern = 'APP_DEFAULTS_TOOL='
          if (($appRunText -match $policyPattern) -and ($appRunText -match $valuePattern) -and ($appRunText -match $toolPattern) -and ($appRunText -match $seedPattern)) {
            $lines.Add(("OK      {0}: {1}" -f $label, $appRunPath)) | Out-Null
          } else {
            $message = ("MISSING {0}: AppRun does not preserve both GSTheme env fallback and seeded GSTheme default at {1}" -f $label, $appRunPath)
            $lines.Add($message) | Out-Null
            $issues.Add($message) | Out-Null
          }
        }
      }
    }
  }

  foreach ($relativePath in @(Get-GpValidationRelativePaths -Context $Context -SectionName $sectionName)) {
    if ($Scope -eq "stage") {
      continue
    }

    $path = Resolve-GpPathRelativeToBase -BasePath $RootPath -Path $relativePath
    if (Test-Path $path) {
      $lines.Add(("OK      path:{0} -> {1}" -f $relativePath, $path)) | Out-Null
    } else {
      $message = ("MISSING path:{0} -> {1}" -f $relativePath, $path)
      $lines.Add($message) | Out-Null
      $issues.Add($message) | Out-Null
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
    if ($Append -and (Test-Path $LogPath)) {
      Add-Content -Path $LogPath -Value ""
      Add-Content -Path $LogPath -Value ("[{0}]" -f $phaseLabel)
      Add-Content -Path $LogPath -Value @($lines.ToArray())
    } else {
      Set-Content -Path $LogPath -Value @($lines.ToArray())
    }
  }

  return [pscustomobject]@{
    Scope = $Scope
    Backend = $Backend
    Lines = [string[]]@($lines.ToArray())
    Issues = [string[]]@($issues.ToArray())
    HasIssues = [bool]($issues.Count -gt 0)
  }
}

function Get-GpValidationPlan {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context
  )

  $manifest = $Context.Manifest
  $payload = $manifest["payload"]
  $validation = $manifest["validation"]
  $launchContract = Get-GpLaunchContract -Context $Context
  $stageRoot = $launchContract.StageRoot

  $requiredPaths = [System.Collections.Generic.List[psobject]]::new()
  $requiredPaths.Add([pscustomobject]@{ Label = "stageRoot"; Path = $stageRoot }) | Out-Null
  $requiredPaths.Add([pscustomobject]@{ Label = "appRoot"; Path = Resolve-GpPathRelativeToBase -BasePath $stageRoot -Path $payload["appRoot"] }) | Out-Null
  $requiredPaths.Add([pscustomobject]@{ Label = "runtimeRoot"; Path = Resolve-GpPathRelativeToBase -BasePath $stageRoot -Path $payload["runtimeRoot"] }) | Out-Null
  $requiredPaths.Add([pscustomobject]@{ Label = "metadataRoot"; Path = Resolve-GpPathRelativeToBase -BasePath $stageRoot -Path $payload["metadataRoot"] }) | Out-Null
  $requiredPaths.Add([pscustomobject]@{ Label = "entry"; Path = $launchContract.EntryPath }) | Out-Null

  foreach ($path in $launchContract.PathPrepend) {
    $requiredPaths.Add([pscustomobject]@{
      Label = "pathPrepend:$path"
      Path  = Resolve-GpPathRelativeToBase -BasePath $stageRoot -Path $path
    }) | Out-Null
  }

  foreach ($path in $launchContract.ResourceRoots) {
    $requiredPaths.Add([pscustomobject]@{
      Label = "resourceRoot:$path"
      Path  = Resolve-GpPathRelativeToBase -BasePath $stageRoot -Path $path
    }) | Out-Null
  }

  foreach ($path in @($validation["smoke"]["requiredPaths"])) {
    if (-not [string]::IsNullOrWhiteSpace($path)) {
      $resolvedPath = Resolve-GpPathRelativeToBase -BasePath $stageRoot -Path $path
      $isPattern = Test-GpWildcardPathPattern -Path $path
      $requiredPaths.Add([pscustomobject]@{
        Label = "smoke:$path"
        Path  = $resolvedPath
        IsPattern = [bool]$isPattern
        Pattern = $(if ($isPattern) { $path } else { $null })
      }) | Out-Null
    }
  }

  return [pscustomobject]@{
    Kind           = [string]$validation["smoke"]["kind"]
    Enabled        = [bool]$validation["smoke"]["enabled"]
    TimeoutSeconds = [int]$validation["smoke"]["timeoutSeconds"]
    RetainLogs     = [bool]$validation["logs"]["retainOnSuccess"]
    RequiredPaths  = @($requiredPaths.ToArray())
  }
}

function Get-GpArtifactPlan {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [string]$Backend
  )

  $manifest = $Context.Manifest
  $package = $manifest["package"]
  $backendConfig = $manifest["backends"][$Backend]
  $outputPaths = Get-GpOutputPaths -Context $Context
  $artifactPattern = [string]$backendConfig["artifactNamePattern"]
  $artifactName = Resolve-GpPatternTokens -Pattern $artifactPattern -Tokens @{
    name = $package["name"]
    version = $package["version"]
    packageId = $package["id"]
    backend = $Backend
  }

  return [pscustomobject]@{
    Backend      = $Backend
    ArtifactName = $artifactName
    ArtifactPath = Join-Path $outputPaths.PackageRoot $artifactName
    OutputRoot   = $outputPaths.PackageRoot
  }
}

function Invoke-GpShellCommand {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Invocation,
    [Parameter(Mandatory = $true)]
    [string]$WorkingDirectory,
    [Parameter(Mandatory = $true)]
    [string]$LogPath,
    [switch]$DryRun
  )

  Ensure-GpDirectory -Path (Split-Path -Parent $LogPath) | Out-Null
  Set-Content -Path $LogPath -Value ("[{0}] shell={1}" -f (Get-Date).ToString("o"), $Invocation.ShellKind)

  if ($DryRun) {
    return [pscustomobject]@{
      FilePath = $Invocation.FilePath
      ArgumentList = [string[]]$Invocation.ArgumentList
      WorkingDirectory = $WorkingDirectory
      LogPath = $LogPath
      DryRun = $true
    }
  }

  Push-Location $WorkingDirectory
  $previousPath = $env:PATH
  try {
    $env:PATH = Get-GpShellCommandPath -Invocation $Invocation
    $argumentList = @($Invocation.ArgumentList)
    $streamRoot = Split-Path -Parent $LogPath
    $streamId = [guid]::NewGuid().ToString("N")
    $stdoutPath = Join-Path $streamRoot ("{0}.stdout.tmp" -f $streamId)
    $stderrPath = Join-Path $streamRoot ("{0}.stderr.tmp" -f $streamId)

    try {
      # Native Windows toolchains regularly emit warnings on stderr even when the
      # process succeeds. Capture both streams as plain text and use only the
      # native exit code as the success/failure signal. ProcessStartInfo keeps
      # the argument vector intact; Start-Process flattens complex shell command
      # arguments on some PowerShell hosts.
      $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
      $startInfo.FileName = $Invocation.FilePath
      $startInfo.WorkingDirectory = $WorkingDirectory
      $startInfo.UseShellExecute = $false
      $startInfo.RedirectStandardOutput = $true
      $startInfo.RedirectStandardError = $true
      foreach ($argument in $argumentList) {
        $startInfo.ArgumentList.Add([string]$argument) | Out-Null
      }

      $process = [System.Diagnostics.Process]::new()
      $process.StartInfo = $startInfo
      if (-not $process.Start()) {
        throw "Failed to start command: $($Invocation.FilePath)"
      }

      $stdoutTask = $process.StandardOutput.ReadToEndAsync()
      $stderrTask = $process.StandardError.ReadToEndAsync()
      $process.WaitForExit()
      $exitCode = [int]$process.ExitCode

      Set-Content -Path $stdoutPath -Value $stdoutTask.GetAwaiter().GetResult()
      Set-Content -Path $stderrPath -Value $stderrTask.GetAwaiter().GetResult()

      foreach ($path in @($stdoutPath, $stderrPath)) {
        if (-not (Test-Path $path)) {
          continue
        }

        $lines = @(Get-Content -Path $path)
        if ($lines.Count -eq 0) {
          continue
        }

        Add-Content -Path $LogPath -Value $lines
        foreach ($line in $lines) {
          Write-Host $line
        }
      }
    } finally {
      foreach ($path in @($stdoutPath, $stderrPath)) {
        if (Test-Path $path) {
          Remove-Item -Force $path
        }
      }
    }
  } finally {
    $env:PATH = $previousPath
    Pop-Location
  }

  if ($exitCode -ne 0) {
    throw "Command failed with exit code $exitCode. See log: $LogPath"
  }

  return [pscustomobject]@{
    ExitCode = $exitCode
    WorkingDirectory = $WorkingDirectory
    LogPath = $LogPath
    DryRun = $false
  }
}

function Invoke-GpGitCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$ArgumentList,
    [string]$WorkingDirectory
  )

  $git = Get-Command git -ErrorAction SilentlyContinue
  if ($null -eq $git -or [string]::IsNullOrWhiteSpace([string]$git.Source)) {
    throw "git was not found. Theme inputs that use repo require git."
  }

  $result = Invoke-GpCapturedProcess -FilePath ([string]$git.Source) -ArgumentList @($ArgumentList) -WorkingDirectory $WorkingDirectory
  if ($result.ExitCode -ne 0) {
    $detail = @($result.StdOut, $result.StdErr) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    throw ("git {0} failed. {1}" -f ([string]::Join(" ", @($ArgumentList))), ([string]::Join(" ", $detail)).Trim())
  }

  return $result
}

function Resolve-GpThemeSourcePath {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [psobject]$Theme,
    [string]$SourceRoot,
    [switch]$DryRun
  )

  if (-not [string]::IsNullOrWhiteSpace([string]$Theme.WorkspacePath)) {
    return Resolve-GpManifestPath -Context $Context -RelativePath ([string]$Theme.WorkspacePath)
  }

  $path = Join-Path $SourceRoot $Theme.Name
  if ($DryRun) {
    return $path
  }

  if (-not (Test-Path $path)) {
    Invoke-GpGitCommand -ArgumentList @("clone", "--", [string]$Theme.Repo, $path) | Out-Null
  }

  if (-not [string]::IsNullOrWhiteSpace([string]$Theme.Ref)) {
    Invoke-GpGitCommand -WorkingDirectory $path -ArgumentList @("fetch", "--tags", "--prune") | Out-Null
    Invoke-GpGitCommand -WorkingDirectory $path -ArgumentList @("checkout", "--", [string]$Theme.Ref) | Out-Null
  }

  return $path
}

function Get-GpGitResolvedCommit {
  param(
    [string]$Path
  )

  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path (Join-Path $Path ".git"))) {
    return $null
  }

  try {
    $result = Invoke-GpGitCommand -WorkingDirectory $Path -ArgumentList @("rev-parse", "HEAD")
    return $result.StdOut.Trim()
  } catch {
    return $null
  }
}

function Get-GpThemeBuildShellConfig {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [psobject]$Theme,
    [Parameter(Mandatory = $true)]
    [string]$InstallRoot,
    [string]$Backend
  )

  $manifestShell = $Context.Manifest["pipeline"]["shell"]
  $targetPlatform = Get-GpThemeTargetPlatform -Backend $Backend
  $shell = if ($manifestShell["kind"] -eq "msys2-bash" -or $targetPlatform -ne "windows") {
    Copy-GpValue -Value $manifestShell
  } else {
    @{
      kind = "msys2-bash"
      bootstrapCommands = @()
      environment = @{}
    }
    if ($manifestShell.Contains("msysRoot")) {
      $shell["msysRoot"] = [string]$manifestShell["msysRoot"]
    }
  }

  if (-not $shell.Contains("environment") -or -not ($shell["environment"] -is [System.Collections.IDictionary])) {
    $shell["environment"] = @{}
  }

  foreach ($key in @($Theme.BuildEnvironment.Keys)) {
    $shell["environment"][$key] = [string]$Theme.BuildEnvironment[$key]
  }

  $installRootForShell = if ($shell["kind"] -in @("bash", "sh", "msys2-bash")) {
    Convert-GpNativePathToPosix -Path $InstallRoot
  } else {
    $InstallRoot
  }
  $shell["environment"]["GNUSTEP_USER_ROOT"] = $installRootForShell

  if (-not $shell["environment"].Contains("CC")) { $shell["environment"]["CC"] = "clang" }
  if (-not $shell["environment"].Contains("OBJC_CC")) { $shell["environment"]["OBJC_CC"] = "clang" }
  if (-not $shell["environment"].Contains("CXX")) { $shell["environment"]["CXX"] = "clang++" }
  if (-not $shell["environment"].Contains("OBJCXX")) { $shell["environment"]["OBJCXX"] = "clang++" }
  if (-not $shell["environment"].Contains("CFLAGS")) { $shell["environment"]["CFLAGS"] = "-DHAVE_MODE_T=1" }
  if (-not $shell["environment"].Contains("OBJCFLAGS")) { $shell["environment"]["OBJCFLAGS"] = "-DHAVE_MODE_T=1" }
  if (-not $shell["environment"].Contains("GNUSTEP_MAKEFILES") -and -not [string]::IsNullOrWhiteSpace($env:GNUSTEP_MAKEFILES)) {
    $shell["environment"]["GNUSTEP_MAKEFILES"] = $env:GNUSTEP_MAKEFILES
  }

  return $shell
}

function Get-GpThemeBuildCommand {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Theme
  )

  if (-not [string]::IsNullOrWhiteSpace([string]$Theme.BuildCommand)) {
    return [string]$Theme.BuildCommand
  }

  $installCommand = if (-not [string]::IsNullOrWhiteSpace([string]$Theme.InstallCommand)) {
    [string]$Theme.InstallCommand
  } else {
    "make install GNUSTEP_INSTALLATION_DOMAIN=USER"
  }

  return ("make clean; make; {0}" -f $installCommand)
}

function Find-GpInstalledThemeBundle {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Roots,
    [Parameter(Mandatory = $true)]
    [string]$ThemeName
  )

  $leaf = ("{0}.theme" -f $ThemeName)
  foreach ($root in @($Roots)) {
    if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path $root)) {
      continue
    }

    foreach ($match in @(Get-ChildItem -Path $root -Directory -Recurse -Filter $leaf -ErrorAction SilentlyContinue | Select-Object -First 1)) {
      return [string]$match.FullName
    }
  }

  return $null
}

function Copy-GpThemeBundleToStage {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [string]$ThemeName,
    [Parameter(Mandatory = $true)]
    [string]$BundlePath
  )

  $stageRoot = Resolve-GpManifestPath -Context $Context -RelativePath $Context.Manifest["payload"]["stageRoot"]
  $themeRoot = Ensure-GpDirectory -Path (Join-Path $stageRoot "runtime/lib/GNUstep/Themes")
  $destination = Join-Path $themeRoot ("{0}.theme" -f $ThemeName)
  if (Test-Path $destination) {
    Remove-Item -Recurse -Force $destination
  }
  Copy-Item -Recurse -Force $BundlePath $destination
  return $destination
}

function Convert-GpPathToRelative {
  param(
    [Parameter(Mandatory = $true)]
    [string]$BasePath,
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $base = $BasePath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
  $baseUri = [System.Uri]::new($base)
  $pathUri = [System.Uri]::new($Path)
  return ([System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()) -replace "/", [System.IO.Path]::DirectorySeparatorChar)
}

function Write-GpThemePayloadReport {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [object[]]$Themes,
    [string]$Backend
  )

  $payload = $Context.Manifest["payload"]
  $stageRoot = Resolve-GpManifestPath -Context $Context -RelativePath $payload["stageRoot"]
  $metadataRootRelative = if ($payload.Contains("metadataRoot") -and -not [string]::IsNullOrWhiteSpace([string]$payload["metadataRoot"])) {
    [string]$payload["metadataRoot"]
  } else {
    "metadata"
  }
  $metadataRoot = Ensure-GpDirectory -Path (Resolve-GpPathRelativeToBase -BasePath $stageRoot -Path $metadataRootRelative)
  $reportPath = Join-Path $metadataRoot "gnustep-packager-theme-report.json"
  $items = @()

  foreach ($theme in @($Themes)) {
    $stagedPath = [string]$theme.StagedPath
    $structure = if (-not [string]::IsNullOrWhiteSpace($stagedPath) -and (Test-Path $stagedPath)) {
      Test-GpThemeBundleStructure -ThemePath $stagedPath -ThemeName ([string]$theme.Name) -Backend $Backend
    } else {
      $null
    }
    $items += [ordered]@{
      name = [string]$theme.Name
      source = [ordered]@{
        repo = $theme.Repo
        workspacePath = $theme.WorkspacePath
        sourcePath = $theme.SourcePath
        ref = $theme.RequestedRef
        resolvedCommit = $theme.ResolvedCommit
      }
      required = [bool]$theme.Required
      default = [bool]$theme.Default
      backend = $Backend
      stagedPath = $(if (-not [string]::IsNullOrWhiteSpace($stagedPath)) { Convert-GpPathToRelative -BasePath $stageRoot -Path $stagedPath } else { $null })
      executable = $(if ($null -ne $structure) { $structure.Executable } else { $null })
      info = $(if ($null -ne $structure) { $structure.InfoPath } else { $null })
      resources = $(if ($null -ne $structure) { @($structure.Resources) } else { @() })
      validationIssues = $(if ($null -ne $structure) { @($structure.Issues) } else { @() })
    }
  }

  $document = [ordered]@{
    formatVersion = 1
    generatedAt = (Get-Date).ToString("o")
    package = [ordered]@{
      id = [string]$Context.Manifest["package"]["id"]
      name = [string]$Context.Manifest["package"]["name"]
      version = [string]$Context.Manifest["package"]["version"]
    }
    themes = @($items)
  }

  $document | ConvertTo-Json -Depth 20 | Set-Content -Path $reportPath -Encoding utf8
  return $reportPath
}

function Invoke-GpThemeProvisioning {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [string]$Backend,
    [string]$LogPath,
    [switch]$DryRun
  )

  if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $LogPath = New-GpCommandLogPath -Context $Context -CommandName "provision-themes"
  }

  Ensure-GpDirectory -Path (Split-Path -Parent $LogPath) | Out-Null
  $outputPaths = Get-GpOutputPaths -Context $Context
  $sourceRoot = Ensure-GpDirectory -Path (Join-Path $outputPaths.TempRoot "theme-inputs/sources")
  $installBaseRoot = Ensure-GpDirectory -Path (Join-Path $outputPaths.TempRoot "theme-inputs/install")
  $lines = [System.Collections.Generic.List[string]]::new()
  $results = [System.Collections.Generic.List[psobject]]::new()
  $issues = [System.Collections.Generic.List[string]]::new()
  $themes = @(Get-GpThemeInputs -Manifest $Context.Manifest -Backend $Backend -ActiveOnly)

  $lines.Add(("[{0}] theme provisioning backend={1} dryRun={2}" -f (Get-Date).ToString("o"), $(if ([string]::IsNullOrWhiteSpace($Backend)) { "(host)" } else { $Backend }), [bool]$DryRun)) | Out-Null
  if ($themes.Count -eq 0) {
    $lines.Add("No active theme inputs apply.") | Out-Null
    Set-Content -Path $LogPath -Value $lines
    return [pscustomobject]@{
      Themes = @()
      LogPath = $LogPath
      DryRun = [bool]$DryRun
    }
  }

  foreach ($theme in @($themes)) {
    $lines.Add(("THEME   {0} required={1} default={2}" -f $theme.Name, $theme.Required, $theme.Default)) | Out-Null
    try {
      if ($Backend -eq "appimage") {
        $message = "Theme input provisioning for AppImage is not implemented yet."
        if ($theme.Required) {
          throw $message
        }
        $lines.Add(("WARN    {0}: {1}" -f $theme.Name, $message)) | Out-Null
        continue
      }

      $sourcePath = Resolve-GpThemeSourcePath -Context $Context -Theme $theme -SourceRoot $sourceRoot -DryRun:$DryRun
      $installRoot = Join-Path $installBaseRoot $theme.Name
      $resolvedCommit = if ($DryRun) { $null } else { Get-GpGitResolvedCommit -Path $sourcePath }
      $buildCommand = Get-GpThemeBuildCommand -Theme $theme
      $lines.Add(("SOURCE  {0}" -f $sourcePath)) | Out-Null
      if (-not [string]::IsNullOrWhiteSpace([string]$theme.Repo)) { $lines.Add(("REPO    {0}" -f $theme.Repo)) | Out-Null }
      if (-not [string]::IsNullOrWhiteSpace([string]$theme.Ref)) { $lines.Add(("REF     {0}" -f $theme.Ref)) | Out-Null }
      if (-not [string]::IsNullOrWhiteSpace($resolvedCommit)) { $lines.Add(("COMMIT  {0}" -f $resolvedCommit)) | Out-Null }
      $lines.Add(("BUILD   {0}" -f $buildCommand)) | Out-Null

      if ($DryRun) {
        $results.Add([pscustomobject]@{
          Name = $theme.Name
          Repo = $theme.Repo
          WorkspacePath = $theme.WorkspacePath
          SourcePath = $sourcePath
          RequestedRef = $theme.Ref
          ResolvedCommit = $resolvedCommit
          Required = $theme.Required
          Default = $theme.Default
          StagedPath = $null
          DryRun = $true
        }) | Out-Null
        continue
      }

      Ensure-GpDirectory -Path $installRoot | Out-Null
      $shellConfig = Get-GpThemeBuildShellConfig -Context $Context -Theme $theme -InstallRoot $installRoot -Backend $Backend
      $invocation = Get-GpShellInvocation -ShellConfig $shellConfig -Command $buildCommand
      $themeLogPath = New-GpCommandLogPath -Context $Context -CommandName ("provision-theme-" + $theme.Name)
      Invoke-GpShellCommand -Invocation $invocation -WorkingDirectory $sourcePath -LogPath $themeLogPath | Out-Null

      $bundlePath = Find-GpInstalledThemeBundle -Roots @($installRoot, $sourcePath) -ThemeName $theme.Name
      if ([string]::IsNullOrWhiteSpace($bundlePath)) {
        throw ("Theme bundle {0}.theme was not found after build/install. Checked {1} and {2}." -f $theme.Name, $installRoot, $sourcePath)
      }

      $stagedPath = Copy-GpThemeBundleToStage -Context $Context -ThemeName $theme.Name -BundlePath $bundlePath
      $lines.Add(("STAGED  {0}" -f $stagedPath)) | Out-Null
      $results.Add([pscustomobject]@{
        Name = $theme.Name
        Repo = $theme.Repo
        WorkspacePath = $theme.WorkspacePath
        SourcePath = $sourcePath
        RequestedRef = $theme.Ref
        ResolvedCommit = $resolvedCommit
        Required = $theme.Required
        Default = $theme.Default
        StagedPath = $stagedPath
        DryRun = $false
      }) | Out-Null
    } catch {
      $message = ("{0}: {1}" -f $theme.Name, $_.Exception.Message)
      if ($theme.Required) {
        $lines.Add(("FAIL    {0}" -f $message)) | Out-Null
        $issues.Add($message) | Out-Null
      } else {
        $lines.Add(("WARN    {0}" -f $message)) | Out-Null
      }
    }
  }

  Set-Content -Path $LogPath -Value $lines
  if ($issues.Count -gt 0) {
    throw ("Theme provisioning failed: {0}. See log: {1}" -f ([string]::Join("; ", @($issues.ToArray()))), $LogPath)
  }

  $reportPath = $null
  if (-not $DryRun -and $results.Count -gt 0) {
    $reportPath = Write-GpThemePayloadReport -Context $Context -Themes @($results.ToArray()) -Backend $Backend
    Add-Content -Path $LogPath -Value ("REPORT  {0}" -f $reportPath)
  }

  return [pscustomobject]@{
    Themes = @($results.ToArray())
    LogPath = $LogPath
    ReportPath = $reportPath
    DryRun = [bool]$DryRun
  }
}

function Invoke-GpPipelineCommand {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [ValidateSet("build", "stage")]
    [string]$StepName,
    [switch]$DryRun
  )

  $manifest = $Context.Manifest
  $pipeline = $manifest["pipeline"]
  $shellConfig = $pipeline["shell"]
  $step = $pipeline[$StepName]
  $workingDirectory = Resolve-GpManifestPath -Context $Context -RelativePath $pipeline["workingDirectory"]
  $logPath = New-GpCommandLogPath -Context $Context -CommandName $StepName
  $invocation = Get-GpShellInvocation -ShellConfig $shellConfig -Command ([string]$step["command"])
  $result = Invoke-GpShellCommand -Invocation $invocation -WorkingDirectory $workingDirectory -LogPath $logPath -DryRun:$DryRun

  return [pscustomobject]@{
    StepName = $StepName
    Command = [string]$step["command"]
    WorkingDirectory = $workingDirectory
    LogPath = $logPath
    DryRun = [bool]$DryRun
    ShellKind = $invocation.ShellKind
    OutputRoot = $(if ($step.Contains("outputRoot")) { Resolve-GpManifestPath -Context $Context -RelativePath ([string]$step["outputRoot"]) } else { $null })
    Result = $result
  }
}

function Resolve-GpBackendName {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Manifest,
    [string]$RequestedBackend
  )

  if (-not [string]::IsNullOrWhiteSpace($RequestedBackend)) {
    $backendName = $RequestedBackend.Trim()
    if (-not (Test-GpBackendEnabled -Manifest $Manifest -Backend $backendName)) {
      $enabledBackends = @(Get-GpEnabledBackends -Manifest $Manifest)
      $enabledText = if ($enabledBackends.Count -gt 0) { [string]::Join(", ", $enabledBackends) } else { "(none)" }
      throw "Requested backend '$backendName' is not enabled in the manifest. Enabled backends: $enabledText"
    }
    return $backendName
  }

  $enabledBackends = @(Get-GpEnabledBackends -Manifest $Manifest)
  if ($enabledBackends.Count -eq 1) {
    return $enabledBackends[0]
  }

  if ($enabledBackends.Count -eq 0) {
    throw "No enabled backends found in manifest."
  }

  throw "Multiple enabled backends found. Specify -Backend explicitly."
}

function Invoke-GpSharedValidation {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [switch]$DryRun
  )

  $plan = Get-GpValidationPlan -Context $Context
  $outputPaths = Get-GpOutputPaths -Context $Context
  Ensure-GpDirectory -Path $outputPaths.ValidationRoot | Out-Null
  $logPath = New-GpCommandLogPath -Context $Context -CommandName "validate"

  if ($DryRun) {
    Set-Content -Path $logPath -Value "Shared validation dry-run"
    return [pscustomobject]@{
      Mode = "dry-run"
      LogPath = $logPath
      Plan = $plan
    }
  }

  $missing = [System.Collections.Generic.List[string]]::new()
  $lines = [System.Collections.Generic.List[string]]::new()
  $lines.Add(("Validation kind: {0}" -f $plan.Kind)) | Out-Null

  foreach ($item in $plan.RequiredPaths) {
    if ($item.PSObject.Properties["IsPattern"] -and [bool]$item.IsPattern) {
      $matches = @(Resolve-GpValidationPathMatches -ResolvedPath $item.Path)
      if ($matches.Count -gt 0) {
        $lines.Add(("OK      {0} -> {1}" -f $item.Label, $item.Pattern)) | Out-Null
        foreach ($match in $matches) {
          $lines.Add(("MATCH   {0}" -f $match)) | Out-Null
        }
      } else {
        $message = ("MISSING {0} -> {1}" -f $item.Label, $item.Pattern)
        $lines.Add($message) | Out-Null
        $missing.Add($message) | Out-Null
      }
    } elseif (Test-Path $item.Path) {
      $lines.Add(("OK      {0} -> {1}" -f $item.Label, $item.Path)) | Out-Null
    } else {
      $message = ("MISSING {0} -> {1}" -f $item.Label, $item.Path)
      $lines.Add($message) | Out-Null
      $missing.Add($message) | Out-Null
    }
  }

  $stageContract = Invoke-GpPackageContractAssertions -Context $Context -Scope "stage"
  foreach ($issue in @($stageContract.Issues)) {
    $missing.Add($issue) | Out-Null
  }

  if ($lines.Count -gt 0) {
    Set-Content -Path $logPath -Value $lines
    if (@($stageContract.Lines).Count -gt 0) {
      Add-Content -Path $logPath -Value ""
      Add-Content -Path $logPath -Value "[stage contract]"
      Add-Content -Path $logPath -Value @($stageContract.Lines)
    }
  } else {
    Set-Content -Path $logPath -Value @($stageContract.Lines)
  }

  if ($missing.Count -gt 0) {
    throw "Shared validation failed. See log: $logPath"
  }

  return [pscustomobject]@{
    Mode = "execute"
    LogPath = $logPath
    Plan = $plan
  }
}

function Get-GpManifestSummary {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Manifest
  )

  $package = $Manifest["package"]
  $pipeline = $Manifest["pipeline"]
  $payload = $Manifest["payload"]
  $launch = $Manifest["launch"]
  $outputs = $Manifest["outputs"]
  $validation = $Manifest["validation"]
  $updates = if ($Manifest.Contains("updates") -and ($Manifest["updates"] -is [System.Collections.IDictionary])) {
    $Manifest["updates"]
  } else {
    @{}
  }

  return [pscustomobject]@{
    PackageId       = $package["id"]
    Name            = $package["name"]
    Version         = $package["version"]
    Manufacturer    = $package["manufacturer"]
    Profiles        = [string[]](Get-GpRequestedProfiles -Manifest $Manifest)
    StageRoot       = $payload["stageRoot"]
    EntryRelative   = $launch["entryRelativePath"]
    BuildCommand    = $pipeline["build"]["command"]
    StageCommand    = $pipeline["stage"]["command"]
    ShellKind       = $pipeline["shell"]["kind"]
    LogRoot         = $outputs["logRoot"]
    PackageRoot     = $outputs["packageRoot"]
    ValidationKind  = $validation["smoke"]["kind"]
    UpdatesEnabled  = [bool]($updates.Contains("enabled") -and $updates["enabled"])
    UpdateChannel   = $(if ($updates.Contains("channel")) { [string]$updates["channel"] } else { $null })
    ComplianceNoticeCount = @(Get-GpComplianceEntries -Manifest $Manifest).Count
    EnabledBackends = [string[]](Get-GpEnabledBackends -Manifest $Manifest)
  }
}
