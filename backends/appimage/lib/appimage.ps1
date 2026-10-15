Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-GpAppImageLogLine {
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

function Reset-GpAppImageDirectory {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (Test-Path $Path) {
    Remove-Item -Recurse -Force $Path
  }
  Ensure-GpDirectory -Path $Path | Out-Null
}

function Copy-GpRelativeStagePathToAppDir {
  param(
    [Parameter(Mandatory = $true)]
    [string]$StageRoot,
    [Parameter(Mandatory = $true)]
    [string]$RelativePath,
    [Parameter(Mandatory = $true)]
    [string]$UsrRoot
  )

  $source = Resolve-GpPathRelativeToBase -BasePath $StageRoot -Path $RelativePath
  if (-not (Test-Path $source)) {
    return $null
  }

  $parentRelative = Split-Path -Path $RelativePath -Parent
  $leafName = Split-Path -Path $RelativePath -Leaf
  $destinationParent = if ([string]::IsNullOrWhiteSpace($parentRelative) -or $parentRelative -eq ".") {
    $UsrRoot
  } else {
    Ensure-GpDirectory -Path (Join-Path $UsrRoot $parentRelative)
  }
  $destination = Join-Path $destinationParent $leafName

  if (-not $IsWindows) {
    # cp -a keeps the stage's symbolic links (libgnustep-gui.so ->
    # libgnustep-gui.so.0 -> libgnustep-gui.so.0.32.0) instead of copying the
    # file once per name; a link that leaves the stage is then replaced by
    # what it points to, so the AppImage never refers to the build host.
    if ((Get-Item -LiteralPath $source) -is [System.IO.DirectoryInfo]) {
      Ensure-GpDirectory -Path $destination | Out-Null
      & cp -a -- ("{0}/." -f $source) $destination
    } else {
      Ensure-GpDirectory -Path (Split-Path -Parent $destination) | Out-Null
      & cp -a -- $source $destination
    }
    if ($LASTEXITCODE -ne 0) {
      throw "Copying the staged $RelativePath into the AppDir failed (cp -a exit $LASTEXITCODE)."
    }
    Resolve-GpAppImageEscapingLinks -StageRoot $StageRoot -SourceRoot $source -DestinationRoot $destination
    return $destination
  }

  if ((Get-Item $source) -is [System.IO.DirectoryInfo]) {
    Copy-Item -Recurse -Force $source $destination
  } else {
    Ensure-GpDirectory -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -Force $source $destination
  }

  return $destination
}

# Replaces each symbolic link copied into the AppDir whose target, resolved
# from its place in the stage, is outside the stage (an absolute path such as
# /usr/lib/..., or ../ past the stage root) with a copy of what it points to.
# Links within the stage stay links.
function Resolve-GpAppImageEscapingLinks {
  param(
    [Parameter(Mandatory = $true)]
    [string]$StageRoot,
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,
    [Parameter(Mandatory = $true)]
    [string]$DestinationRoot
  )

  $stageFull = [System.IO.Path]::GetFullPath($StageRoot).TrimEnd("/") + "/"
  $sourceFull = [System.IO.Path]::GetFullPath($SourceRoot)
  $links = if (Test-Path -LiteralPath $DestinationRoot -PathType Container) {
    @(Get-ChildItem -LiteralPath $DestinationRoot -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue)
  } else {
    @(Get-Item -LiteralPath $DestinationRoot -Force | Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint })
  }

  foreach ($link in $links) {
    $target = [string]$link.LinkTarget
    if ([string]::IsNullOrEmpty($target)) {
      continue
    }
    $relativeToDestination = [System.IO.Path]::GetRelativePath($DestinationRoot, $link.FullName)
    $sourceLink = if ($relativeToDestination -eq ".") { $sourceFull } else { Join-Path $sourceFull $relativeToDestination }
    $resolved = if ([System.IO.Path]::IsPathRooted($target)) {
      [System.IO.Path]::GetFullPath($target)
    } else {
      [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $sourceLink) $target))
    }
    if ($resolved.StartsWith($stageFull, [System.StringComparison]::Ordinal)) {
      continue
    }

    Remove-Item -LiteralPath $link.FullName -Force
    & cp -a -L -- $sourceLink $link.FullName
    if ($LASTEXITCODE -ne 0) {
      throw "The staged link $sourceLink points outside the stage ($target), and what it points to could not be copied into the AppDir."
    }
  }
}

function Set-GpUnixExecutable {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if ($IsWindows) {
    return
  }

  & chmod "+x" $Path
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to mark file executable: $Path"
  }
}

function Escape-GpShDoubleQuotedLiteral {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value
  )

  return (($Value -replace "\\", "\\\\") -replace '"', '\"' -replace '\$', '\$' -replace '`', '\`')
}

function Get-GpAppImageDiagnosticsDocPath {
  return (Join-Path (Get-GpToolRoot) "backends\\appimage\\README.md")
}

function Get-GpAppImageSidecarPaths {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Config
  )

  return [pscustomobject]@{
    MetadataPath = Get-GpArtifactSidecarPath -ArtifactPath $Config.ArtifactPlan.ArtifactPath -Suffix "metadata.json"
    DiagnosticsPath = Get-GpArtifactSidecarPath -ArtifactPath $Config.ArtifactPlan.ArtifactPath -Suffix "diagnostics.txt"
  }
}

function Convert-GpAppImageIdentifierFragment {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value
  )

  $normalized = $Value.ToLowerInvariant() -replace "[^a-z0-9]+", "-"
  $normalized = $normalized.Trim("-")
  if ([string]::IsNullOrWhiteSpace($normalized)) {
    return "app"
  }
  return $normalized
}

function Get-GpAppImageGeneratedMimeType {
  param(
    [Parameter(Mandatory = $true)]
    [string]$PackageName,
    [Parameter(Mandatory = $true)]
    [string]$Extension
  )

  $extensionValue = if ($Extension.StartsWith(".")) { $Extension.Substring(1) } else { $Extension }
  return ("application/x-{0}-{1}" -f (Convert-GpAppImageIdentifierFragment -Value $PackageName), (Convert-GpAppImageIdentifierFragment -Value $extensionValue))
}

function Get-GpAppImageMimeEntries {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [psobject]$Config
  )

  $entries = [System.Collections.Generic.List[psobject]]::new()
  $integrations = $Context.Manifest["integrations"]
  foreach ($association in @($integrations["fileAssociations"])) {
    if (-not ($association -is [System.Collections.IDictionary])) {
      continue
    }

    $kind = [string]$association["kind"]
    $value = [string]$association["value"]
    $description = if ($association.Contains("description")) { [string]$association["description"] } else { $null }

    if ([string]::IsNullOrWhiteSpace($kind) -or [string]::IsNullOrWhiteSpace($value)) {
      continue
    }

    switch ($kind) {
      "mime" {
        $entries.Add([pscustomobject]@{
          Kind = $kind
          MimeType = $value
          Description = $description
          GlobPattern = $null
          Generated = $false
        }) | Out-Null
      }

      "extension" {
        $extension = if ($value.StartsWith(".")) { $value } else { "." + $value }
        $entries.Add([pscustomobject]@{
          Kind = $kind
          MimeType = Get-GpAppImageGeneratedMimeType -PackageName $Config.PackageName -Extension $extension
          Description = $description
          GlobPattern = ("*" + $extension)
          Generated = $true
        }) | Out-Null
      }
    }
  }

  return @($entries.ToArray())
}

function Get-GpAppImageDesktopMimeTypes {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [psobject[]]$MimeEntries
  )

  return [string[]]@($MimeEntries | ForEach-Object { $_.MimeType } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Resolve-GpAppImageArtifactNamePattern {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Pattern,
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Package,
    [Parameter(Mandatory = $true)]
    [string]$VersionToken
  )

  return (Resolve-GpPatternTokens -Pattern $Pattern -Tokens @{
    name = [string]$Package["name"]
    version = $VersionToken
    packageId = [string]$Package["id"]
    backend = "appimage"
  })
}

function ConvertTo-GpAppImageGlobalDefaultEntries {
  param(
    [AllowNull()]
    [object]$Values
  )

  # A manifest map of defaults, as typed entries for GlobalDefaults.plist.
  if (-not ($Values -is [System.Collections.IDictionary])) {
    return @()
  }
  return @(
    foreach ($key in @($Values.Keys | Sort-Object)) {
      $value = $Values[$key]
      $type = if ($value -is [bool]) { "bool" } elseif ($value -is [int] -or $value -is [long]) { "integer" } elseif ($value -is [double] -or $value -is [decimal]) { "number" } else { "string" }
      [pscustomobject]@{ Key = [string]$key; Type = $type; Value = $value }
    }
  )
}

function Get-GpAppImageConfig {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context
  )

  $manifest = $Context.Manifest
  $package = $manifest["package"]
  $payload = $manifest["payload"]
  $backend = $manifest["backends"]["appimage"]
  $artifactPlan = Get-GpArtifactPlan -Context $Context -Backend "appimage"
  $outputPaths = Get-GpOutputPaths -Context $Context
  $updateSettings = Get-GpUpdateSettings -Context $Context -Backend "appimage"
  $displayName = if ($package.Contains("displayName") -and -not [string]::IsNullOrWhiteSpace([string]$package["displayName"])) {
    [string]$package["displayName"]
  } else {
    [string]$package["name"]
  }
  $desktopEntryName = [string]$backend["desktopEntryName"]
  $desktopEntryBaseName = [System.IO.Path]::GetFileNameWithoutExtension($desktopEntryName)
  if ([string]::IsNullOrWhiteSpace($desktopEntryBaseName)) {
    $desktopEntryBaseName = [string]$package["name"]
  }
  $smoke = if ($backend.Contains("smoke") -and ($backend["smoke"] -is [System.Collections.IDictionary])) {
    $backend["smoke"]
  } else {
    @{}
  }
  $validation = if ($backend.Contains("validation") -and ($backend["validation"] -is [System.Collections.IDictionary])) {
    $backend["validation"]
  } else {
    @{}
  }
  $backendUpdates = if ($backend.Contains("updates") -and ($backend["updates"] -is [System.Collections.IDictionary])) {
    $backend["updates"]
  } else {
    @{}
  }

  $gnustepConfig = if ($backend.Contains("gnustepConfig") -and ($backend["gnustepConfig"] -is [System.Collections.IDictionary])) {
    $backend["gnustepConfig"]
  } else {
    @{}
  }
  $gnustepSystemRoot = if ($gnustepConfig.Contains("systemRoot")) { [string]$gnustepConfig["systemRoot"] } else { "" }
  $gnustepDefaultTheme = $null
  if ($gnustepConfig.Contains("defaultTheme") -and ($gnustepConfig["defaultTheme"] -is [System.Collections.IDictionary]) -and -not [string]::IsNullOrWhiteSpace([string]$gnustepConfig["defaultTheme"]["name"])) {
    if ([string]::IsNullOrWhiteSpace($gnustepSystemRoot)) {
      throw "backends.appimage.gnustepConfig.defaultTheme requires backends.appimage.gnustepConfig.systemRoot."
    }
    $gnustepDefaultTheme = [pscustomobject]@{
      Name = [string]$gnustepConfig["defaultTheme"]["name"]
      Desktops = [string[]]@($gnustepConfig["defaultTheme"]["desktops"] | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
      Defaults = @(ConvertTo-GpAppImageGlobalDefaultEntries -Values $gnustepConfig["defaultTheme"]["defaults"])
    }
  }

  $gnustepGlobalDefaults = @()
  if ($gnustepConfig.Contains("globalDefaults") -and ($gnustepConfig["globalDefaults"] -is [System.Collections.IDictionary])) {
    if ([string]::IsNullOrWhiteSpace($gnustepSystemRoot)) {
      throw "backends.appimage.gnustepConfig.globalDefaults requires backends.appimage.gnustepConfig.systemRoot."
    }
    $gnustepGlobalDefaults = @(ConvertTo-GpAppImageGlobalDefaultEntries -Values $gnustepConfig["globalDefaults"])
  }

  # The user's GNUstep Library (~/GNUstep/Library) holds themes and bundles built against the
  # host's GNUstep, which the bundled runtime can't load. "app" gives the AppImage a Library of
  # its own instead; "host" keeps the user's.
  $gnustepUserLibrary = if ($gnustepConfig.Contains("userLibrary")) { [string]$gnustepConfig["userLibrary"] } else { "app" }
  if ($gnustepUserLibrary -notin @("app", "host")) {
    throw "backends.appimage.gnustepConfig.userLibrary must be 'app' or 'host', not '$gnustepUserLibrary'."
  }

  $bundledFonts = @()
  if ($backend.Contains("fonts") -and ($backend["fonts"] -is [System.Collections.IDictionary]) -and $backend["fonts"].Contains("bundle")) {
    $bundledFonts = @(
      foreach ($font in @($backend["fonts"]["bundle"])) {
        $fontName = [string]$font["name"]
        if ([string]::IsNullOrWhiteSpace($fontName)) {
          throw "backends.appimage.fonts.bundle entries need a name."
        }
        if ([string]::IsNullOrWhiteSpace([string]$font["licenseFile"])) {
          throw "backends.appimage.fonts.bundle '$fontName' needs a licenseFile: the font's license ships with it."
        }
        [pscustomobject]@{
          Name = $fontName
          DirectoryName = Convert-GpAppImageIdentifierFragment -Value $fontName
          Files = [string[]]@(@($font["files"]) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { Resolve-GpManifestPath -Context $Context -RelativePath ([string]$_) })
          LicenseFile = Resolve-GpManifestPath -Context $Context -RelativePath ([string]$font["licenseFile"])
          License = $(if ($font.Contains("license")) { [string]$font["license"] } else { $null })
          Homepage = $(if ($font.Contains("homepage")) { [string]$font["homepage"] } else { $null })
        }
      }
    )
  }

  $downloadUrl = [string]$backend["downloadUrl"]
  $downloadLeaf = Split-Path -Leaf $downloadUrl
  if ([string]::IsNullOrWhiteSpace($downloadLeaf)) {
    $downloadLeaf = "appimagetool-x86_64.AppImage"
  }
  $appDirName = Resolve-GpPatternTokens -Pattern ([string]$backend["appDirName"]) -Tokens @{
    name = $package["name"]
    version = $package["version"]
    packageId = $package["id"]
    backend = "appimage"
  }
  $zsyncArtifactPattern = if ($backendUpdates.Contains("zsyncArtifactNamePattern") -and -not [string]::IsNullOrWhiteSpace([string]$backendUpdates["zsyncArtifactNamePattern"])) {
    [string]$backendUpdates["zsyncArtifactNamePattern"]
  } else {
    "{name}-{version}-x86_64.AppImage.zsync"
  }
  $zsyncArtifactName = Resolve-GpAppImageArtifactNamePattern -Pattern $zsyncArtifactPattern -Package $package -VersionToken ([string]$package["version"])
  $zsyncLookupPattern = Resolve-GpAppImageArtifactNamePattern -Pattern $zsyncArtifactPattern -Package $package -VersionToken "*"
  $releaseSelector = if ($backendUpdates.Contains("releaseSelector") -and -not [string]::IsNullOrWhiteSpace([string]$backendUpdates["releaseSelector"])) {
    [string]$backendUpdates["releaseSelector"]
  } else {
    "latest"
  }
  $embedUpdateInformation = [bool]($backendUpdates.Contains("embedUpdateInformation") -and $backendUpdates["embedUpdateInformation"])
  $updateInformation = if ($backendUpdates.Contains("updateInformation") -and -not [string]::IsNullOrWhiteSpace([string]$backendUpdates["updateInformation"])) {
    [string]$backendUpdates["updateInformation"]
  } elseif ($updateSettings.Enabled -and $embedUpdateInformation) {
    if ([string]::IsNullOrWhiteSpace([string]$updateSettings.GitHub.Owner) -or [string]::IsNullOrWhiteSpace([string]$updateSettings.GitHub.Repo)) {
      throw "AppImage updates require updates.github.owner and updates.github.repo when backends.appimage.updates.embedUpdateInformation is enabled."
    }

    "gh-releases-zsync|{0}|{1}|{2}|{3}" -f [string]$updateSettings.GitHub.Owner, [string]$updateSettings.GitHub.Repo, $releaseSelector, $zsyncLookupPattern
  } else {
    $null
  }

  return [pscustomobject]@{
    PackageId = [string]$package["id"]
    PackageName = [string]$package["name"]
    DisplayName = $displayName
    Summary = $(if ($package.Contains("summary")) { [string]$package["summary"] } else { $null })
    Description = $(if ($package.Contains("description")) { [string]$package["description"] } else { $null })
    Version = [string]$package["version"]
    Manufacturer = [string]$package["manufacturer"]
    Homepage = $(if ($package.Contains("homepage")) { [string]$package["homepage"] } else { $null })
    License = $(if ($package.Contains("license")) { [string]$package["license"] } else { $null })
    StageRoot = Resolve-GpManifestPath -Context $Context -RelativePath ([string]$payload["stageRoot"])
    AppRootRelative = [string]$payload["appRoot"]
    RuntimeRootRelative = [string]$payload["runtimeRoot"]
    MetadataRootRelative = [string]$payload["metadataRoot"]
    ArtifactPlan = $artifactPlan
    OutputPaths = $outputPaths
    AppDirName = $appDirName
    DesktopEntryName = $desktopEntryName
    DesktopEntryBaseName = $desktopEntryBaseName
    IconRelativePath = [string]$backend["iconRelativePath"]
    IconFileName = [System.IO.Path]::GetFileName([string]$backend["iconRelativePath"])
    IconName = $desktopEntryBaseName
    IconExtension = ([System.IO.Path]::GetExtension([string]$backend["iconRelativePath"]).TrimStart(".").ToLowerInvariant())
    AppImageToolRoot = Resolve-GpPathRelativeToBase -BasePath $Context.ToolRoot -Path ([string]$backend["toolRoot"])
    AppImageToolDownloadUrl = $downloadUrl
    AppImageToolFileName = $downloadLeaf
    SkipAppStreamValidation = [bool]$backend["skipAppStreamValidation"]
    GnustepConfig = [pscustomobject]@{
      Enabled = -not [string]::IsNullOrWhiteSpace($gnustepSystemRoot)
      SystemRootRelative = $gnustepSystemRoot
      DefaultTheme = $gnustepDefaultTheme
      GlobalDefaults = @($gnustepGlobalDefaults)
      UserLibraryRelative = if ($gnustepUserLibrary -eq "app") { "GNUstep/Library/AppImage/" + [string]$package["id"] } else { $null }
    }
    BundledFonts = @($bundledFonts)
    Validation = [pscustomobject]@{
      RuntimeClosure = [string]$validation["runtimeClosure"]
      AllowedSystemLibraries = [string[]]@($validation["allowedSystemLibraries"])
      AllowedExternalRunpaths = [string[]]@($validation["allowedExternalRunpaths"])
    }
    Updates = [pscustomobject]@{
      Enabled = [bool]$updateSettings.Enabled
      FeedUrl = $updateSettings.FeedUrl
      Channel = $updateSettings.Channel
      ReleaseTag = $updateSettings.GitHub.Tag
      ReleaseNotesUrl = $updateSettings.GitHub.ReleaseNotesUrl
      RuntimeConfigRelativePath = $updateSettings.RuntimeConfigRelativePath
      EmbedUpdateInformation = [bool]$embedUpdateInformation
      ReleaseSelector = $releaseSelector
      UpdateInformation = $updateInformation
      ZsyncArtifactName = $zsyncArtifactName
      ZsyncArtifactPath = Join-Path $outputPaths.PackageRoot $zsyncArtifactName
      ZsyncLookupPattern = $zsyncLookupPattern
    }
    Smoke = [pscustomobject]@{
      Mode = [string]$smoke["mode"]
      Arguments = [string[]]@($smoke["arguments"])
      Environment = $(if ($smoke.Contains("environment") -and ($smoke["environment"] -is [System.Collections.IDictionary])) {
        [hashtable](Copy-GpValue -Value $smoke["environment"])
      } else {
        @{}
      })
      DocumentStageRelativePath = $(if ($smoke.Contains("documentStageRelativePath") -and -not [string]::IsNullOrWhiteSpace([string]$smoke["documentStageRelativePath"])) {
        [string]$smoke["documentStageRelativePath"]
      } else {
        $null
      })
      StartupSeconds = $(if ($smoke.Contains("startupSeconds")) { [int]$smoke["startupSeconds"] } else { 5 })
      AllowStartupAlert = $(if ($smoke.Contains("allowStartupAlert")) { [bool]$smoke["allowStartupAlert"] } else { $false })
    }
  }
}

