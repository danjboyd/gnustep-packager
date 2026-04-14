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
    Environment           = [hashtable](Get-GpNormalizedLaunchEnvironment -Environment $launch["env"])
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
  try {
    $argumentList = @($Invocation.ArgumentList)
    $streamRoot = Split-Path -Parent $LogPath
    $streamId = [guid]::NewGuid().ToString("N")
    $stdoutPath = Join-Path $streamRoot ("{0}.stdout.tmp" -f $streamId)
    $stderrPath = Join-Path $streamRoot ("{0}.stderr.tmp" -f $streamId)

    try {
      # Native Windows toolchains regularly emit warnings on stderr even when the
      # process succeeds. Capture both streams as plain text and use only the
      # native exit code as the success/failure signal.
      $process = Start-Process `
        -FilePath $Invocation.FilePath `
        -ArgumentList $argumentList `
        -WorkingDirectory $WorkingDirectory `
        -NoNewWindow `
        -Wait `
        -PassThru `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath
      $exitCode = [int]$process.ExitCode

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
