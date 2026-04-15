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

  if ((Get-Item $source) -is [System.IO.DirectoryInfo]) {
    Copy-Item -Recurse -Force $source $destination
  } else {
    Ensure-GpDirectory -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -Force $source $destination
  }

  return $destination
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
  }
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
    [string]$LogPath
  )

  $package = $Context.Manifest["package"]
  $entries = @(Get-GpAppImageRuntimeNoticeEntries -Context $Context -AppDirRoot $AppDirRoot)
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
  $lines.Add('  export FONTCONFIG_PATH="$RUNTIME_ROOT/etc/fonts"') | Out-Null
  $lines.Add("fi") | Out-Null

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

      default {
        throw "Unsupported AppImage launch environment policy '$policy' for key '$key'."
      }
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

  $mimeEntries = @(Get-GpAppImageMimeEntries -Context $Context -Config $Config)
  $mimePackagePath = Write-GpAppImageMimePackage -Config $Config -AppDirRoot $WorkPaths.AppDirRoot -MimeEntries $mimeEntries -LogPath $LogPath
  $desktopEntry = Write-GpAppImageDesktopEntry -Context $Context -Config $Config -AppDirRoot $WorkPaths.AppDirRoot -MimeEntries $mimeEntries -LogPath $LogPath
  $iconAssets = Copy-GpAppImageIconAssets -Context $Context -Config $Config -AppDirRoot $WorkPaths.AppDirRoot -LogPath $LogPath
  $appRunPath = Write-GpAppImageAppRun -Context $Context -Config $Config -AppDirRoot $WorkPaths.AppDirRoot -LogPath $LogPath
  $noticeReport = Write-GpAppImageNoticeReport -Context $Context -Config $Config -AppDirRoot $WorkPaths.AppDirRoot -LogPath $LogPath
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
  $diagnosticsPath = Write-GpAppImageDiagnosticsSummary -Context $Context -Config $config -AppDir $appDir -MetadataPath $metadataPath -LogPath $LogPath

  return [pscustomobject]@{
    Backend = "appimage"
    ManifestPath = $Context.ManifestPath
    ArtifactPath = $artifacts.ArtifactPath
    ZsyncArtifactPath = $artifacts.ZsyncArtifactPath
    MetadataPath = $metadataPath
    UpdateFeedPath = $updateFeedPath
    DiagnosticsPath = $diagnosticsPath
    AppDirRoot = $appDir.AppDirRoot
    AppRunPath = $appDir.AppRunPath
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

  Write-GpAppImageLogLine -LogPath $LogPath -Message ("RUN env {0}" -f ([string]::Join(" ", @($commandParts.ToArray()))))
  return (Start-Process -FilePath "env" -ArgumentList @($commandParts.ToArray()) -PassThru -RedirectStandardOutput $StdOutPath -RedirectStandardError $StdErrPath)
}

function Stop-GpAppImageSmokeProcess {
  param(
    [AllowNull()]
    [System.Diagnostics.Process]$Process
  )

  if ($null -eq $Process) {
    return
  }

  try {
    $Process.Refresh()
    if (-not $Process.HasExited) {
      Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
      $Process.WaitForExit(5000) | Out-Null
    }
  } catch {
  }
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
        Add-Content -Path $LogPath -Value ""
        Add-Content -Path $LogPath -Value ("[{0}]" -f $stream.Label)
        Add-Content -Path $LogPath -Value $content
      }
      Remove-Item -Force $stream.Path
    }
  }

  return $exitCode
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
  $smokeEnvironment = [hashtable](Copy-GpValue -Value $smokePlan.Environment)
  $smokeEnvironment["APPIMAGE_EXTRACT_AND_RUN"] = "1"
  $stdoutPath = Join-Path $ValidationRoot "smoke.stdout.txt"
  $stderrPath = Join-Path $ValidationRoot "smoke.stderr.txt"
  $process = $null
  $successReason = $null

  Set-Content -Path $SmokeLog -Value ("[{0}] AppImage smoke validation" -f (Get-Date).ToString("o"))
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
          }
        }
      }
    }
  } finally {
    Stop-GpAppImageSmokeProcess -Process $process
    $exitCode = Complete-GpAppImageSmokeProcess -Process $process -StdOutPath $stdoutPath -StdErrPath $stderrPath -LogPath $SmokeLog
    Write-GpAppImageLogLine -LogPath $SmokeLog -Message ("Smoke process exit code: {0}" -f $exitCode)
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