function Get-GpAppImageWorkPaths {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [psobject]$Config
  )

  $outputPaths = Get-GpOutputPaths -Context $Context
  $workRoot = Join-Path (Join-Path $outputPaths.TempRoot "appimage") (New-GpTimestamp)
  return [pscustomobject]@{
    Root = $workRoot
    AppDirRoot = Join-Path $workRoot $Config.AppDirName
    ExtractRoot = Join-Path $workRoot "extract"
    DownloadRoot = Join-Path $workRoot "downloads"
  }
}

function Get-GpAppImageSmokePlan {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [string]$ValidationRoot
  )

  $smoke = $Config.Smoke
  $environment = [hashtable](Copy-GpValue -Value $smoke.Environment)
  $arguments = [System.Collections.Generic.List[string]]::new()
  $markerPath = $null
  $documentPath = $null
  $appDefaults = Get-GpAppImageAppDomainDefaults -Context $Context

  if ($null -ne $appDefaults -and @($appDefaults.Entries).Count -gt 0 -and -not $environment.ContainsKey("HOME")) {
    # The smoke launch's fresh home (Get-GpAppImageSmokeBaseEnvironment).
    $environment["HOME"] = Join-Path $ValidationRoot "smoke-env/home"
  }

  switch ($smoke.Mode) {
    "launch-only" {
    }

    "custom-arguments" {
      foreach ($argument in @($smoke.Arguments)) {
        $arguments.Add([string]$argument) | Out-Null
      }
    }

    "open-file" {
      if ([string]::IsNullOrWhiteSpace($smoke.DocumentStageRelativePath)) {
        throw "AppImage smoke mode 'open-file' requires backends.appimage.smoke.documentStageRelativePath."
      }
      foreach ($argument in @($smoke.Arguments)) {
        $arguments.Add([string]$argument) | Out-Null
      }
      $documentPath = Resolve-GpStagePath -Context $Context -RelativePath $smoke.DocumentStageRelativePath
      if (-not (Test-Path $documentPath)) {
        throw "Configured AppImage smoke document does not exist in the staged payload: $documentPath"
      }
      $arguments.Add($documentPath) | Out-Null
    }

    "marker-file" {
      $markerPath = Join-Path $ValidationRoot "smoke-marker.txt"
      $environment["GP_APPIMAGE_SMOKE_MARKER_PATH"] = $markerPath
      $arguments.Add($markerPath) | Out-Null
    }

    default {
      throw "Unsupported AppImage smoke mode: $($smoke.Mode)"
    }
  }

  Assert-GpAppImageEnvironmentKeys -Environment $environment -Label "AppImage smoke"
  return [pscustomobject]@{
    Mode = $smoke.Mode
    Arguments = [string[]]@($arguments.ToArray())
    Environment = $environment
    MarkerPath = $markerPath
    DocumentPath = $documentPath
    StartupSeconds = [int]$smoke.StartupSeconds
    AllowStartupAlert = [bool]$smoke.AllowStartupAlert
  }
}

# Output that means the app is missing part of its runtime or hit an
# exception, even when it keeps running. GNUstep logs these and carries on.
$script:GpAppImageSmokeFailurePatterns = @(
  [pscustomobject]@{ Pattern = 'Glyph generation with no font'; Reason = "the app found no font it can use (see backends.appimage.fonts.bundle)" },
  [pscustomobject]@{ Pattern = 'Unable to find (the )?(backend|gdnc|gpbs|\S+ tool)'; Reason = "the app could not find a runtime component" },
  [pscustomobject]@{ Pattern = '[Uu]ncaught exception'; Reason = "the app raised an uncaught exception" },
  [pscustomobject]@{ Pattern = 'ignoring exception'; Reason = "the app raised an exception during startup" },
  [pscustomobject]@{ Pattern = 'Problem posting .*NSException'; Reason = "the app raised an exception during startup" },
  [pscustomobject]@{ Pattern = 'error while loading shared libraries'; Reason = "a shared library is missing from the AppImage" },
  [pscustomobject]@{ Pattern = 'version .GLIBC_[0-9.]+. not found'; Reason = "a bundled library needs a newer glibc than the host has" }
)

# The environment the smoke launch starts from, in place of the caller's:
# a minimal PATH and fresh home, XDG, and temporary directories under the
# validation root, so the app cannot lean on the build machine (a GNUstep
# tool on PATH, a services cache in ~/GNUstep, a session bus) or write to
# the user's own files. gnustep-base takes the home directory from the
# passwd database, not HOME, unless GNUSTEP_HOME is set, so both are set.
# Only the display variables are passed through, and WAYLAND_DISPLAY only
# when there is no DISPLAY: with an X display (often a private Xvfb), it
# would let GTK reach the user's desktop session.
function Get-GpAppImageSmokeBaseEnvironment {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ValidationRoot
  )

  $smokeRoot = Join-Path $ValidationRoot "smoke-env"
  if (Test-Path $smokeRoot) {
    Remove-Item -Recurse -Force $smokeRoot
  }

  $homePath = Join-Path $smokeRoot "home"
  $runtimePath = Join-Path $smokeRoot "runtime"
  $tempPath = Join-Path $smokeRoot "tmp"
  foreach ($directory in @($homePath, $runtimePath, $tempPath)) {
    Ensure-GpDirectory -Path $directory | Out-Null
  }
  & chmod 700 $runtimePath

  $environment = [ordered]@{
    PATH = "/usr/bin:/bin"
    HOME = $homePath
    GNUSTEP_HOME = $homePath
    XDG_CONFIG_HOME = Join-Path $homePath ".config"
    XDG_DATA_HOME = Join-Path $homePath ".local/share"
    XDG_CACHE_HOME = Join-Path $homePath ".cache"
    XDG_STATE_HOME = Join-Path $homePath ".local/state"
    XDG_RUNTIME_DIR = $runtimePath
    TMPDIR = $tempPath
    LANG = "C.UTF-8"
    DBUS_SESSION_BUS_ADDRESS = "unix:path=" + (Join-Path $runtimePath "no-session-bus")
  }
  $displayNames = @("DISPLAY", "XAUTHORITY")
  if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable("DISPLAY"))) {
    $displayNames = @("WAYLAND_DISPLAY")
  }
  foreach ($name in $displayNames) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if (-not [string]::IsNullOrWhiteSpace($value)) {
      $environment[$name] = $value
    }
  }

  return $environment
}

function Get-GpAppImageSmokeFailure {
  param(
    [AllowNull()]
    [string]$Output
  )

  if ([string]::IsNullOrWhiteSpace($Output)) {
    return $null
  }

  foreach ($entry in $script:GpAppImageSmokeFailurePatterns) {
    $match = [regex]::Match($Output, $entry.Pattern)
    if ($match.Success) {
      $lineStart = $Output.LastIndexOf("`n", $match.Index) + 1
      $lineEnd = $Output.IndexOf("`n", $match.Index)
      if ($lineEnd -lt 0) {
        $lineEnd = $Output.Length
      }
      return [pscustomobject]@{
        Reason = $entry.Reason
        Line = $Output.Substring($lineStart, $lineEnd - $lineStart).Trim()
      }
    }
  }

  return $null
}

# The smoke process and every process under it (env, the AppImage runtime,
# AppRun, the app), as name prefixes: /proc's comm is cut to 15 characters.
function Get-GpAppImageSmokeProcessNames {
  param(
    [Parameter(Mandatory = $true)]
    [int]$RootProcessId
  )

  $children = @{}
  $names = @{}
  foreach ($line in @(& ps -e -o pid=,ppid=,comm= 2>$null)) {
    $fields = ([string]$line).Trim() -split '\s+', 3
    if ($fields.Count -lt 3) {
      continue
    }
    $processId = [int]$fields[0]
    $parentId = [int]$fields[1]
    $names[$processId] = $fields[2]
    if (-not $children.ContainsKey($parentId)) {
      $children[$parentId] = [System.Collections.Generic.List[int]]::new()
    }
    $children[$parentId].Add($processId) | Out-Null
  }

  $result = [System.Collections.Generic.List[string]]::new()
  $pending = [System.Collections.Generic.Queue[int]]::new()
  $pending.Enqueue($RootProcessId)
  while ($pending.Count -gt 0) {
    $current = $pending.Dequeue()
    if ($names.ContainsKey($current)) {
      $result.Add([string]$names[$current]) | Out-Null
    }
    if ($children.ContainsKey($current)) {
      foreach ($child in $children[$current]) {
        $pending.Enqueue($child)
      }
    }
  }

  return [string[]]@($result.ToArray())
}

# GNUstep alert panels the smoke process has on screen. An uncaught
# exception in a GNUstep app shows a modal "Critical Error" panel and logs
# nothing until it is dismissed, so the app looks healthy from outside.
# Every GNUstep alert panel has the window title " " (one space); the
# panel's WM_CLASS is the process name. GNUstep sets no _NET_WM_PID, so a
# panel from another process with the same name would match: the caller
# passes the panels already on screen before the launch to ignore. Returns
# $null when the check can't run (no X display or no xwininfo).
function Get-GpAppImageSmokeAlertWindows {
  param(
    [AllowNull()]
    [System.Diagnostics.Process]$Process,
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Environment,
    [string[]]$IgnoreWindowIds = @()
  )

  if (-not $Environment.Contains("DISPLAY") -or -not (Get-Command xwininfo -ErrorAction SilentlyContinue)) {
    return $null
  }

  # Without a process, any viewable alert panel counts: used to note the
  # panels already on screen before the launch.
  $processNames = if ($null -ne $Process) { @(Get-GpAppImageSmokeProcessNames -RootProcessId $Process.Id) } else { $null }
  $displayArguments = @("DISPLAY=" + [string]$Environment["DISPLAY"])
  if ($Environment.Contains("XAUTHORITY")) {
    $displayArguments += "XAUTHORITY=" + [string]$Environment["XAUTHORITY"]
  }

  $alerts = [System.Collections.Generic.List[string]]::new()
  foreach ($line in @(& env @displayArguments xwininfo -root -tree 2>$null)) {
    $match = [regex]::Match([string]$line, '^\s*(0x[0-9a-fA-F]+) " ": \("([^"]*)"')
    if (-not $match.Success) {
      continue
    }
    $className = $match.Groups[2].Value
    if ($IgnoreWindowIds -contains $match.Groups[1].Value) {
      continue
    }
    $owned = ($null -eq $processNames)
    foreach ($name in @($processNames)) {
      if ($className.StartsWith($name) -or $name.StartsWith($className)) {
        $owned = $true
        break
      }
    }
    if (-not $owned) {
      continue
    }
    $windowInfo = [string]::Join("`n", @(& env @displayArguments xwininfo -id $match.Groups[1].Value 2>$null))
    if ($windowInfo -match 'Map State:\s*IsViewable') {
      $alerts.Add(("{0} ({1})" -f $match.Groups[1].Value, $className)) | Out-Null
    }
  }

  # The comma keeps an empty list an array: PowerShell would unroll it to
  # $null, which means the check was skipped.
  return ,([string[]]$alerts.ToArray())
}

function Invoke-GpAppImageExternalTool {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [Parameter(Mandatory = $true)]
    [string[]]$ArgumentList,
    [Parameter(Mandatory = $true)]
    [string]$LogPath,
    [hashtable]$Environment = @{}
  )

  Write-GpAppImageLogLine -LogPath $LogPath -Message ("RUN {0} {1}" -f $FilePath, ([string]::Join(" ", $ArgumentList)))
  $global:LASTEXITCODE = 0

  if ($Environment.Count -gt 0) {
    $envArgumentList = [System.Collections.Generic.List[string]]::new()
    foreach ($key in ($Environment.Keys | Sort-Object)) {
      $envArgumentList.Add(("{0}={1}" -f $key, [string]$Environment[$key])) | Out-Null
    }
    $envArgumentList.Add($FilePath) | Out-Null
    foreach ($argument in @($ArgumentList)) {
      $envArgumentList.Add($argument) | Out-Null
    }

    & env @($envArgumentList.ToArray()) 2>&1 | Tee-Object -FilePath $LogPath -Append | Out-Host
  } else {
    & $FilePath @ArgumentList 2>&1 | Tee-Object -FilePath $LogPath -Append | Out-Host
  }

  $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
  if ($exitCode -ne 0) {
    throw "Command failed with exit code $exitCode. See log: $LogPath"
  }
}

function Ensure-GpAppImageTool {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [psobject]$WorkPaths,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  $command = Get-Command appimagetool -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($command) {
    return $command.Source
  }

  $toolPath = Join-Path $Config.AppImageToolRoot $Config.AppImageToolFileName
  if (Test-Path $toolPath) {
    Set-GpUnixExecutable -Path $toolPath
    return $toolPath
  }

  Write-GpAppImageLogLine -LogPath $LogPath -Message ("Bootstrapping appimagetool into {0}" -f $Config.AppImageToolRoot)
  Ensure-GpDirectory -Path $Config.AppImageToolRoot | Out-Null
  Ensure-GpDirectory -Path $WorkPaths.DownloadRoot | Out-Null
  $downloadPath = Join-Path $WorkPaths.DownloadRoot $Config.AppImageToolFileName
  Invoke-WebRequest -Uri $Config.AppImageToolDownloadUrl -OutFile $downloadPath
  Copy-Item -Force $downloadPath $toolPath
  Set-GpUnixExecutable -Path $toolPath
  return $toolPath
}

