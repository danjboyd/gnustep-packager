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
  return (Get-Content -Raw -Path $resolvedPath | ConvertFrom-Json -AsHashtable)
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
  return (Merge-GpHashtable -Base $defaults -Overlay $Manifest)
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
  }

  $outputs = Require-Object -Parent $Manifest -Key "outputs" -Label "outputs"
  if ($outputs) {
    foreach ($key in @("root", "packageRoot", "logRoot", "tempRoot", "validationRoot")) {
      Require-String -Parent $outputs -Key $key -Label ("outputs." + $key)
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
  }

  if ($Manifest.Contains("backends") -and ($Manifest["backends"] -is [System.Collections.IDictionary])) {
    $backends = $Manifest["backends"]

    if ($backends.Contains("msi") -and ($backends["msi"] -is [System.Collections.IDictionary])) {
      $msi = $backends["msi"]
      if ($msi.Contains("enabled") -and $msi["enabled"]) {
        Require-String -Parent $msi -Key "upgradeCode" -Label "backends.msi.upgradeCode"
        Require-String -Parent $msi -Key "artifactNamePattern" -Label "backends.msi.artifactNamePattern"
      }
    }

    if ($backends.Contains("appimage") -and ($backends["appimage"] -is [System.Collections.IDictionary])) {
      $appimage = $backends["appimage"]
      if ($appimage.Contains("enabled") -and $appimage["enabled"]) {
        Require-String -Parent $appimage -Key "desktopEntryName" -Label "backends.appimage.desktopEntryName"
        Require-String -Parent $appimage -Key "artifactNamePattern" -Label "backends.appimage.artifactNamePattern"
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
      return [pscustomobject]@{
        FilePath     = $(if ($ShellConfig.Contains("program")) { [string]$ShellConfig["program"] } else { "pwsh" })
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
        FilePath     = $(if ($ShellConfig.Contains("program")) { [string]$ShellConfig["program"] } else { "bash" })
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
        FilePath     = $(if ($ShellConfig.Contains("program")) { [string]$ShellConfig["program"] } else { "sh" })
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
    Environment           = [hashtable](Copy-GpValue -Value $launch["env"])
    WindowsEntryPath      = Convert-GpNativePathToWindows -Path $entryPath
    PosixEntryPath        = Convert-GpNativePathToPosix -Path $entryPath
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
      $requiredPaths.Add([pscustomobject]@{
        Label = "smoke:$path"
        Path  = Resolve-GpPathRelativeToBase -BasePath $stageRoot -Path $path
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
  try {
    $global:LASTEXITCODE = 0
    $argumentList = @($Invocation.ArgumentList)
    & $Invocation.FilePath @argumentList 2>&1 | Tee-Object -FilePath $LogPath -Append | Out-Host
    $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
  } finally {
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
    if (Test-Path $item.Path) {
      $lines.Add(("OK      {0} -> {1}" -f $item.Label, $item.Path)) | Out-Null
    } else {
      $message = ("MISSING {0} -> {1}" -f $item.Label, $item.Path)
      $lines.Add($message) | Out-Null
      $missing.Add($message) | Out-Null
    }
  }

  Set-Content -Path $logPath -Value $lines

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
    ComplianceNoticeCount = @(Get-GpComplianceEntries -Manifest $Manifest).Count
    EnabledBackends = [string[]](Get-GpEnabledBackends -Manifest $Manifest)
  }
}