function Ensure-GpAppImageRuntimeFile {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ToolPath,
    [Parameter(Mandatory = $true)]
    [psobject]$WorkPaths,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  if (-not $ToolPath.EndsWith(".AppImage", [System.StringComparison]::OrdinalIgnoreCase)) {
    return $null
  }

  Ensure-GpDirectory -Path $WorkPaths.DownloadRoot | Out-Null
  $runtimePath = Join-Path $WorkPaths.DownloadRoot "runtime-x86_64"
  if (Test-Path $runtimePath) {
    Set-GpUnixExecutable -Path $runtimePath
    return $runtimePath
  }

  $global:LASTEXITCODE = 0
  $offsetText = & env "APPIMAGE_EXTRACT_AND_RUN=1" $ToolPath "--appimage-offset"
  $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
  if ($exitCode -ne 0) {
    throw "Failed to determine the AppImage runtime offset from tool: $ToolPath"
  }

  $offset = 0L
  if (-not [long]::TryParse(([string]$offsetText).Trim(), [ref]$offset) -or ($offset -lt 1)) {
    throw "AppImage tool did not return a valid runtime offset: $offsetText"
  }

  Write-GpAppImageLogLine -LogPath $LogPath -Message ("Extracting AppImage runtime from {0} to {1}" -f $ToolPath, $runtimePath)
  $buffer = New-Object byte[] 81920
  $remaining = $offset
  $inputStream = $null
  $outputStream = $null

  try {
    $inputStream = [System.IO.File]::OpenRead($ToolPath)
    $outputStream = [System.IO.File]::Create($runtimePath)

    while ($remaining -gt 0) {
      $count = if ($remaining -gt $buffer.Length) { $buffer.Length } else { [int]$remaining }
      $read = $inputStream.Read($buffer, 0, $count)
      if ($read -le 0) {
        throw "Unexpected end of file while extracting AppImage runtime from $ToolPath"
      }
      $outputStream.Write($buffer, 0, $read)
      $remaining -= $read
    }
  } finally {
    if ($null -ne $outputStream) {
      $outputStream.Dispose()
    }
    if ($null -ne $inputStream) {
      $inputStream.Dispose()
    }
  }

  Set-GpUnixExecutable -Path $runtimePath
  return $runtimePath
}

function Get-GpLaunchEnvironmentForAppImage {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context
  )

  $launch = Get-GpLaunchContract -Context $Context
  $environment = [hashtable](Copy-GpValue -Value $launch.Environment)
  if (-not $environment.ContainsKey("GNUSTEP_PATHPREFIX_LIST")) {
    $environment["GNUSTEP_PATHPREFIX_LIST"] = New-GpLaunchEnvironmentEntry -Value "{@runtimeRoot}" -Policy "override"
  }

  Assert-GpAppImageEnvironmentKeys -Environment $environment -Label "AppImage launch"
  return $environment
}

function Convert-GpPackagedDefaultToGnustepLiteral {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Entry
  )

  switch ([string]$Entry.Type) {
    "string" {
      $escaped = ([string]$Entry.Value).Replace('\', '\\').Replace('"', '\"')
      return ('"{0}"' -f $escaped)
    }
    "bool" {
      if ([bool]$Entry.Value) {
        return "YES"
      }
      return "NO"
    }
    "integer" {
      return [string]$Entry.Value
    }
    "number" {
      return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0}", $Entry.Value)
    }
    default {
      throw "Unsupported packaged default type for AppImage AppRun seeding: $($Entry.Type)"
    }
  }
}

function Get-GpAppImageAppDomainDefaults {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context
  )

  $packagedDefaults = Get-GpPackagedDefaults -Manifest $Context.Manifest
  $packageId = [string]$Context.Manifest["package"]["id"]
  $domainName = if ($null -ne $packagedDefaults.AppDomain -and -not [string]::IsNullOrWhiteSpace([string]$packagedDefaults.AppDomain.Domain)) {
    [string]$packagedDefaults.AppDomain.Domain
  } else {
    $packageId
  }

  if ($null -eq $packagedDefaults.AppDomain -and [string]::IsNullOrWhiteSpace([string]$packagedDefaults.DefaultTheme)) {
    return $null
  }

  $entries = [System.Collections.Generic.List[psobject]]::new()
  if (-not [string]::IsNullOrWhiteSpace([string]$packagedDefaults.DefaultTheme)) {
    $themeEntry = [pscustomobject]@{
      Key = "GSTheme"
      Type = "string"
      Value = [string]$packagedDefaults.DefaultTheme
    }
    $entries.Add([pscustomobject]@{
      Key = [string]$themeEntry.Key
      Type = [string]$themeEntry.Type
      Value = $themeEntry.Value
      SerializedValue = Convert-GpPackagedDefaultToGnustepLiteral -Entry $themeEntry
    }) | Out-Null
  }

  $appDomainEntries = if ($null -ne $packagedDefaults.AppDomain) { @($packagedDefaults.AppDomain.Entries) } else { @() }
  foreach ($entry in $appDomainEntries) {
    $entries.Add([pscustomobject]@{
      Key = [string]$entry.Key
      Type = [string]$entry.Type
      Value = $entry.Value
      SerializedValue = Convert-GpPackagedDefaultToGnustepLiteral -Entry $entry
    }) | Out-Null
  }

  return [pscustomobject]@{
    Domain = $domainName
    Entries = @($entries.ToArray())
  }
}

function Assert-GpAppImageEnvironmentKeys {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Environment,
    [Parameter(Mandatory = $true)]
    [string]$Label
  )

  foreach ($key in @($environment.Keys)) {
    if (-not [regex]::IsMatch([string]$key, "^[A-Za-z_][A-Za-z0-9_]*$")) {
      throw "$Label environment key '$key' is not a valid POSIX shell variable name."
    }
  }
}

function Convert-GpAppImageStagePathToShellExpression {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RelativePath
  )

  $normalized = ($RelativePath -replace "\\", "/").Trim()
  if ([string]::IsNullOrWhiteSpace($normalized) -or $normalized -eq ".") {
    return '"${USR}"'
  }

  while ($normalized.StartsWith("./", [System.StringComparison]::Ordinal)) {
    $normalized = $normalized.Substring(2)
  }
  $normalized = $normalized.TrimStart("/")
  return ('"${USR}/' + (Escape-GpShDoubleQuotedLiteral -Value $normalized) + '"')
}

function Convert-GpAppImageValueToShellExpression {
  param(
    [AllowNull()]
    [string]$Value
  )

  if ($null -eq $Value) {
    return '""'
  }

  $replacements = [ordered]@{
    "{@installRoot}" = '${APPDIR}'
    "{@appRoot}" = '${APP_ROOT}'
    "{@runtimeRoot}" = '${RUNTIME_ROOT}'
    "{@metadataRoot}" = '${METADATA_ROOT}'
  }

  $resolved = [string]$Value
  $placeholders = @{}
  $index = 0
  foreach ($token in $replacements.Keys) {
    $placeholder = "__GP_TOKEN_{0}__" -f $index
    $index += 1
    $resolved = $resolved.Replace($token, $placeholder)
    $placeholders[$placeholder] = [string]$replacements[$token]
  }

  $escaped = Escape-GpShDoubleQuotedLiteral -Value $resolved
  foreach ($placeholder in $placeholders.Keys) {
    $escaped = $escaped.Replace($placeholder, [string]$placeholders[$placeholder])
  }

  return ('"' + $escaped + '"')
}

function Get-GpAppImageRuntimeNoticeEntries {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [string]$AppDirRoot
  )

  $entries = [System.Collections.Generic.List[psobject]]::new()
  foreach ($entry in @(Get-GpComplianceEntries -Manifest $Context.Manifest)) {
    $stageRelativePath = if ($entry.ContainsKey("stageRelativePath") -and -not [string]::IsNullOrWhiteSpace([string]$entry["stageRelativePath"])) {
      [string]$entry["stageRelativePath"]
    } else {
      $null
    }

    $installedPath = $null
    if (-not [string]::IsNullOrWhiteSpace($stageRelativePath)) {
      $installedPath = Resolve-GpPathRelativeToBase -BasePath (Join-Path $AppDirRoot "usr") -Path $stageRelativePath
      if (-not (Test-Path $installedPath)) {
        throw "Configured compliance.runtimeNotices entry '$($entry["name"])' references a missing bundled file: $installedPath"
      }
    }

    $entries.Add([pscustomobject]@{
      Name = [string]$entry["name"]
      Version = $(if ($entry.ContainsKey("version")) { [string]$entry["version"] } else { $null })
      License = $(if ($entry.ContainsKey("license")) { [string]$entry["license"] } else { $null })
      Source = $(if ($entry.ContainsKey("source")) { [string]$entry["source"] } else { $null })
      Homepage = $(if ($entry.ContainsKey("homepage")) { [string]$entry["homepage"] } else { $null })
      StageRelativePath = $stageRelativePath
      InstalledPath = $installedPath
    }) | Out-Null
  }

  return @($entries.ToArray())
}

function Write-GpAppImageNoticeReport {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [string]$AppDirRoot,
    [Parameter(Mandatory = $true)]
    [string]$LogPath,
    [object[]]$AdditionalEntries = @()
  )

  $package = $Context.Manifest["package"]
  $entries = @(Get-GpAppImageRuntimeNoticeEntries -Context $Context -AppDirRoot $AppDirRoot) + @($AdditionalEntries)
  $metadataRoot = Ensure-GpDirectory -Path (Join-Path (Join-Path $AppDirRoot "usr") ($Config.MetadataRootRelative -replace "/", [System.IO.Path]::DirectorySeparatorChar))
  $reportPath = Join-Path $metadataRoot "THIRD-PARTY-NOTICES.txt"
  $lines = [System.Collections.Generic.List[string]]::new()

  $lines.Add(("Package: {0}" -f [string]$package["name"])) | Out-Null
  $lines.Add(("Version: {0}" -f [string]$package["version"])) | Out-Null
  $lines.Add(("Manufacturer: {0}" -f [string]$package["manufacturer"])) | Out-Null
  $lines.Add("") | Out-Null
  $lines.Add(("Runtime notice entries: {0}" -f $entries.Count)) | Out-Null

  foreach ($entry in $entries) {
    $lines.Add("") | Out-Null
    $lines.Add(("[{0}]" -f $entry.Name)) | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($entry.Version)) {
      $lines.Add(("Version: {0}" -f $entry.Version)) | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($entry.License)) {
      $lines.Add(("License: {0}" -f $entry.License)) | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($entry.Source)) {
      $lines.Add(("Source: {0}" -f $entry.Source)) | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($entry.Homepage)) {
      $lines.Add(("Homepage: {0}" -f $entry.Homepage)) | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($entry.StageRelativePath)) {
      $lines.Add(("Bundled notice path: {0}" -f $entry.StageRelativePath)) | Out-Null
    }
  }

  Set-Content -Path $reportPath -Value $lines -Encoding ascii
  Write-GpAppImageLogLine -LogPath $LogPath -Message ("Generated notice report: {0}" -f $reportPath)

  return [pscustomobject]@{
    ReportPath = $reportPath
    Entries = $entries
  }
}

function Write-GpAppImageMimePackage {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [string]$AppDirRoot,
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [psobject[]]$MimeEntries,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  $generatedEntries = @($MimeEntries | Where-Object { $_.Generated })
  if ($generatedEntries.Count -eq 0) {
    return $null
  }

  $mimeDir = Ensure-GpDirectory -Path (Join-Path $AppDirRoot "usr/share/mime/packages")
  $mimePath = Join-Path $mimeDir ((Convert-GpAppImageIdentifierFragment -Value $Config.PackageId) + ".xml")
  $lines = [System.Collections.Generic.List[string]]::new()
  $lines.Add('<?xml version="1.0" encoding="UTF-8"?>') | Out-Null
  $lines.Add("<mime-info xmlns='http://www.freedesktop.org/standards/shared-mime-info'>") | Out-Null

  foreach ($entry in $generatedEntries) {
    $lines.Add(("  <mime-type type='{0}'>" -f $entry.MimeType)) | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($entry.Description)) {
      $lines.Add(("    <comment>{0}</comment>" -f ([System.Security.SecurityElement]::Escape($entry.Description)))) | Out-Null
    }
    $lines.Add(("    <glob pattern='{0}'/>" -f ([System.Security.SecurityElement]::Escape($entry.GlobPattern)))) | Out-Null
    $lines.Add("  </mime-type>") | Out-Null
  }

  $lines.Add("</mime-info>") | Out-Null
  Set-Content -Path $mimePath -Value $lines -Encoding ascii
  Write-GpAppImageLogLine -LogPath $LogPath -Message ("Generated MIME package: {0}" -f $mimePath)
  return $mimePath
}

function Write-GpAppImageDesktopEntry {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [string]$AppDirRoot,
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [psobject[]]$MimeEntries,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  $integrations = $Context.Manifest["integrations"]
  $desktopDir = Ensure-GpDirectory -Path (Join-Path $AppDirRoot "usr/share/applications")
  $desktopPath = Join-Path $desktopDir $Config.DesktopEntryName
  $rootDesktopPath = Join-Path $AppDirRoot $Config.DesktopEntryName
  $mimeTypes = @(Get-GpAppImageDesktopMimeTypes -MimeEntries $MimeEntries)
  $categories = [string[]]@($integrations["categories"])
  $comment = if (-not [string]::IsNullOrWhiteSpace($Config.Summary)) { $Config.Summary } else { $Config.Description }
  $execValue = if ($mimeTypes.Count -gt 0) { "AppRun %F" } else { "AppRun" }
  $lines = [System.Collections.Generic.List[string]]::new()

  $lines.Add("[Desktop Entry]") | Out-Null
  $lines.Add("Type=Application") | Out-Null
  $lines.Add(("Name={0}" -f $Config.DisplayName)) | Out-Null
  $lines.Add(("Exec={0}" -f $execValue)) | Out-Null
  $lines.Add(("Icon={0}" -f $Config.IconName)) | Out-Null
  $lines.Add("Terminal=false") | Out-Null
  if (-not [string]::IsNullOrWhiteSpace($comment)) {
    $lines.Add(("Comment={0}" -f $comment)) | Out-Null
  }
  if (-not [string]::IsNullOrWhiteSpace($Config.Homepage)) {
    $lines.Add(("X-AppImage-Homepage={0}" -f $Config.Homepage)) | Out-Null
  }
  $lines.Add(("X-AppImage-Name={0}" -f $Config.PackageName)) | Out-Null
  $lines.Add(("X-AppImage-Version={0}" -f $Config.Version)) | Out-Null

  if ($categories.Count -gt 0) {
    $lines.Add(("Categories={0};" -f ([string]::Join(";", $categories)))) | Out-Null
  }
  if ($mimeTypes.Count -gt 0) {
    $lines.Add(("MimeType={0};" -f ([string]::Join(";", $mimeTypes)))) | Out-Null
  }

  Set-Content -Path $desktopPath -Value $lines -Encoding ascii
  Copy-Item -Force $desktopPath $rootDesktopPath
  Write-GpAppImageLogLine -LogPath $LogPath -Message ("Generated desktop entry: {0}" -f $desktopPath)

  return [pscustomobject]@{
    DesktopPath = $desktopPath
    RootDesktopPath = $rootDesktopPath
    MimeTypes = [string[]]$mimeTypes
  }
}

function Copy-GpAppImageIconAssets {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [string]$AppDirRoot,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  $sourceIconPath = Resolve-GpStagePath -Context $Context -RelativePath $Config.IconRelativePath
  if (-not (Test-Path $sourceIconPath)) {
    throw "Configured AppImage icon does not exist in the staged payload: $sourceIconPath"
  }

  $iconFileName = "{0}.{1}" -f $Config.IconName, $Config.IconExtension
  $shareIconDir = Ensure-GpDirectory -Path (Join-Path $AppDirRoot "usr/share/icons/hicolor/256x256/apps")
  $shareIconPath = Join-Path $shareIconDir $iconFileName
  $rootIconPath = Join-Path $AppDirRoot $iconFileName
  $dirIconPath = Join-Path $AppDirRoot ".DirIcon"

  Copy-Item -Force $sourceIconPath $shareIconPath
  Copy-Item -Force $sourceIconPath $rootIconPath
  Copy-Item -Force $sourceIconPath $dirIconPath

  Write-GpAppImageLogLine -LogPath $LogPath -Message ("Copied icon assets: {0}" -f $shareIconPath)
  return [pscustomobject]@{
    SourceIconPath = $sourceIconPath
    ShareIconPath = $shareIconPath
    RootIconPath = $rootIconPath
    DirIconPath = $dirIconPath
  }
}

function Get-GpAppImageGnustepConfigLayout {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Config
  )

  # Stage-relative directories (under usr/ in the AppDir). The second one adds
  # GlobalDefaults.plist with the default theme; AppRun picks it on the
  # desktops the manifest names.
  $runtimeRoot = ($Config.RuntimeRootRelative -replace "\\", "/").Trim("/")
  $baseRoot = if ([string]::IsNullOrWhiteSpace($runtimeRoot) -or $runtimeRoot -eq ".") { "etc" } else { "$runtimeRoot/etc" }
  return [pscustomobject]@{
    PlainDirRelative = "$baseRoot/GNUstep"
    ThemedDirRelative = "$baseRoot/GNUstep-default-theme"
  }
}

function Get-GpAppImageGnustepConfigText {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigDirectory,
    [Parameter(Mandatory = $true)]
    [string]$SystemRoot,
    [string]$UserLibraryRelative
  )

  # gnustep-base resolves a path that starts with ./ or ../ against the
  # directory of the config file, so the file works wherever the AppImage is
  # mounted. SYSTEM, LOCAL and NETWORK all point at the bundled tree: nothing
  # from a GNUstep installed on the host gets loaded.
  $relative = [System.IO.Path]::GetRelativePath($ConfigDirectory, $SystemRoot) -replace "\\", "/"
  if (-not $relative.StartsWith("../", [System.StringComparison]::Ordinal) -and $relative -ne "..") {
    $relative = "./" + $relative
  }

  $lines = [System.Collections.Generic.List[string]]::new()
  $lines.Add("# Generated by gnustep-packager. Paths are relative to this file.") | Out-Null
  $lines.Add("GNUSTEP_USER_CONFIG_FILE=") | Out-Null
  $lines.Add("GNUSTEP_USER_DEFAULTS_DIR=GNUstep/Defaults") | Out-Null
  if (-not [string]::IsNullOrWhiteSpace($UserLibraryRelative)) {
    # Relative to the user's home, like GNUstep's other user directories. The defaults stay in
    # GNUSTEP_USER_DEFAULTS_DIR, so the user's settings are unaffected.
    $lines.Add("GNUSTEP_USER_DIR_LIBRARY=$UserLibraryRelative") | Out-Null
  }
  $lines.Add("GNUSTEP_MAKEFILES=$relative/Library/Makefiles") | Out-Null
  foreach ($domain in @("SYSTEM", "NETWORK", "LOCAL")) {
    $lines.Add("GNUSTEP_${domain}_APPS=$relative/Applications") | Out-Null
    $lines.Add("GNUSTEP_${domain}_ADMIN_APPS=$relative/Applications/Admin") | Out-Null
    $lines.Add("GNUSTEP_${domain}_WEB_APPS=$relative/Library/WebApplications") | Out-Null
    $lines.Add("GNUSTEP_${domain}_TOOLS=$relative/Tools") | Out-Null
    $lines.Add("GNUSTEP_${domain}_ADMIN_TOOLS=$relative/Tools/Admin") | Out-Null
    $lines.Add("GNUSTEP_${domain}_LIBRARY=$relative/Library") | Out-Null
    $lines.Add("GNUSTEP_${domain}_HEADERS=$relative/Library/Headers") | Out-Null
    $lines.Add("GNUSTEP_${domain}_LIBRARIES=$relative/Library/Libraries") | Out-Null
    $lines.Add("GNUSTEP_${domain}_DOC=$relative/Library/Documentation") | Out-Null
    $lines.Add("GNUSTEP_${domain}_DOC_MAN=$relative/Library/Documentation/man") | Out-Null
    $lines.Add("GNUSTEP_${domain}_DOC_INFO=$relative/Library/Documentation/info") | Out-Null
  }
  return ([string]::Join("`n", $lines) + "`n")
}

function Write-GpAppImageGlobalDefaults {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Directory,
    [Parameter(Mandatory = $true)]
    [object[]]$Entries
  )

  # GlobalDefaults.plist next to GNUstep.conf ranks below the user's own
  # defaults (NSGlobalDomain and the app's domain), so a user's choice wins.
  $pairs = @(
    foreach ($entry in @($Entries | Sort-Object Key)) {
      $keyLiteral = Convert-GpPackagedDefaultToGnustepLiteral -Entry ([pscustomobject]@{ Type = "string"; Value = $entry.Key })
      "  {0} = {1};" -f $keyLiteral, (Convert-GpPackagedDefaultToGnustepLiteral -Entry $entry)
    }
  )
  $path = Join-Path $Directory "GlobalDefaults.plist"
  Set-Content -Path $path -Value ("{`n" + [string]::Join("`n", $pairs) + "`n}`n") -Encoding ascii -NoNewline
  return $path
}

function Write-GpAppImageGnustepConfig {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [string]$AppDirRoot,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  $usrRoot = Join-Path $AppDirRoot "usr"
  $runtimeSystemLibrary = Join-Path (Join-Path $usrRoot ($Config.RuntimeRootRelative -replace "/", [System.IO.Path]::DirectorySeparatorChar)) (Join-Path "System" "Library")
  if (-not $Config.GnustepConfig.Enabled) {
    if (Test-Path $runtimeSystemLibrary) {
      Write-GpAppImageLogLine -LogPath $LogPath -Message ("WARNING: the staged runtime has {0} but backends.appimage.gnustepConfig.systemRoot is not set. The bundled gnustep-base will look for its backend, tools and themes where it was built (for example /usr/GNUstep), so the AppImage only starts on hosts with GNUstep installed there." -f $runtimeSystemLibrary)
    }
    return $null
  }

  $systemRoot = [System.IO.Path]::GetFullPath((Join-Path $usrRoot ($Config.GnustepConfig.SystemRootRelative -replace "/", [System.IO.Path]::DirectorySeparatorChar)))
  if (-not (Test-Path (Join-Path $systemRoot "Library"))) {
    throw "backends.appimage.gnustepConfig.systemRoot '$($Config.GnustepConfig.SystemRootRelative)' has no Library directory in the AppDir ($systemRoot)."
  }

  $layout = Get-GpAppImageGnustepConfigLayout -Config $Config
  $writtenPaths = [System.Collections.Generic.List[string]]::new()
  $plainDir = Ensure-GpDirectory -Path (Join-Path $usrRoot ($layout.PlainDirRelative -replace "/", [System.IO.Path]::DirectorySeparatorChar))
  $plainPath = Join-Path $plainDir "GNUstep.conf"
  Set-Content -Path $plainPath -Value (Get-GpAppImageGnustepConfigText -ConfigDirectory $plainDir -SystemRoot $systemRoot -UserLibraryRelative $Config.GnustepConfig.UserLibraryRelative) -Encoding ascii -NoNewline
  $writtenPaths.Add($plainPath) | Out-Null
  $globalDefaults = @($Config.GnustepConfig.GlobalDefaults)
  if ($globalDefaults.Count -gt 0) {
    $writtenPaths.Add((Write-GpAppImageGlobalDefaults -Directory $plainDir -Entries $globalDefaults)) | Out-Null
  }
  Write-GpAppImageLogLine -LogPath $LogPath -Message ("Generated GNUstep.conf: {0}" -f $plainPath)

  $themedPath = $null
  $theme = $Config.GnustepConfig.DefaultTheme
  if ($null -ne $theme) {
    $themeBundle = Join-Path (Join-Path (Join-Path $systemRoot "Library") "Themes") ($theme.Name + ".theme")
    if (-not (Test-Path $themeBundle)) {
      throw "backends.appimage.gnustepConfig.defaultTheme '$($theme.Name)' is not bundled: expected $themeBundle."
    }
    $themedDir = Ensure-GpDirectory -Path (Join-Path $usrRoot ($layout.ThemedDirRelative -replace "/", [System.IO.Path]::DirectorySeparatorChar))
    $themedPath = Join-Path $themedDir "GNUstep.conf"
    Set-Content -Path $themedPath -Value (Get-GpAppImageGnustepConfigText -ConfigDirectory $themedDir -SystemRoot $systemRoot -UserLibraryRelative $Config.GnustepConfig.UserLibraryRelative) -Encoding ascii -NoNewline
    $writtenPaths.Add($themedPath) | Out-Null
    # The theme's own defaults (for example its window decorations) apply only with it, over the
    # global ones; GSTheme is the theme's name.
    $themeKeys = @(@($theme.Defaults) | ForEach-Object { $_.Key }) + @("GSTheme")
    $themedDefaults = @($globalDefaults | Where-Object { $themeKeys -notcontains $_.Key }) + @($theme.Defaults | Where-Object { $_.Key -ne "GSTheme" }) + @([pscustomobject]@{ Key = "GSTheme"; Type = "string"; Value = $theme.Name })
    $writtenPaths.Add((Write-GpAppImageGlobalDefaults -Directory $themedDir -Entries $themedDefaults)) | Out-Null
    Write-GpAppImageLogLine -LogPath $LogPath -Message ("Generated GNUstep.conf with default theme {0}: {1}" -f $theme.Name, $themedPath)
  }

  # gnustep-base ignores a config file that anyone but its owner can write.
  if (-not $IsWindows) {
    foreach ($path in $writtenPaths) {
      & chmod 0644 $path
    }
  }

  return [pscustomobject]@{
    PlainConfigPath = $plainPath
    ThemedConfigPath = $themedPath
  }
}

function Write-GpAppImageBundledFonts {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [string]$AppDirRoot,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  $fonts = @($Config.BundledFonts)
  if ($fonts.Count -eq 0) {
    return @()
  }

  # Fonts go under <runtimeRoot>/share/fonts, the fontconfig file that adds them under
  # <runtimeRoot>/etc/fonts, where AppRun points FONTCONFIG_FILE.
  $usrRoot = Join-Path $AppDirRoot "usr"
  $runtimeRoot = Join-Path $usrRoot ($Config.RuntimeRootRelative -replace "/", [System.IO.Path]::DirectorySeparatorChar)
  $fontConfigDir = Join-Path (Join-Path $runtimeRoot "etc") "fonts"
  $fontConfigPath = Join-Path $fontConfigDir "fonts.conf"
  if (Test-Path $fontConfigPath) {
    throw "backends.appimage.fonts.bundle needs to write $fontConfigPath, but the staged runtime already has one."
  }
  $fontsRoot = Ensure-GpDirectory -Path (Join-Path (Join-Path $runtimeRoot "share") "fonts")
  $metadataRelative = ($Config.MetadataRootRelative -replace "\\", "/").Trim("/")
  $licenseDirRelative = if ([string]::IsNullOrWhiteSpace($metadataRelative) -or $metadataRelative -eq ".") { "licenses/fonts" } else { "$metadataRelative/licenses/fonts" }
  $licenseDir = Ensure-GpDirectory -Path (Join-Path $usrRoot ($licenseDirRelative -replace "/", [System.IO.Path]::DirectorySeparatorChar))

  $notices = [System.Collections.Generic.List[psobject]]::new()
  foreach ($font in $fonts) {
    if (@($font.Files).Count -eq 0) {
      throw "backends.appimage.fonts.bundle '$($font.Name)' lists no files."
    }
    $fontDir = Ensure-GpDirectory -Path (Join-Path $fontsRoot $font.DirectoryName)
    foreach ($file in @($font.Files)) {
      if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "backends.appimage.fonts.bundle '$($font.Name)': font file not found: $file"
      }
      Copy-Item -LiteralPath $file -Destination $fontDir -Force
    }
    if (-not (Test-Path -LiteralPath $font.LicenseFile -PathType Leaf)) {
      throw "backends.appimage.fonts.bundle '$($font.Name)': license file not found: $($font.LicenseFile)"
    }
    $licenseName = $font.DirectoryName + ".txt"
    Copy-Item -LiteralPath $font.LicenseFile -Destination (Join-Path $licenseDir $licenseName) -Force
    Write-GpAppImageLogLine -LogPath $LogPath -Message ("Bundled font {0}: {1} file(s) in {2}" -f $font.Name, @($font.Files).Count, $fontDir)

    $notices.Add([pscustomobject]@{
      Name = ("{0} (font)" -f $font.Name)
      Version = $null
      License = $font.License
      Source = "Font bundled for hosts that lack it"
      Homepage = $font.Homepage
      StageRelativePath = "$licenseDirRelative/$licenseName"
      InstalledPath = Join-Path $licenseDir $licenseName
    }) | Out-Null
  }

  # The host's own configuration comes first, so its fonts, aliases and preferences still decide
  # what a family name matches; the bundled fonts only join the set. That way an app whose
  # toolkit falls back to a fixed family (gnustep-back to DejaVu Sans) still finds it on hosts
  # without it, such as Fedora, and changes nothing on hosts that have it. The directory is
  # relative to this file, so it works wherever the AppImage is mounted.
  Ensure-GpDirectory -Path $fontConfigDir | Out-Null
  $relativeFontsRoot = [System.IO.Path]::GetRelativePath($fontConfigDir, $fontsRoot) -replace "\\", "/"
  $configText = @(
    '<?xml version="1.0"?>'
    '<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">'
    '<!-- Generated by gnustep-packager: the host configuration, then the bundled fonts. -->'
    '<fontconfig>'
    '  <include ignore_missing="yes">/etc/fonts/fonts.conf</include>'
    ('  <dir prefix="relative">{0}</dir>' -f $relativeFontsRoot)
    '  <cachedir prefix="xdg">fontconfig</cachedir>'
    '</fontconfig>'
  )
  Set-Content -Path $fontConfigPath -Value $configText -Encoding ascii
  Write-GpAppImageLogLine -LogPath $LogPath -Message ("Generated fonts.conf: {0}" -f $fontConfigPath)

  return @($notices.ToArray())
}

function Write-GpAppImageAppRun {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [string]$AppDirRoot,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  $launch = Get-GpLaunchContract -Context $Context
  $environment = Get-GpLaunchEnvironmentForAppImage -Context $Context
  $appDefaults = Get-GpAppImageAppDomainDefaults -Context $Context
  $appRunPath = Join-Path $AppDirRoot "AppRun"
  $lines = [System.Collections.Generic.List[string]]::new()

  $lines.Add("#!/bin/sh") | Out-Null
  $lines.Add("set -eu") | Out-Null
  $lines.Add('APPDIR="${APPDIR:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)}"') | Out-Null
  $lines.Add('USR="${APPDIR}/usr"') | Out-Null
  $lines.Add(("APP_ROOT={0}" -f (Convert-GpAppImageStagePathToShellExpression -RelativePath $Config.AppRootRelative))) | Out-Null
  $lines.Add(("RUNTIME_ROOT={0}" -f (Convert-GpAppImageStagePathToShellExpression -RelativePath $Config.RuntimeRootRelative))) | Out-Null
  $lines.Add(("METADATA_ROOT={0}" -f (Convert-GpAppImageStagePathToShellExpression -RelativePath $Config.MetadataRootRelative))) | Out-Null
  $lines.Add(("ENTRY_PATH={0}" -f (Convert-GpAppImageStagePathToShellExpression -RelativePath $launch.EntryRelativePath))) | Out-Null
  $lines.Add(("WORKING_DIRECTORY={0}" -f (Convert-GpAppImageStagePathToShellExpression -RelativePath $launch.WorkingDirectory))) | Out-Null
  $lines.Add('if [ -d "$WORKING_DIRECTORY" ]; then') | Out-Null
  $lines.Add('  cd "$WORKING_DIRECTORY"') | Out-Null
  $lines.Add("fi") | Out-Null
  $lines.Add('if [ -f "$RUNTIME_ROOT/etc/fonts/fonts.conf" ] && [ -z "${FONTCONFIG_FILE:-}" ]; then') | Out-Null
  $lines.Add('  export FONTCONFIG_FILE="$RUNTIME_ROOT/etc/fonts/fonts.conf"') | Out-Null
  if (@($Config.BundledFonts).Count -gt 0) {
    # The generated fonts.conf includes the host's /etc/fonts/fonts.conf, whose relative
    # <include>conf.d</include> fontconfig resolves against FONTCONFIG_PATH and then its
    # compiled-in directory. Name the host's directory, so the host's aliases and rendering
    # settings load whatever prefix the bundled libfontconfig was built with.
    $lines.Add('  export FONTCONFIG_PATH="/etc/fonts"') | Out-Null
  } else {
    $lines.Add('  export FONTCONFIG_PATH="$RUNTIME_ROOT/etc/fonts"') | Out-Null
  }
  $lines.Add("fi") | Out-Null

  if ($Config.GnustepConfig.Enabled) {
    # Point gnustep-base at the bundled GNUstep.conf; without it, it reads the
    # config it was built with and loads (or misses) the host's GNUstep. A
    # GNUSTEP_CONFIG_FILE in the launch environment below still wins.
    $layout = Get-GpAppImageGnustepConfigLayout -Config $Config
    $plainExpression = Convert-GpAppImageStagePathToShellExpression -RelativePath ($layout.PlainDirRelative + "/GNUstep.conf")
    $lines.Add(("GP_GNUSTEP_CONFIG_FILE={0}" -f $plainExpression)) | Out-Null
    $theme = $Config.GnustepConfig.DefaultTheme
    if ($null -ne $theme) {
      $themedExpression = Convert-GpAppImageStagePathToShellExpression -RelativePath ($layout.ThemedDirRelative + "/GNUstep.conf")
      if (@($theme.Desktops).Count -eq 0) {
        $lines.Add(("GP_GNUSTEP_CONFIG_FILE={0}" -f $themedExpression)) | Out-Null
      } else {
        $patterns = @(
          foreach ($desktop in @($theme.Desktops)) {
            if (-not [regex]::IsMatch($desktop, "^[A-Za-z0-9_.-]+$")) {
              throw "backends.appimage.gnustepConfig.defaultTheme.desktops entry '$desktop' is not a desktop name."
            }
            "*:$($desktop):*"
          }
        )
        $lines.Add('case ":${XDG_CURRENT_DESKTOP:-}:" in') | Out-Null
        $lines.Add(("  {0}) GP_GNUSTEP_CONFIG_FILE={1} ;;" -f ([string]::Join("|", $patterns)), $themedExpression)) | Out-Null
        $lines.Add('esac') | Out-Null
      }
    }
    $lines.Add('export GNUSTEP_CONFIG_FILE="$GP_GNUSTEP_CONFIG_FILE"') | Out-Null
  }

  $pathPrependItems = [string[]]@($launch.PathPrepend)
  [array]::Reverse($pathPrependItems)
  foreach ($item in @($pathPrependItems)) {
    if (-not [string]::IsNullOrWhiteSpace($item)) {
      $pathExpression = (Convert-GpAppImageStagePathToShellExpression -RelativePath $item).Trim('"')
      $lines.Add(('PATH="' + $pathExpression + ':${PATH:-}"')) | Out-Null
    }
  }
  $lines.Add('export PATH') | Out-Null

  foreach ($key in ($environment.Keys | Sort-Object)) {
    $entry = $environment[$key]
    $value = if (($entry -is [System.Collections.IDictionary]) -and $entry.Contains("value")) { [string]$entry["value"] } else { [string]$entry }
    $policy = if (($entry -is [System.Collections.IDictionary]) -and $entry.Contains("policy") -and -not [string]::IsNullOrWhiteSpace([string]$entry["policy"])) {
      [string]$entry["policy"]
    } else {
      "override"
    }
    $valueExpression = Convert-GpAppImageValueToShellExpression -Value $value

    switch ($policy) {
      "override" {
        $lines.Add(("export {0}={1}" -f $key, $valueExpression)) | Out-Null
      }

      "ifUnset" {
        $lines.Add(('if [ -z "${' + $key + '+x}" ]; then')) | Out-Null
        $lines.Add(("  export {0}={1}" -f $key, $valueExpression)) | Out-Null
        $lines.Add("fi") | Out-Null
      }

      "prepend" {
        # The packaged value goes first; the host's value (or hostDefault
        # when the host has none) follows, so search paths such as
        # XDG_DATA_DIRS keep the desktop's entries.
        # GP_HOST_<key> keeps the host's value from the first launch, so an
        # app relaunched from inside the AppImage (after an update, from a
        # different mount) doesn't stack packaged entries.
        $packagedPart = $valueExpression.Substring(1, $valueExpression.Length - 2)
        $hostKey = "GP_HOST_" + $key
        $lines.Add(('if [ -z "${' + $hostKey + '+x}" ]; then')) | Out-Null
        $lines.Add(('  export ' + $hostKey + '="${' + $key + ':-}"')) | Out-Null
        $lines.Add('fi') | Out-Null
        $hostDefault = if (($entry -is [System.Collections.IDictionary]) -and $entry.Contains("hostDefault")) { [string]$entry["hostDefault"] } else { "" }
        if ([string]::IsNullOrEmpty($hostDefault)) {
          $lines.Add(('export ' + $key + '="' + $packagedPart + '${' + $hostKey + ':+:${' + $hostKey + '}}"')) | Out-Null
        } else {
          $hostDefaultPart = Escape-GpShDoubleQuotedLiteral -Value $hostDefault
          $lines.Add(('export ' + $key + '="' + $packagedPart + ':${' + $hostKey + ':-' + $hostDefaultPart + '}"')) | Out-Null
        }
      }

      default {
        throw "Unsupported AppImage launch environment policy '$policy' for key '$key'."
      }
    }
  }

  if ($null -ne $appDefaults -and @($appDefaults.Entries).Count -gt 0) {
    $lines.Add('APP_DEFAULTS_TOOL=""') | Out-Null
    $lines.Add('if [ -x "$RUNTIME_ROOT/bin/defaults" ]; then') | Out-Null
    $lines.Add('  APP_DEFAULTS_TOOL="$RUNTIME_ROOT/bin/defaults"') | Out-Null
    $lines.Add('elif [ -x "$RUNTIME_ROOT/bin/defaults.exe" ]; then') | Out-Null
    $lines.Add('  APP_DEFAULTS_TOOL="$RUNTIME_ROOT/bin/defaults.exe"') | Out-Null
    $lines.Add('fi') | Out-Null
    $lines.Add('if [ -z "$APP_DEFAULTS_TOOL" ]; then') | Out-Null
    $lines.Add('  printf ''AppRun requires runtime/bin/defaults or runtime/bin/defaults.exe for packaged app defaults.\n'' >&2') | Out-Null
    $lines.Add('  exit 41') | Out-Null
    $lines.Add('fi') | Out-Null

    foreach ($entry in @($appDefaults.Entries)) {
      $keyLiteral = Convert-GpAppImageValueToShellExpression -Value $entry.Key
      $valueLiteral = Convert-GpAppImageValueToShellExpression -Value $entry.SerializedValue
      $domainLiteral = Convert-GpAppImageValueToShellExpression -Value $appDefaults.Domain

      $lines.Add(('if ! "$APP_DEFAULTS_TOOL" read ' + $domainLiteral + ' ' + $keyLiteral + ' >/dev/null 2>&1; then')) | Out-Null
      $lines.Add(('  "$APP_DEFAULTS_TOOL" write ' + $domainLiteral + ' ' + $keyLiteral + ' ' + $valueLiteral + ' >/dev/null 2>&1')) | Out-Null
      $lines.Add('fi') | Out-Null
    }
  }

  if (@($launch.Arguments).Count -gt 0) {
    $baseArguments = @(
      foreach ($argument in @($launch.Arguments)) {
        Convert-GpAppImageValueToShellExpression -Value ([string]$argument)
      }
    )
    $lines.Add(('set -- ' + ([string]::Join(" ", $baseArguments)) + ' "$@"')) | Out-Null
  }

  $lines.Add('exec "$ENTRY_PATH" "$@"') | Out-Null

  Set-Content -Path $appRunPath -Value $lines -Encoding ascii
  Set-GpUnixExecutable -Path $appRunPath
  Write-GpAppImageLogLine -LogPath $LogPath -Message ("Generated AppRun: {0}" -f $appRunPath)
  return $appRunPath
}

function Assert-GpAppImageAppDefaultsPrerequisites {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [string]$AppDirRoot
  )

  $appDefaults = Get-GpAppImageAppDomainDefaults -Context $Context
  if ($null -eq $appDefaults -or @($appDefaults.Entries).Count -eq 0) {
    return
  }

  foreach ($candidate in @(
    (Join-Path $AppDirRoot "usr/runtime/bin/defaults"),
    (Join-Path $AppDirRoot "usr/runtime/bin/defaults.exe")
  )) {
    if (Test-Path $candidate) {
      return
    }
  }

  throw "packagedDefaults.appDomain or packagedDefaults.defaultTheme requires a bundled defaults tool at usr/runtime/bin/defaults or usr/runtime/bin/defaults.exe inside the AppDir."
}

function Prepare-GpAppDir {
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

  Reset-GpAppImageDirectory -Path $WorkPaths.AppDirRoot
  $usrRoot = Ensure-GpDirectory -Path (Join-Path $WorkPaths.AppDirRoot "usr")

  foreach ($relativeRoot in @($Config.AppRootRelative, $Config.RuntimeRootRelative, $Config.MetadataRootRelative)) {
    if (-not [string]::IsNullOrWhiteSpace($relativeRoot)) {
      $destination = Copy-GpRelativeStagePathToAppDir -StageRoot $Config.StageRoot -RelativePath $relativeRoot -UsrRoot $usrRoot
      if ($destination) {
        Write-GpAppImageLogLine -LogPath $LogPath -Message ("Copied staged root {0} -> {1}" -f $relativeRoot, $destination)
      }
    }
  }

  Assert-GpAppImageAppDefaultsPrerequisites -Context $Context -AppDirRoot $WorkPaths.AppDirRoot

  $mimeEntries = @(Get-GpAppImageMimeEntries -Context $Context -Config $Config)
  $mimePackagePath = Write-GpAppImageMimePackage -Config $Config -AppDirRoot $WorkPaths.AppDirRoot -MimeEntries $mimeEntries -LogPath $LogPath
  $desktopEntry = Write-GpAppImageDesktopEntry -Context $Context -Config $Config -AppDirRoot $WorkPaths.AppDirRoot -MimeEntries $mimeEntries -LogPath $LogPath
  $iconAssets = Copy-GpAppImageIconAssets -Context $Context -Config $Config -AppDirRoot $WorkPaths.AppDirRoot -LogPath $LogPath
  $gnustepConfig = Write-GpAppImageGnustepConfig -Config $Config -AppDirRoot $WorkPaths.AppDirRoot -LogPath $LogPath
  $fontNotices = @(Write-GpAppImageBundledFonts -Config $Config -AppDirRoot $WorkPaths.AppDirRoot -LogPath $LogPath)
  $appRunPath = Write-GpAppImageAppRun -Context $Context -Config $Config -AppDirRoot $WorkPaths.AppDirRoot -LogPath $LogPath
  $noticeReport = Write-GpAppImageNoticeReport -Context $Context -Config $Config -AppDirRoot $WorkPaths.AppDirRoot -LogPath $LogPath -AdditionalEntries $fontNotices
  $metadataRoot = Ensure-GpDirectory -Path (Join-Path (Join-Path $WorkPaths.AppDirRoot "usr") ($Config.MetadataRootRelative -replace "/", [System.IO.Path]::DirectorySeparatorChar))
  $updateRuntimeConfigPath = Write-GpUpdateRuntimeConfig -Context $Context -Backend "appimage" -MetadataRoot $metadataRoot
  if (-not [string]::IsNullOrWhiteSpace($updateRuntimeConfigPath)) {
    Write-GpAppImageLogLine -LogPath $LogPath -Message ("Generated updater runtime config: {0}" -f $updateRuntimeConfigPath)
  }
  $packageContract = Invoke-GpPackageContractAssertions -Context $Context -Scope "package" -Backend "appimage" -RootPath $WorkPaths.AppDirRoot
  foreach ($line in @($packageContract.Lines)) {
    Write-GpAppImageLogLine -LogPath $LogPath -Message ("Package contract: {0}" -f $line)
  }
  if ($packageContract.HasIssues) {
    throw "AppImage package contract validation failed. See $LogPath."
  }

  return [pscustomobject]@{
    AppDirRoot = $WorkPaths.AppDirRoot
    AppRunPath = $appRunPath
    GnustepConfigPath = $(if ($gnustepConfig) { $gnustepConfig.PlainConfigPath } else { $null })
    GnustepThemedConfigPath = $(if ($gnustepConfig) { $gnustepConfig.ThemedConfigPath } else { $null })
    DesktopEntryPath = $desktopEntry.DesktopPath
    RootDesktopEntryPath = $desktopEntry.RootDesktopPath
    IconPaths = $iconAssets
    MimeTypes = [string[]]$desktopEntry.MimeTypes
    MimePackagePath = $mimePackagePath
    NoticeReportPath = $noticeReport.ReportPath
    UpdateRuntimeConfigPath = $updateRuntimeConfigPath
    RuntimeNotices = @($noticeReport.Entries)
  }
}

function Build-GpAppImageArtifact {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [psobject]$WorkPaths,
    [Parameter(Mandatory = $true)]
    [string]$ToolPath,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  Ensure-GpDirectory -Path $Config.ArtifactPlan.OutputRoot | Out-Null
  if (Test-Path $Config.ArtifactPlan.ArtifactPath) {
    Remove-Item -Force $Config.ArtifactPlan.ArtifactPath
  }

  $toolEnvironment = @{
    ARCH = "x86_64"
    VERSION = $Config.Version
  }
  if ($ToolPath.EndsWith(".AppImage", [System.StringComparison]::OrdinalIgnoreCase)) {
    $toolEnvironment["APPIMAGE_EXTRACT_AND_RUN"] = "1"
  }
  $runtimeFile = Ensure-GpAppImageRuntimeFile -ToolPath $ToolPath -WorkPaths $WorkPaths -LogPath $LogPath

  $arguments = [System.Collections.Generic.List[string]]::new()
  if ($Config.SkipAppStreamValidation) {
    $arguments.Add("-n") | Out-Null
  }
  if ($Config.Updates.EmbedUpdateInformation -and -not [string]::IsNullOrWhiteSpace($Config.Updates.UpdateInformation)) {
    $arguments.Add("-u") | Out-Null
    $arguments.Add($Config.Updates.UpdateInformation) | Out-Null
  }
  if (-not [string]::IsNullOrWhiteSpace($runtimeFile)) {
    $arguments.Add("--runtime-file") | Out-Null
    $arguments.Add($runtimeFile) | Out-Null
  }
  $arguments.Add($WorkPaths.AppDirRoot) | Out-Null
  $arguments.Add($Config.ArtifactPlan.ArtifactPath) | Out-Null

  Invoke-GpAppImageExternalTool -FilePath $ToolPath -ArgumentList ([string[]]$arguments.ToArray()) -LogPath $LogPath -Environment $toolEnvironment
  Set-GpUnixExecutable -Path $Config.ArtifactPlan.ArtifactPath
  Write-GpAppImageLogLine -LogPath $LogPath -Message ("Created AppImage artifact: {0}" -f $Config.ArtifactPlan.ArtifactPath)

  $zsyncArtifactPath = $null
  if ($Config.Updates.EmbedUpdateInformation -and -not [string]::IsNullOrWhiteSpace($Config.Updates.UpdateInformation)) {
    if (Test-Path $Config.Updates.ZsyncArtifactPath) {
      $zsyncArtifactPath = $Config.Updates.ZsyncArtifactPath
      Write-GpAppImageLogLine -LogPath $LogPath -Message ("Created AppImage zsync sidecar: {0}" -f $zsyncArtifactPath)
    } else {
      $workingDirectoryZsyncPath = Join-Path (Get-Location).Path $Config.Updates.ZsyncArtifactName
      if (Test-Path $workingDirectoryZsyncPath) {
        Ensure-GpDirectory -Path (Split-Path -Parent $Config.Updates.ZsyncArtifactPath) | Out-Null
        Move-Item -Force $workingDirectoryZsyncPath $Config.Updates.ZsyncArtifactPath
        $zsyncArtifactPath = $Config.Updates.ZsyncArtifactPath
        Write-GpAppImageLogLine -LogPath $LogPath -Message ("Moved AppImage zsync sidecar from working directory to artifact output root: {0}" -f $zsyncArtifactPath)
      } else {
        Write-GpAppImageLogLine -LogPath $LogPath -Message ("AppImage update information was embedded, but no .zsync sidecar was found at the expected path: {0}" -f $Config.Updates.ZsyncArtifactPath)
      }
    }
  }

  return [pscustomobject]@{
    ArtifactPath = $Config.ArtifactPlan.ArtifactPath
    ZsyncArtifactPath = $zsyncArtifactPath
  }
}

function New-GpAppImageUpdateAssetEntry {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [psobject]$Artifacts
  )

  $updateSettings = Get-GpUpdateSettings -Context $Context -Backend "appimage"
  if (-not $updateSettings.Enabled) {
    return $null
  }

  $asset = [ordered]@{
    backend = "appimage"
    platform = $updateSettings.Platform
    kind = "appimage"
    name = $Config.ArtifactPlan.ArtifactName
    url = Get-GpGitHubReleaseAssetUrl -UpdateSettings $updateSettings -AssetName $Config.ArtifactPlan.ArtifactName
    sha256 = Get-GpFileSha256 -Path $Artifacts.ArtifactPath
    sizeBytes = (Get-Item $Artifacts.ArtifactPath).Length
    updateInformation = $Config.Updates.UpdateInformation
  }

  if (-not [string]::IsNullOrWhiteSpace($Artifacts.ZsyncArtifactPath) -and (Test-Path $Artifacts.ZsyncArtifactPath)) {
    $zsyncName = Split-Path -Leaf $Artifacts.ZsyncArtifactPath
    $asset["zsync"] = [ordered]@{
      name = $zsyncName
      url = Get-GpGitHubReleaseAssetUrl -UpdateSettings $updateSettings -AssetName $zsyncName
      sha256 = Get-GpFileSha256 -Path $Artifacts.ZsyncArtifactPath
      sizeBytes = (Get-Item $Artifacts.ZsyncArtifactPath).Length
    }
  }

  return $asset
}

function Write-GpAppImageArtifactMetadata {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [psobject]$WorkPaths,
    [Parameter(Mandatory = $true)]
    [psobject]$AppDir,
    [Parameter(Mandatory = $true)]
    [psobject]$Artifacts,
    [Parameter(Mandatory = $true)]
    [string]$ToolPath,
    [string]$UpdateFeedPath,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  $launch = Get-GpLaunchContract -Context $Context
  $appDefaults = Get-GpAppImageAppDomainDefaults -Context $Context
  $hostEnvironment = Get-GpHostEnvironment
  $profiles = @(Get-GpRequestedProfiles -Manifest $Context.Manifest)
  $sidecars = Get-GpAppImageSidecarPaths -Config $Config
  $mimeEntries = @(Get-GpAppImageMimeEntries -Context $Context -Config $Config)
  $updateSettings = Get-GpUpdateSettings -Context $Context -Backend "appimage"
  $metadata = [ordered]@{
    generatedAt = (Get-Date).ToString("o")
    backend = "appimage"
    manifestPath = $Context.ManifestPath
    profiles = [string[]]$profiles
    package = [ordered]@{
      id = $Config.PackageId
      name = $Config.PackageName
      displayName = $Config.DisplayName
      version = $Config.Version
      manufacturer = $Config.Manufacturer
      homepage = $Config.Homepage
      license = $Config.License
    }
    artifacts = [ordered]@{
      appImage = [ordered]@{
        path = $Artifacts.ArtifactPath
        sha256 = Get-GpFileSha256 -Path $Artifacts.ArtifactPath
        sizeBytes = (Get-Item $Artifacts.ArtifactPath).Length
      }
      zsync = $(if (-not [string]::IsNullOrWhiteSpace($Artifacts.ZsyncArtifactPath) -and (Test-Path $Artifacts.ZsyncArtifactPath)) {
        [ordered]@{
          path = $Artifacts.ZsyncArtifactPath
          sha256 = Get-GpFileSha256 -Path $Artifacts.ZsyncArtifactPath
          sizeBytes = (Get-Item $Artifacts.ZsyncArtifactPath).Length
        }
      } else {
        $null
      })
      metadata = [ordered]@{
        path = $sidecars.MetadataPath
      }
      updateFeed = $(if (-not [string]::IsNullOrWhiteSpace($UpdateFeedPath) -and (Test-Path $UpdateFeedPath)) {
        [ordered]@{
          path = $UpdateFeedPath
          sha256 = Get-GpFileSha256 -Path $UpdateFeedPath
          sizeBytes = (Get-Item $UpdateFeedPath).Length
        }
      } else {
        $null
      })
      diagnostics = [ordered]@{
        path = $sidecars.DiagnosticsPath
      }
    }
    appDir = [ordered]@{
      path = $AppDir.AppDirRoot
      appRunPath = $AppDir.AppRunPath
      desktopEntryPath = $AppDir.DesktopEntryPath
      rootDesktopEntryPath = $AppDir.RootDesktopEntryPath
      iconPath = $AppDir.IconPaths.ShareIconPath
      dirIconPath = $AppDir.IconPaths.DirIconPath
      mimePackagePath = $AppDir.MimePackagePath
      noticeReportPath = $AppDir.NoticeReportPath
      updateRuntimeConfigPath = $AppDir.UpdateRuntimeConfigPath
    }
    launch = [ordered]@{
      entryRelativePath = $launch.EntryRelativePath
      workingDirectory = $launch.WorkingDirectory
      arguments = [string[]]@($launch.Arguments)
      pathPrepend = [string[]]@($launch.PathPrepend)
      resourceRoots = [string[]]@($launch.ResourceRoots)
      environment = [hashtable](Copy-GpValue -Value (Get-GpLaunchEnvironmentForAppImage -Context $Context))
      appDomainDefaults = $(if ($null -ne $appDefaults -and @($appDefaults.Entries).Count -gt 0) {
        [ordered]@{
          domain = $appDefaults.Domain
          entries = @(
            foreach ($entry in @($appDefaults.Entries)) {
              [ordered]@{
                key = $entry.Key
                type = $entry.Type
                value = $entry.Value
                serializedValue = $entry.SerializedValue
              }
            }
          )
        }
      } else {
        $null
      })
    }
    desktop = [ordered]@{
      desktopEntryName = $Config.DesktopEntryName
      iconName = $Config.IconName
      mimeTypes = [string[]](Get-GpAppImageDesktopMimeTypes -MimeEntries $mimeEntries)
    }
    validation = [ordered]@{
      sharedSmoke = [ordered]@{
        enabled = [bool]$Context.Manifest["validation"]["smoke"]["enabled"]
        kind = [string]$Context.Manifest["validation"]["smoke"]["kind"]
        requiredPaths = [string[]]@($Context.Manifest["validation"]["smoke"]["requiredPaths"])
        timeoutSeconds = [int]$Context.Manifest["validation"]["smoke"]["timeoutSeconds"]
      }
      appimageSmoke = [ordered]@{
        mode = $Config.Smoke.Mode
        arguments = [string[]]@($Config.Smoke.Arguments)
        environment = [hashtable](Copy-GpValue -Value $Config.Smoke.Environment)
        documentStageRelativePath = $Config.Smoke.DocumentStageRelativePath
        startupSeconds = [int]$Config.Smoke.StartupSeconds
      }
      runtimeClosure = [ordered]@{
        mode = $Config.Validation.RuntimeClosure
        allowedSystemLibraries = [string[]]@($Config.Validation.AllowedSystemLibraries)
        allowedExternalRunpaths = [string[]]@($Config.Validation.AllowedExternalRunpaths)
      }
    }
    compliance = [ordered]@{
      noticeReportPath = $AppDir.NoticeReportPath
      runtimeNotices = @(
        foreach ($entry in @($AppDir.RuntimeNotices)) {
          [ordered]@{
            name = $entry.Name
            version = $entry.Version
            license = $entry.License
            source = $entry.Source
            homepage = $entry.Homepage
            stageRelativePath = $entry.StageRelativePath
            installedPath = $entry.InstalledPath
          }
        }
      )
    }
    updates = [ordered]@{
      enabled = [bool]$updateSettings.Enabled
      channel = $updateSettings.Channel
      feedUrl = $updateSettings.FeedUrl
      runtimeConfigRelativePath = $updateSettings.RuntimeConfigRelativePath
      releaseTag = $updateSettings.GitHub.Tag
      releaseNotesUrl = $updateSettings.GitHub.ReleaseNotesUrl
      appimage = [ordered]@{
        embedUpdateInformation = [bool]$Config.Updates.EmbedUpdateInformation
        releaseSelector = $Config.Updates.ReleaseSelector
        updateInformation = $Config.Updates.UpdateInformation
        zsyncArtifactName = $Config.Updates.ZsyncArtifactName
      }
    }
    tooling = [ordered]@{
      appimagetool = $ToolPath
      desktopFileValidate = $(Get-Command desktop-file-validate -ErrorAction SilentlyContinue | Select-Object -First 1 | ForEach-Object { $_.Source })
    }
    outputs = [ordered]@{
      logPath = $LogPath
      workRoot = $WorkPaths.Root
      diagnosticsDocPath = Get-GpAppImageDiagnosticsDocPath
    }
    host = [ordered]@{
      platform = $hostEnvironment.Platform
      pwshVersion = $hostEnvironment.PwshVersion
      currentPath = $hostEnvironment.CurrentPath
      toolRoot = $hostEnvironment.ToolRoot
    }
  }

  $metadata | ConvertTo-Json -Depth 20 | Set-Content -Path $sidecars.MetadataPath -Encoding utf8
  Write-GpAppImageLogLine -LogPath $LogPath -Message ("Wrote artifact metadata: {0}" -f $sidecars.MetadataPath)
  return $sidecars.MetadataPath
}

function Write-GpAppImageDiagnosticsSummary {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [psobject]$AppDir,
    [Parameter(Mandatory = $true)]
    [string]$MetadataPath,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  $sidecars = Get-GpAppImageSidecarPaths -Config $Config
  $lines = [System.Collections.Generic.List[string]]::new()
  $lines.Add(("AppImage packaging summary for {0}" -f $Config.DisplayName)) | Out-Null
  $lines.Add(("Manifest: {0}" -f $Context.ManifestPath)) | Out-Null
  $lines.Add(("Artifact: {0}" -f $Config.ArtifactPlan.ArtifactPath)) | Out-Null
  $lines.Add(("Metadata: {0}" -f $MetadataPath)) | Out-Null
  $lines.Add(("Package log: {0}" -f $LogPath)) | Out-Null
  $lines.Add(("AppDir: {0}" -f $AppDir.AppDirRoot)) | Out-Null
  $lines.Add(("Desktop entry: {0}" -f $AppDir.DesktopEntryPath)) | Out-Null
  if (-not [string]::IsNullOrWhiteSpace($AppDir.UpdateRuntimeConfigPath)) {
    $lines.Add(("Updater runtime config: {0}" -f $AppDir.UpdateRuntimeConfigPath)) | Out-Null
  }
  if ($Config.Updates.Enabled) {
    $lines.Add(("Update channel: {0}" -f $Config.Updates.Channel)) | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($Config.Updates.FeedUrl)) {
      $lines.Add(("Update feed URL: {0}" -f $Config.Updates.FeedUrl)) | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($Config.Updates.UpdateInformation)) {
      $lines.Add(("Embedded AppImage update info: {0}" -f $Config.Updates.UpdateInformation)) | Out-Null
    }
  }
  $lines.Add(("Smoke mode: {0}" -f $Config.Smoke.Mode)) | Out-Null
  $lines.Add(("Runtime closure mode: {0}" -f $Config.Validation.RuntimeClosure)) | Out-Null
  $lines.Add(("Triage guide: {0}" -f (Get-GpAppImageDiagnosticsDocPath))) | Out-Null
  $lines.Add("") | Out-Null
  $lines.Add("Reproduction commands:") | Out-Null
  $lines.Add(("./scripts/gnustep-packager.ps1 -Command package -Manifest `"{0}`" -Backend appimage" -f $Context.ManifestPath)) | Out-Null
  $lines.Add(("./scripts/gnustep-packager.ps1 -Command validate -Manifest `"{0}`" -Backend appimage -RunSmoke" -f $Context.ManifestPath)) | Out-Null
  $lines.Add("") | Out-Null
  $lines.Add("Common failure areas: staged icon path, desktop entry rendering, MIME metadata, appimagetool bootstrap, AppImage extraction, smoke launch.") | Out-Null

  Set-Content -Path $sidecars.DiagnosticsPath -Value $lines -Encoding ascii
  Write-GpAppImageLogLine -LogPath $LogPath -Message ("Wrote diagnostics summary: {0}" -f $sidecars.DiagnosticsPath)
  return $sidecars.DiagnosticsPath
}

function Invoke-GpAppImagePackage {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [switch]$DryRun,
    [string]$LogPath
  )

  $config = Get-GpAppImageConfig -Context $Context
  $workPaths = Get-GpAppImageWorkPaths -Context $Context -Config $config
  $launch = Get-GpLaunchContract -Context $Context
  $backendSupport = Get-GpBackendSupport -Backend "appimage"
  $summary = [ordered]@{
    Backend = "appimage"
    ManifestPath = $Context.ManifestPath
    ProductName = $config.DisplayName
    Version = $config.Version
    StageRoot = $config.StageRoot
    EntryPath = $launch.EntryPath
    ArtifactPath = $config.ArtifactPlan.ArtifactPath
    AppDirRoot = $workPaths.AppDirRoot
    DesktopEntryName = $config.DesktopEntryName
    HostPlatform = $backendSupport.HostPlatform
    RequiredPlatform = $backendSupport.RequiredPlatform
    HostSupported = [bool]$backendSupport.Supported
  }

  if ($DryRun) {
    Write-GpAppImageLogLine -LogPath $LogPath -Message ("AppImage package dry-run for {0}" -f $config.DisplayName)
    return [pscustomobject]$summary
  }

  if (-not $backendSupport.Supported) {
    throw "AppImage packaging requires host platform '$($backendSupport.RequiredPlatform)'. Current host: '$($backendSupport.HostPlatform)'."
  }

  Write-GpAppImageLogLine -LogPath $LogPath -Message ("Starting AppImage package build for {0}" -f $config.DisplayName)
  $appDir = Prepare-GpAppDir -Context $Context -Config $config -WorkPaths $workPaths -LogPath $LogPath
  $toolPath = Ensure-GpAppImageTool -Config $config -WorkPaths $workPaths -LogPath $LogPath
  $artifacts = Build-GpAppImageArtifact -Config $config -WorkPaths $workPaths -ToolPath $toolPath -LogPath $LogPath
  $updateFeedPath = $null
  $updateAssetEntry = New-GpAppImageUpdateAssetEntry -Context $Context -Config $config -Artifacts $artifacts
  if ($null -ne $updateAssetEntry) {
    $updateFeedPath = Write-GpUpdateFeedDocument -Context $Context -Backend "appimage" -ArtifactPath $artifacts.ArtifactPath -Assets @($updateAssetEntry)
    if (-not [string]::IsNullOrWhiteSpace($updateFeedPath)) {
      Write-GpAppImageLogLine -LogPath $LogPath -Message ("Wrote update feed sidecar: {0}" -f $updateFeedPath)
    }
  }
  $metadataPath = Write-GpAppImageArtifactMetadata -Context $Context -Config $config -WorkPaths $workPaths -AppDir $appDir -Artifacts $artifacts -ToolPath $toolPath -UpdateFeedPath $updateFeedPath -LogPath $LogPath
  $provenancePath = Write-GpProvenanceDocument -Context $Context -Backend "appimage" -ArtifactPath $artifacts.ArtifactPath -PayloadRoot $appDir.AppDirRoot -EntryPath (Join-Path (Join-Path $appDir.AppDirRoot "usr") $launch.EntryRelativePath)
  if (-not [string]::IsNullOrWhiteSpace($provenancePath)) {
    Write-GpAppImageLogLine -LogPath $LogPath -Message ("Wrote provenance sidecar: {0}" -f $provenancePath)
  }
  $diagnosticsPath = Write-GpAppImageDiagnosticsSummary -Context $Context -Config $config -AppDir $appDir -MetadataPath $metadataPath -LogPath $LogPath

  return [pscustomobject]@{
    Backend = "appimage"
    ManifestPath = $Context.ManifestPath
    ArtifactPath = $artifacts.ArtifactPath
    ZsyncArtifactPath = $artifacts.ZsyncArtifactPath
    MetadataPath = $metadataPath
    ProvenancePath = $provenancePath
    UpdateFeedPath = $updateFeedPath
    DiagnosticsPath = $diagnosticsPath
    AppDirRoot = $appDir.AppDirRoot
    AppRunPath = $appDir.AppRunPath
    GnustepConfigPath = $appDir.GnustepConfigPath
    GnustepThemedConfigPath = $appDir.GnustepThemedConfigPath
    DesktopEntryPath = $appDir.DesktopEntryPath
    RootDesktopEntryPath = $appDir.RootDesktopEntryPath
    IconPath = $appDir.IconPaths.ShareIconPath
    DirIconPath = $appDir.IconPaths.DirIconPath
    MimePackagePath = $appDir.MimePackagePath
    NoticeReportPath = $appDir.NoticeReportPath
    UpdateRuntimeConfigPath = $appDir.UpdateRuntimeConfigPath
    LogPath = $LogPath
  }
}

function Test-GpAppImageDesktopEntry {
  param(
    [Parameter(Mandatory = $true)]
    [string]$DesktopPath
  )

  $lines = Get-Content -Path $DesktopPath
  $section = ""
  $properties = @{}
  foreach ($line in @($lines)) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#", [System.StringComparison]::Ordinal)) {
      continue
    }
    if ($trimmed.StartsWith("[") -and $trimmed.EndsWith("]")) {
      $section = $trimmed
      continue
    }
    if ($section -ne "[Desktop Entry]") {
      continue
    }
    $separatorIndex = $trimmed.IndexOf("=")
    if ($separatorIndex -lt 1) {
      continue
    }
    $properties[$trimmed.Substring(0, $separatorIndex)] = $trimmed.Substring($separatorIndex + 1)
  }

  $issues = [System.Collections.Generic.List[string]]::new()
  foreach ($key in @("Type", "Name", "Exec", "Icon")) {
    if (-not $properties.ContainsKey($key) -or [string]::IsNullOrWhiteSpace([string]$properties[$key])) {
      $issues.Add("Missing desktop entry field: $key") | Out-Null
    }
  }
  if ($properties.ContainsKey("Type") -and $properties["Type"] -ne "Application") {
    $issues.Add("Desktop entry Type must be Application.") | Out-Null
  }

  return [string[]]$issues.ToArray()
}

function Expand-GpAppImageArtifact {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ArtifactPath,
    [Parameter(Mandatory = $true)]
    [string]$ExtractRoot,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  Reset-GpAppImageDirectory -Path $ExtractRoot
  $workingArtifactPath = Join-Path $ExtractRoot ([System.IO.Path]::GetFileName($ArtifactPath))
  Copy-Item -Force $ArtifactPath $workingArtifactPath
  Set-GpUnixExecutable -Path $workingArtifactPath

  Push-Location $ExtractRoot
  try {
    Invoke-GpAppImageExternalTool -FilePath $workingArtifactPath -ArgumentList @("--appimage-extract") -LogPath $LogPath
  } finally {
    Pop-Location
  }

  $expandedPath = Join-Path $ExtractRoot "squashfs-root"
  if (-not (Test-Path $expandedPath)) {
    throw "Expected extracted AppImage contents at $expandedPath"
  }

  return $expandedPath
}

function Test-GpElfFile {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $stream = $null
  try {
    $stream = [System.IO.File]::OpenRead($Path)
    if ($stream.Length -lt 4) {
      return $false
    }

    $buffer = New-Object byte[] 4
    $read = $stream.Read($buffer, 0, $buffer.Length)
    return ($read -eq 4) -and ($buffer[0] -eq 0x7F) -and ($buffer[1] -eq 0x45) -and ($buffer[2] -eq 0x4C) -and ($buffer[3] -eq 0x46)
  } catch {
    return $false
  } finally {
    if ($null -ne $stream) {
      $stream.Dispose()
    }
  }
}

function Invoke-GpAppImageCapturedTool {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [string[]]$ArgumentList,
    [hashtable]$Environment = @{}
  )

  $previousValues = @{}
  foreach ($key in $Environment.Keys) {
    $previousValues[$key] = [System.Environment]::GetEnvironmentVariable($key, "Process")
    [System.Environment]::SetEnvironmentVariable($key, [string]$Environment[$key], "Process")
  }

  try {
    $global:LASTEXITCODE = 0
    $output = & $FilePath @ArgumentList 2>&1
    $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
  } finally {
    foreach ($key in $previousValues.Keys) {
      [System.Environment]::SetEnvironmentVariable($key, $previousValues[$key], "Process")
    }
  }

  $lines = @(
    foreach ($line in @($output)) {
      [string]$line
    }
  )

  return [pscustomobject]@{
    ExitCode = $exitCode
    Lines = [string[]]@($lines)
    Text = [string]::Join([System.Environment]::NewLine, @($lines))
  }
}

function Get-GpAppImageElfFiles {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Root
  )

  $files = [System.Collections.Generic.List[string]]::new()
  foreach ($item in Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue) {
    if (Test-GpElfFile -Path $item.FullName) {
      $files.Add($item.FullName) | Out-Null
    }
  }

  return [string[]]@($files.ToArray() | Sort-Object -Unique)
}

function Get-GpAppImageRuntimeLibrarySearchPaths {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ExpandedRoot,
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [string[]]$ElfFiles
  )

  $paths = [System.Collections.Generic.List[string]]::new()
  $seen = @{}

  function Add-Path([string]$PathValue) {
    if ([string]::IsNullOrWhiteSpace($PathValue) -or -not (Test-Path $PathValue) -or $seen.ContainsKey($PathValue)) {
      return
    }
    $seen[$PathValue] = $true
    $paths.Add($PathValue) | Out-Null
  }

  $usrRoot = Join-Path $ExpandedRoot "usr"
  Add-Path $usrRoot
  Add-Path (Join-Path $usrRoot "lib")
  Add-Path (Join-Path $usrRoot "lib64")

  foreach ($file in @($ElfFiles)) {
    Add-Path (Split-Path -Parent $file)
  }

  return [string[]]@($paths.ToArray())
}

function Get-GpAppImageReadElfDynamicInfo {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $readelf = Get-Command readelf -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $readelf) {
    throw "AppImage runtime validation requires readelf on PATH."
  }

  $result = Invoke-GpAppImageCapturedTool -FilePath $readelf.Source -ArgumentList @("-d", $Path)
  $needed = [System.Collections.Generic.List[string]]::new()
  $runpaths = [System.Collections.Generic.List[string]]::new()
  $hasDynamicSection = $false
  $missingDynamicSection = $false

  foreach ($line in @($result.Lines)) {
    if ($line -match "There is no dynamic section in this file") {
      $missingDynamicSection = $true
      continue
    }
    if ($line -match "Shared library: \[(.+)\]") {
      $hasDynamicSection = $true
      $needed.Add([string]$Matches[1]) | Out-Null
      continue
    }
    if ($line -match "(RUNPATH|RPATH).*\[(.*)\]") {
      $hasDynamicSection = $true
      foreach ($entry in @(([string]$Matches[2]) -split ":")) {
        if (-not [string]::IsNullOrWhiteSpace($entry)) {
          $runpaths.Add($entry) | Out-Null
        }
      }
    }
  }

  if ($result.ExitCode -ne 0 -and -not $missingDynamicSection) {
    throw "readelf failed for $Path"
  }

  return [pscustomobject]@{
    HasDynamicSection = [bool]($hasDynamicSection -and -not $missingDynamicSection)
    NeededLibraries = [string[]]@($needed.ToArray() | Sort-Object -Unique)
    Runpaths = [string[]]@($runpaths.ToArray() | Sort-Object -Unique)
    RawOutput = $result.Text
  }
}

function Get-GpAppImageRunpathIssues {
  param(
    [AllowEmptyCollection()]
    [string[]]$Runpaths,
    [Parameter(Mandatory = $true)]
    [string]$ExpandedRoot,
    [AllowEmptyCollection()]
    [string[]]$AllowedExternalRunpaths
  )

  $allowed = @{}
  foreach ($entry in @($AllowedExternalRunpaths)) {
    if (-not [string]::IsNullOrWhiteSpace($entry)) {
      $allowed[[string]$entry] = $true
    }
  }

  $issues = [System.Collections.Generic.List[string]]::new()
  foreach ($entry in @($Runpaths)) {
    if ([string]::IsNullOrWhiteSpace($entry)) {
      continue
    }

    if ($allowed.ContainsKey([string]$entry)) {
      continue
    }

    if ($entry.StartsWith('$ORIGIN', [System.StringComparison]::Ordinal) -or
        $entry.StartsWith('${ORIGIN}', [System.StringComparison]::Ordinal) -or
        $entry.StartsWith($ExpandedRoot, [System.StringComparison]::Ordinal)) {
      continue
    }

    $issues.Add([string]$entry) | Out-Null
  }

  return [string[]]@($issues.ToArray())
}

function Get-GpAppImageLddDependencies {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [hashtable]$Environment,
    [Parameter(Mandatory = $true)]
    [string]$ExpandedRoot
  )

  $ldd = Get-Command ldd -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $ldd) {
    throw "AppImage runtime validation requires ldd on PATH."
  }

  $result = Invoke-GpAppImageCapturedTool -FilePath $ldd.Source -ArgumentList @($Path) -Environment $Environment
  $dependencies = [System.Collections.Generic.List[psobject]]::new()
  $isDynamic = $true

  foreach ($line in @($result.Lines)) {
    if ($line -match "statically linked" -or $line -match "not a dynamic executable") {
      $isDynamic = $false
      continue
    }

    if ($line -match '^\s*(\S+)\s+=>\s+not found') {
      $dependencies.Add([pscustomobject]@{
        Name = [string]$Matches[1]
        Path = $null
        Status = "not-found"
      }) | Out-Null
      continue
    }

    if ($line -match '^\s*(\S+)\s+=>\s+(\S+)\s+\(') {
      $resolvedPath = [string]$Matches[2]
      $dependencies.Add([pscustomobject]@{
        Name = [string]$Matches[1]
        Path = $resolvedPath
        Status = $(if ($resolvedPath.StartsWith($ExpandedRoot, [System.StringComparison]::Ordinal)) { "bundled" } else { "external" })
      }) | Out-Null
      continue
    }

    if ($line -match '^\s*(/[^ ]+)\s+\(') {
      $resolvedPath = [string]$Matches[1]
      $dependencies.Add([pscustomobject]@{
        Name = [System.IO.Path]::GetFileName($resolvedPath)
        Path = $resolvedPath
        Status = $(if ($resolvedPath.StartsWith($ExpandedRoot, [System.StringComparison]::Ordinal)) { "bundled" } else { "external" })
      }) | Out-Null
      continue
    }

    if ($line -match '^\s*(linux-vdso\.so\.\d+)\s+\(') {
      $dependencies.Add([pscustomobject]@{
        Name = [string]$Matches[1]
        Path = $null
        Status = "special"
      }) | Out-Null
    }
  }

  $hasMissingDependencies = @($dependencies | Where-Object { $_.Status -eq "not-found" }).Count -gt 0
  if ($result.ExitCode -ne 0 -and $isDynamic -and -not $hasMissingDependencies) {
    throw "ldd failed for $Path"
  }

  return [pscustomobject]@{
    IsDynamic = [bool]$isDynamic
    Dependencies = @($dependencies.ToArray())
    RawOutput = $result.Text
  }
}

function Test-GpAppImageAllowedSystemLibrary {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Dependency,
    [AllowEmptyCollection()]
    [string[]]$AllowedSystemLibraries
  )

  foreach ($allowed in @($AllowedSystemLibraries)) {
    if ([string]::IsNullOrWhiteSpace($allowed)) {
      continue
    }

    if ([string]::Equals([string]$Dependency.Name, [string]$allowed, [System.StringComparison]::OrdinalIgnoreCase)) {
      return $true
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Dependency.Path)) {
      $leaf = [System.IO.Path]::GetFileName([string]$Dependency.Path)
      if ([string]::Equals($leaf, [string]$allowed, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
      }
    }
  }

  return $false
}

function Invoke-GpAppImageRuntimeClosureValidation {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [string]$ExpandedRoot,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  Set-Content -Path $LogPath -Value ("[{0}] AppImage runtime-closure validation" -f (Get-Date).ToString("o"))

  if ($Config.Validation.RuntimeClosure -ne "strict") {
    Write-GpAppImageLogLine -LogPath $LogPath -Message ("Runtime closure validation mode: {0}" -f $Config.Validation.RuntimeClosure)
    return [pscustomobject]@{
      Mode = [string]$Config.Validation.RuntimeClosure
      CheckedFileCount = 0
      DynamicFileCount = 0
      LibrarySearchPaths = @()
      LogPath = $LogPath
    }
  }

  $elfFiles = @(Get-GpAppImageElfFiles -Root $ExpandedRoot)
  Write-GpAppImageLogLine -LogPath $LogPath -Message ("Found ELF files: {0}" -f $elfFiles.Count)
  if ($elfFiles.Count -eq 0) {
    return [pscustomobject]@{
      Mode = "strict"
      CheckedFileCount = 0
      DynamicFileCount = 0
      LibrarySearchPaths = @()
      LogPath = $LogPath
    }
  }

  $librarySearchPaths = @(Get-GpAppImageRuntimeLibrarySearchPaths -ExpandedRoot $ExpandedRoot -ElfFiles $elfFiles)
  if ($librarySearchPaths.Count -gt 0) {
    Write-GpAppImageLogLine -LogPath $LogPath -Message ("Packaged library search paths: {0}" -f ([string]::Join(":", $librarySearchPaths)))
  }

  $ldEnvironment = @{}
  if ($librarySearchPaths.Count -gt 0) {
    $ldEnvironment["LD_LIBRARY_PATH"] = [string]::Join(":", $librarySearchPaths)
  }

  $issues = [System.Collections.Generic.List[string]]::new()
  $dynamicFileCount = 0
  foreach ($file in @($elfFiles)) {
    Write-GpAppImageLogLine -LogPath $LogPath -Message ("Inspecting ELF: {0}" -f $file)
    $dynamicInfo = Get-GpAppImageReadElfDynamicInfo -Path $file
    foreach ($entry in @(Get-GpAppImageRunpathIssues -Runpaths $dynamicInfo.Runpaths -ExpandedRoot $ExpandedRoot -AllowedExternalRunpaths @($Config.Validation.AllowedExternalRunpaths))) {
      $issues.Add(("Packaged ELF escaped the AppDir via RUNPATH/RPATH: {0} -> {1}" -f $file, $entry)) | Out-Null
    }

    if (-not $dynamicInfo.HasDynamicSection) {
      Write-GpAppImageLogLine -LogPath $LogPath -Message "No dynamic section found; skipping dependency resolution."
      continue
    }

    $dynamicFileCount += 1
    $lddInfo = Get-GpAppImageLddDependencies -Path $file -Environment $ldEnvironment -ExpandedRoot $ExpandedRoot
    if (-not $lddInfo.IsDynamic) {
      Write-GpAppImageLogLine -LogPath $LogPath -Message "ldd reported a non-dynamic executable."
      continue
    }

    foreach ($dependency in @($lddInfo.Dependencies)) {
      switch ($dependency.Status) {
        "not-found" {
          $issues.Add(("Packaged ELF has unresolved dependency under packaged LD_LIBRARY_PATH: {0} -> {1}" -f $file, $dependency.Name)) | Out-Null
        }

        "external" {
          if (@($Config.Validation.AllowedSystemLibraries).Count -gt 0) {
            if (Test-GpAppImageAllowedSystemLibrary -Dependency $dependency -AllowedSystemLibraries @($Config.Validation.AllowedSystemLibraries)) {
              Write-GpAppImageLogLine -LogPath $LogPath -Message ("Allowed host-resolved dependency: {0} -> {1}" -f $dependency.Name, $dependency.Path)
            } else {
              $issues.Add(("Packaged ELF resolved an external host library not allowlisted: {0} -> {1}" -f $file, $dependency.Path)) | Out-Null
            }
          } else {
            Write-GpAppImageLogLine -LogPath $LogPath -Message ("Observed host-resolved dependency outside the packaged AppDir: {0} -> {1}" -f $dependency.Name, $dependency.Path)
          }
        }
      }
    }
  }

  if ($issues.Count -gt 0) {
    foreach ($issue in @($issues)) {
      Write-GpAppImageLogLine -LogPath $LogPath -Message $issue
    }
    throw "AppImage runtime-closure validation failed. See $LogPath."
  }

  Write-GpAppImageLogLine -LogPath $LogPath -Message ("Runtime closure validation succeeded for {0} dynamic ELF file(s)." -f $dynamicFileCount)
  return [pscustomobject]@{
    Mode = "strict"
    CheckedFileCount = $elfFiles.Count
    DynamicFileCount = $dynamicFileCount
    LibrarySearchPaths = [string[]]@($librarySearchPaths)
    LogPath = $LogPath
  }
}

function Start-GpAppImageSmokeProcess {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ArtifactPath,
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [string[]]$ArgumentList,
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Environment,
    [Parameter(Mandatory = $true)]
    [string]$StdOutPath,
    [Parameter(Mandatory = $true)]
    [string]$StdErrPath,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  if (Test-Path $StdOutPath) {
    Remove-Item -Force $StdOutPath
  }
  if (Test-Path $StdErrPath) {
    Remove-Item -Force $StdErrPath
  }

  $commandParts = [System.Collections.Generic.List[string]]::new()
  foreach ($key in ($Environment.Keys | Sort-Object)) {
    $commandParts.Add(("{0}={1}" -f $key, [string]$Environment[$key])) | Out-Null
  }
  $commandParts.Add($ArtifactPath) | Out-Null
  foreach ($argument in @($ArgumentList)) {
    $commandParts.Add($argument) | Out-Null
  }

  # env -i: the app gets only $Environment, not this process's environment.
  $commandParts.Insert(0, "-i")
  Write-GpAppImageLogLine -LogPath $LogPath -Message ("RUN env {0}" -f ([string]::Join(" ", @($commandParts.ToArray()))))
  # Start-Process joins the arguments with spaces, so quote any that have
  # spaces or quotes in them.
  $quotedParts = foreach ($part in $commandParts) {
    if ($part.Length -eq 0 -or $part -match '[\s"]') {
      '"' + $part.Replace('"', '\"') + '"'
    } else {
      $part
    }
  }
  return (Start-Process -FilePath "env" -ArgumentList @($quotedParts) -PassThru -RedirectStandardOutput $StdOutPath -RedirectStandardError $StdErrPath)
}

# Processes that belong to a smoke launch: those under the smoke process,
# and any process whose environment has the smoke's GNUSTEP_HOME. gdnc and
# gpbs detach from the app's process tree, but they keep its environment.
function Get-GpAppImageSmokeProcessIds {
  param(
    [int]$RootProcessId = 0,
    [string]$GnustepHome
  )

  $ids = [System.Collections.Generic.HashSet[int]]::new()
  if ($RootProcessId -gt 0) {
    $children = @{}
    foreach ($line in @(& ps -e -o pid=,ppid= 2>$null)) {
      $fields = ([string]$line).Trim() -split '\s+'
      if ($fields.Count -lt 2) {
        continue
      }
      $parentId = [int]$fields[1]
      if (-not $children.ContainsKey($parentId)) {
        $children[$parentId] = [System.Collections.Generic.List[int]]::new()
      }
      $children[$parentId].Add([int]$fields[0]) | Out-Null
    }

    $pending = [System.Collections.Generic.Queue[int]]::new()
    $pending.Enqueue($RootProcessId)
    while ($pending.Count -gt 0) {
      $current = $pending.Dequeue()
      if ($ids.Add($current) -and $children.ContainsKey($current)) {
        foreach ($child in $children[$current]) {
          $pending.Enqueue($child)
        }
      }
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($GnustepHome) -and (Test-Path "/proc")) {
    $marker = [System.Text.Encoding]::UTF8.GetBytes("GNUSTEP_HOME=" + $GnustepHome)
    foreach ($directory in @(Get-ChildItem -LiteralPath "/proc" -Directory -ErrorAction SilentlyContinue)) {
      $processId = 0
      if (-not [int]::TryParse($directory.Name, [ref]$processId) -or $processId -eq $PID) {
        continue
      }
      try {
        $environ = [System.IO.File]::ReadAllBytes((Join-Path $directory.FullName "environ"))
      } catch {
        continue
      }
      # Entries are NUL-separated; match a whole entry.
      $start = 0
      for ($index = 0; $index -le $environ.Length; $index++) {
        if ($index -eq $environ.Length -or $environ[$index] -eq 0) {
          if (($index - $start) -eq $marker.Length -and
              [System.Linq.Enumerable]::SequenceEqual([byte[]]$environ[$start..($index - 1)], [byte[]]$marker)) {
            $ids.Add($processId) | Out-Null
            break
          }
          $start = $index + 1
        }
      }
    }
  }

  return [int[]]@($ids)
}

# Ends a smoke launch and everything it started: TERM, a short wait, then
# KILL. Returns the processes still alive afterwards.
function Stop-GpAppImageSmokeProcess {
  param(
    [AllowNull()]
    [System.Diagnostics.Process]$Process,
    [string]$GnustepHome
  )

  $rootId = if ($null -ne $Process) { $Process.Id } else { 0 }
  $targets = @(Get-GpAppImageSmokeProcessIds -RootProcessId $rootId -GnustepHome $GnustepHome)
  if ($targets.Count -eq 0) {
    return [int[]]@()
  }

  foreach ($signal in @("TERM", "KILL")) {
    $alive = @($targets | Where-Object { Test-Path ("/proc/{0}" -f $_) })
    if ($alive.Count -eq 0) {
      break
    }
    & env kill ("-" + $signal) @($alive | ForEach-Object { [string]$_ }) 2>$null
    $deadline = (Get-Date).AddSeconds(3)
    while ((Get-Date) -lt $deadline -and @($alive | Where-Object { Test-Path ("/proc/{0}" -f $_) }).Count -gt 0) {
      Start-Sleep -Milliseconds 100
    }
    # Pick up anything started while the first ones were stopping.
    $targets = @(@($targets) + @(Get-GpAppImageSmokeProcessIds -GnustepHome $GnustepHome) | Select-Object -Unique)
  }

  if ($null -ne $Process) {
    try {
      $Process.WaitForExit(2000) | Out-Null
    } catch {
    }
  }

  return [int[]]@($targets | Where-Object { Test-Path ("/proc/{0}" -f $_) })
}

function Complete-GpAppImageSmokeProcess {
  param(
    [AllowNull()]
    [System.Diagnostics.Process]$Process,
    [Parameter(Mandatory = $true)]
    [string]$StdOutPath,
    [Parameter(Mandatory = $true)]
    [string]$StdErrPath,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  $exitCode = 0
  $output = [System.Text.StringBuilder]::new()
  if ($null -ne $Process) {
    try {
      $Process.Refresh()
      if (-not $Process.HasExited) {
        $Process.WaitForExit(5000) | Out-Null
        $Process.Refresh()
      }
      if ($Process.HasExited) {
        $exitCode = [int]$Process.ExitCode
      }
    } catch {
    }
  }

  foreach ($stream in @(
    [pscustomobject]@{ Label = "stdout"; Path = $StdOutPath },
    [pscustomobject]@{ Label = "stderr"; Path = $StdErrPath }
  )) {
    if (Test-Path $stream.Path) {
      $content = Get-Content -Raw -Path $stream.Path
      if (-not [string]::IsNullOrWhiteSpace($content)) {
        $output.AppendLine($content) | Out-Null
        Add-Content -Path $LogPath -Value ""
        Add-Content -Path $LogPath -Value ("[{0}]" -f $stream.Label)
        Add-Content -Path $LogPath -Value $content
      }
      Remove-Item -Force $stream.Path
    }
  }

  return [pscustomobject]@{
    ExitCode = $exitCode
    Output = $output.ToString()
  }
}

function Invoke-GpAppImageSmoke {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [psobject]$ValidationPlan,
    [Parameter(Mandatory = $true)]
    [string]$ValidationRoot,
    [Parameter(Mandatory = $true)]
    [string]$SmokeLog
  )

  $smokePlan = Get-GpAppImageSmokePlan -Context $Context -Config $Config -ValidationRoot $ValidationRoot
  # Leftovers from an earlier smoke launch here (same GNUstep home) would
  # still have its windows up; end them before starting over.
  $leftovers = @(Stop-GpAppImageSmokeProcess -Process $null -GnustepHome (Join-Path $ValidationRoot "smoke-env/home"))
  $smokeEnvironment = Get-GpAppImageSmokeBaseEnvironment -ValidationRoot $ValidationRoot
  foreach ($key in @($smokePlan.Environment.Keys)) {
    $smokeEnvironment[$key] = $smokePlan.Environment[$key]
  }
  # A HOME from smoke.environment is GNUstep's home too.
  if ($smokePlan.Environment.ContainsKey("HOME") -and -not $smokePlan.Environment.ContainsKey("GNUSTEP_HOME")) {
    $smokeEnvironment["GNUSTEP_HOME"] = $smokePlan.Environment["HOME"]
  }
  $smokeEnvironment["APPIMAGE_EXTRACT_AND_RUN"] = "1"
  $stdoutPath = Join-Path $ValidationRoot "smoke.stdout.txt"
  $stderrPath = Join-Path $ValidationRoot "smoke.stderr.txt"
  $process = $null
  $successReason = $null

  Set-Content -Path $SmokeLog -Value ("[{0}] AppImage smoke validation" -f (Get-Date).ToString("o"))
  if ($leftovers.Count -gt 0) {
    Write-GpAppImageLogLine -LogPath $SmokeLog -Message ("Processes from an earlier smoke launch survived being stopped: {0}" -f [string]::Join(", ", @($leftovers)))
  }
  $preexistingAlerts = @(Get-GpAppImageSmokeAlertWindows -Process $null -Environment $smokeEnvironment | ForEach-Object { ([string]$_ -split ' ')[0] })
  Write-GpAppImageLogLine -LogPath $SmokeLog -Message ("Smoke mode: {0}" -f $smokePlan.Mode)
  if (-not [string]::IsNullOrWhiteSpace($smokePlan.DocumentPath)) {
    Write-GpAppImageLogLine -LogPath $SmokeLog -Message ("Smoke document path: {0}" -f $smokePlan.DocumentPath)
  }
  if ($smokePlan.MarkerPath -and (Test-Path $smokePlan.MarkerPath)) {
    Remove-Item -Force $smokePlan.MarkerPath
  }

  try {
    $process = Start-GpAppImageSmokeProcess `
      -ArtifactPath $Config.ArtifactPlan.ArtifactPath `
      -ArgumentList @($smokePlan.Arguments) `
      -Environment $smokeEnvironment `
      -StdOutPath $stdoutPath `
      -StdErrPath $stderrPath `
      -LogPath $SmokeLog

    switch ($smokePlan.Mode) {
      "marker-file" {
        $deadline = (Get-Date).AddSeconds([Math]::Max($ValidationPlan.TimeoutSeconds, 1))
        while ((Get-Date) -lt $deadline) {
          if ($smokePlan.MarkerPath -and (Test-Path $smokePlan.MarkerPath)) {
            $successReason = "marker-file-created"
            break
          }

          $process.Refresh()
          if ($process.HasExited) {
            if ([int]$process.ExitCode -ne 0) {
              throw "AppImage smoke launch failed with exit code $($process.ExitCode). See $SmokeLog."
            }
            if ($smokePlan.MarkerPath -and (Test-Path $smokePlan.MarkerPath)) {
              $successReason = "marker-file-created"
              break
            }
            throw "AppImage smoke launch did not create the expected marker file: $($smokePlan.MarkerPath)"
          }

          Start-Sleep -Milliseconds 200
        }

        if (-not $successReason) {
          if ($smokePlan.MarkerPath -and (Test-Path $smokePlan.MarkerPath)) {
            $successReason = "marker-file-created"
          } else {
            throw "AppImage smoke launch did not create the expected marker file: $($smokePlan.MarkerPath)"
          }
        }
      }

      default {
        $startupWindow = [Math]::Min([Math]::Max($smokePlan.StartupSeconds, 1), [Math]::Max($ValidationPlan.TimeoutSeconds, 1))
        $deadline = (Get-Date).AddSeconds($startupWindow)
        while ((Get-Date) -lt $deadline) {
          $process.Refresh()
          if ($process.HasExited) {
            if ([int]$process.ExitCode -ne 0) {
              throw "AppImage smoke launch failed with exit code $($process.ExitCode). See $SmokeLog."
            }
            $successReason = "process-exited-cleanly"
            break
          }
          Start-Sleep -Milliseconds 200
        }

        if (-not $successReason) {
          $process.Refresh()
          if ($process.HasExited) {
            if ([int]$process.ExitCode -ne 0) {
              throw "AppImage smoke launch failed with exit code $($process.ExitCode). See $SmokeLog."
            }
            $successReason = "process-exited-cleanly"
          } else {
            $successReason = "process-remained-running-through-startup-window"
            $alertWindows = Get-GpAppImageSmokeAlertWindows -Process $process -Environment $smokeEnvironment -IgnoreWindowIds $preexistingAlerts
            if ($null -eq $alertWindows) {
              Write-GpAppImageLogLine -LogPath $SmokeLog -Message "Alert panel check skipped: no X display or no xwininfo."
            } elseif (@($alertWindows).Count -gt 0) {
              $alertList = [string]::Join(", ", @($alertWindows))
              Write-GpAppImageLogLine -LogPath $SmokeLog -Message ("Alert panel on screen at the end of startup: {0}" -f $alertList)
              if (-not $smokePlan.AllowStartupAlert) {
                throw ("AppImage smoke launch is showing a GNUstep alert panel ({0}). An uncaught exception shows a modal 'Critical Error' panel and logs nothing, so this usually means a startup failure; set backends.appimage.smoke.allowStartupAlert if the app shows an alert on purpose. See $SmokeLog." -f $alertList)
              }
            }
          }
        }
      }
    }
  } finally {
    $survivors = @(Stop-GpAppImageSmokeProcess -Process $process -GnustepHome ([string]$smokeEnvironment["GNUSTEP_HOME"]))
    if ($survivors.Count -gt 0) {
      Write-GpAppImageLogLine -LogPath $SmokeLog -Message ("Smoke processes still running after KILL: {0}" -f [string]::Join(", ", @($survivors)))
    }
    $completion = Complete-GpAppImageSmokeProcess -Process $process -StdOutPath $stdoutPath -StdErrPath $stderrPath -LogPath $SmokeLog
    Write-GpAppImageLogLine -LogPath $SmokeLog -Message ("Smoke process exit code: {0}" -f $completion.ExitCode)
  }

  $failure = Get-GpAppImageSmokeFailure -Output $completion.Output
  if ($null -ne $failure) {
    Write-GpAppImageLogLine -LogPath $SmokeLog -Message ("Smoke output shows a failure: {0}: {1}" -f $failure.Reason, $failure.Line)
    throw ("AppImage smoke launch failed: {0}: {1}. See $SmokeLog." -f $failure.Reason, $failure.Line)
  }

  Write-GpAppImageLogLine -LogPath $SmokeLog -Message ("Smoke validation succeeded: {0}" -f $successReason)
  return [pscustomobject]@{
    Mode = $smokePlan.Mode
    Outcome = $successReason
    MarkerPath = $smokePlan.MarkerPath
    DocumentPath = $smokePlan.DocumentPath
    SmokeLog = $SmokeLog
  }
}

function Invoke-GpAppImageValidation {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [switch]$DryRun,
    [switch]$RunSmoke,
    [string]$LogPath
  )

  $config = Get-GpAppImageConfig -Context $Context
  $workPaths = Get-GpAppImageWorkPaths -Context $Context -Config $config
  $validationPlan = Get-GpValidationPlan -Context $Context
  $backendSupport = Get-GpBackendSupport -Backend "appimage"

  if ($DryRun) {
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
      Ensure-GpDirectory -Path (Split-Path -Parent $LogPath) | Out-Null
      Set-Content -Path $LogPath -Value ("[{0}] AppImage validation dry-run" -f (Get-Date).ToString("o"))
    }

    return [pscustomobject]@{
      Backend = "appimage"
      Mode = "dry-run"
      ArtifactPath = $config.ArtifactPlan.ArtifactPath
      HostPlatform = $backendSupport.HostPlatform
      RequiredPlatform = $backendSupport.RequiredPlatform
      HostSupported = [bool]$backendSupport.Supported
      RunSmoke = [bool]$RunSmoke
      SmokeMode = $config.Smoke.Mode
      RuntimeClosureMode = $config.Validation.RuntimeClosure
      TimeoutSeconds = $validationPlan.TimeoutSeconds
      LogPath = $LogPath
    }
  }

  if (-not $backendSupport.Supported) {
    throw "AppImage validation requires host platform '$($backendSupport.RequiredPlatform)'. Current host: '$($backendSupport.HostPlatform)'."
  }

  if (-not (Test-Path $config.ArtifactPlan.ArtifactPath)) {
    throw "AppImage artifact not found: $($config.ArtifactPlan.ArtifactPath)"
  }

  Ensure-GpDirectory -Path (Split-Path -Parent $LogPath) | Out-Null
  $artifactBudgetLine = Assert-GpArtifactSizeBudget -Manifest $Context.Manifest -Backend "appimage" -ArtifactPath $config.ArtifactPlan.ArtifactPath
  if ($null -ne $artifactBudgetLine) {
    Write-GpAppImageLogLine -LogPath $LogPath -Message $artifactBudgetLine
  }
  $validationRoot = Split-Path -Parent $LogPath
  $extractLog = Join-Path $validationRoot "extract.log"
  $smokeLog = Join-Path $validationRoot "smoke.log"
  $runtimeClosureLog = Join-Path $validationRoot "runtime-closure.log"
  $expandedRoot = Expand-GpAppImageArtifact -ArtifactPath $config.ArtifactPlan.ArtifactPath -ExtractRoot $workPaths.ExtractRoot -LogPath $extractLog

  $requiredPaths = @(
    (Join-Path $expandedRoot "AppRun"),
    (Join-Path $expandedRoot $config.DesktopEntryName),
    (Join-Path $expandedRoot ("{0}.{1}" -f $config.IconName, $config.IconExtension)),
    (Join-Path $expandedRoot ".DirIcon"),
    (Join-Path $expandedRoot "usr"),
    (Resolve-GpPathRelativeToBase -BasePath (Join-Path $expandedRoot "usr") -Path $config.AppRootRelative),
    (Resolve-GpPathRelativeToBase -BasePath (Join-Path $expandedRoot "usr") -Path $config.RuntimeRootRelative),
    (Resolve-GpPathRelativeToBase -BasePath (Join-Path $expandedRoot "usr") -Path $config.MetadataRootRelative),
    (Join-Path $expandedRoot "usr/share/applications/$($config.DesktopEntryName)"),
    (Join-Path $expandedRoot ("usr/share/icons/hicolor/256x256/apps/{0}.{1}" -f $config.IconName, $config.IconExtension))
  )

  foreach ($requiredPath in @($requiredPaths)) {
    if (-not (Test-Path $requiredPath)) {
      throw "AppImage structural validation failed. Missing path: $requiredPath"
    }
  }

  $desktopIssues = @(Test-GpAppImageDesktopEntry -DesktopPath (Join-Path $expandedRoot $config.DesktopEntryName))
  if ($desktopIssues.Count -gt 0) {
    throw "AppImage desktop entry validation failed: $([string]::Join('; ', $desktopIssues))"
  }

  $desktopFileValidate = Get-Command desktop-file-validate -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($desktopFileValidate) {
    Invoke-GpAppImageExternalTool -FilePath $desktopFileValidate.Source -ArgumentList @((Join-Path $expandedRoot $config.DesktopEntryName)) -LogPath $LogPath
  }

  $runtimeClosureResult = Invoke-GpAppImageRuntimeClosureValidation -Config $config -ExpandedRoot $expandedRoot -LogPath $runtimeClosureLog
  $installedContract = Invoke-GpPackageContractAssertions -Context $Context -Scope "installed" -Backend "appimage" -RootPath $expandedRoot
  foreach ($line in @($installedContract.Lines)) {
    Write-GpAppImageLogLine -LogPath $LogPath -Message ("Installed contract: {0}" -f $line)
  }
  if ($installedContract.HasIssues) {
    throw "AppImage installed-result contract validation failed. See $LogPath."
  }
  $smokeResult = $null
  if ($RunSmoke -or $validationPlan.Enabled) {
    $smokeResult = Invoke-GpAppImageSmoke -Context $Context -Config $config -ValidationPlan $validationPlan -ValidationRoot $validationRoot -SmokeLog $smokeLog
  }

  Write-GpAppImageLogLine -LogPath $LogPath -Message ("Validated AppImage artifact: {0}" -f $config.ArtifactPlan.ArtifactPath)
  return [pscustomobject]@{
    Backend = "appimage"
    Mode = "execute"
    ArtifactPath = $config.ArtifactPlan.ArtifactPath
    ExpandedRoot = $expandedRoot
    ExtractLog = $extractLog
    RuntimeClosureLog = $runtimeClosureLog
    RuntimeClosureMode = $(if ($runtimeClosureResult) { $runtimeClosureResult.Mode } else { $null })
    RuntimeClosureFilesChecked = $(if ($runtimeClosureResult) { $runtimeClosureResult.CheckedFileCount } else { 0 })
    RuntimeClosureDynamicFiles = $(if ($runtimeClosureResult) { $runtimeClosureResult.DynamicFileCount } else { 0 })
    SmokeLog = $smokeLog
    SmokeMode = $(if ($smokeResult) { $smokeResult.Mode } else { $null })
    SmokeOutcome = $(if ($smokeResult) { $smokeResult.Outcome } else { $null })
    SmokeMarkerPath = $(if ($smokeResult) { $smokeResult.MarkerPath } else { $null })
    SmokeDocumentPath = $(if ($smokeResult) { $smokeResult.DocumentPath } else { $null })
    LogPath = $LogPath
  }
}
