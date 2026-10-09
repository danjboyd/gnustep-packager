Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# macOS DMG backend. Packages the staged `<appRoot>/<Name>.app` bundle into a
# compressed, read-only disk image with Apple's own tools (hdiutil, codesign,
# ditto, osascript, xcrun notarytool/stapler). See docs/dmg-backend.md.

function Write-GpDmgLogLine {
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

function Get-GpDmgDiagnosticsDocPath {
  return (Join-Path (Get-GpToolRoot) "docs/dmg-backend.md")
}

function Get-GpDmgAssetPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  return (Join-Path (Get-GpToolRoot) ("backends/dmg/assets/{0}" -f $Name))
}

function Get-GpDmgSection {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Parent,
    [Parameter(Mandatory = $true)]
    [string]$Key
  )

  if ($Parent.Contains($Key) -and ($Parent[$Key] -is [System.Collections.IDictionary])) {
    return $Parent[$Key]
  }

  return @{}
}

function Get-GpDmgValue {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Parent,
    [Parameter(Mandatory = $true)]
    [string]$Key,
    [AllowNull()]
    [object]$Default
  )

  if ($Parent.Contains($Key) -and $null -ne $Parent[$Key]) {
    if (($Parent[$Key] -is [string]) -and [string]::IsNullOrWhiteSpace([string]$Parent[$Key])) {
      return $Default
    }
    return $Parent[$Key]
  }

  return $Default
}

# Runs a native tool, appends its combined output to the log and returns it.
# Throws on a non-zero exit code unless -AllowFailure is given.
function Invoke-GpDmgTool {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [AllowEmptyCollection()]
    [string[]]$ArgumentList = @(),
    [string]$LogPath,
    [switch]$AllowFailure,
    [switch]$Quiet
  )

  Write-GpDmgLogLine -LogPath $LogPath -Message ("RUN {0} {1}" -f $FilePath, ([string]::Join(" ", @($ArgumentList))))
  $global:LASTEXITCODE = 0
  $output = @(& $FilePath @ArgumentList 2>&1 | ForEach-Object { [string]$_ })
  $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }

  if (-not [string]::IsNullOrWhiteSpace($LogPath) -and $output.Count -gt 0) {
    Add-Content -Path $LogPath -Value $output
  }
  if (-not $Quiet) {
    foreach ($line in $output) {
      Write-Host $line
    }
  }
  Write-GpDmgLogLine -LogPath $LogPath -Message ("EXIT {0}" -f $exitCode)

  if (($exitCode -ne 0) -and -not $AllowFailure) {
    $detail = [string]::Join(" ", @($output | Select-Object -Last 5))
    throw ("{0} failed with exit code {1}: {2} See log: {3}" -f (Split-Path -Leaf $FilePath), $exitCode, $detail, $LogPath)
  }

  return [pscustomobject]@{
    ExitCode = $exitCode
    Output = [string[]]$output
    Text = [string]::Join([Environment]::NewLine, $output)
  }
}

# Starts a process with a hard timeout; the process is killed when the timeout
# expires. Used for osascript (Finder can block) and the launch smoke.
function Invoke-GpDmgProcessWithTimeout {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [AllowEmptyCollection()]
    [string[]]$ArgumentList = @(),
    [Parameter(Mandatory = $true)]
    [int]$TimeoutSeconds,
    [hashtable]$Environment = @{},
    [string]$WorkingDirectory,
    [switch]$KillOnTimeoutIsSuccess
  )

  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $FilePath
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
    $startInfo.WorkingDirectory = $WorkingDirectory
  }
  foreach ($argument in @($ArgumentList)) {
    $startInfo.ArgumentList.Add([string]$argument) | Out-Null
  }
  foreach ($key in @($Environment.Keys)) {
    $startInfo.Environment[[string]$key] = [string]$Environment[$key]
  }

  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  if (-not $process.Start()) {
    throw "Failed to start: $FilePath"
  }

  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  $timedOut = -not $process.WaitForExit([Math]::Max($TimeoutSeconds, 1) * 1000)
  if ($timedOut) {
    try {
      $process.Kill($true)
    } catch {
    }
    $process.WaitForExit(5000) | Out-Null
  } else {
    $process.WaitForExit()
  }

  $exitCode = $null
  try {
    if ($process.HasExited) {
      $exitCode = [int]$process.ExitCode
    }
  } catch {
  }

  $stdout = ""
  $stderr = ""
  try { $stdout = $stdoutTask.GetAwaiter().GetResult() } catch { }
  try { $stderr = $stderrTask.GetAwaiter().GetResult() } catch { }

  return [pscustomobject]@{
    ExitCode = $exitCode
    TimedOut = [bool]$timedOut
    ProcessId = $process.Id
    StdOut = [string]$stdout
    StdErr = [string]$stderr
  }
}

function Read-GpDmgPlistValue {
  param(
    [Parameter(Mandatory = $true)]
    [string]$PlistPath,
    [Parameter(Mandatory = $true)]
    [string]$Key
  )

  $global:LASTEXITCODE = 0
  $value = & plutil -extract $Key raw -o - $PlistPath 2>$null
  if ($LASTEXITCODE -ne 0) {
    return $null
  }

  return ([string]$value).Trim()
}

function Convert-GpDmgPlistTextToObject {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$PlistText
  )

  $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-dmg-{0}.plist" -f [guid]::NewGuid().ToString("N"))
  try {
    # hdiutil may print informational lines before the XML document.
    $start = $PlistText.IndexOf("<?xml")
    $xml = if ($start -ge 0) { $PlistText.Substring($start) } else { $PlistText }
    Set-Content -Path $tempPath -Value $xml -Encoding utf8 -NoNewline
    $global:LASTEXITCODE = 0
    $json = & plutil -convert json -r -o - $tempPath 2>&1
    if ($LASTEXITCODE -ne 0) {
      throw "Could not parse plist output: $([string]::Join(' ', @($json)))"
    }
    return ([string]::Join([Environment]::NewLine, @($json)) | ConvertFrom-Json)
  } finally {
    if (Test-Path $tempPath) {
      Remove-Item -Force $tempPath
    }
  }
}

function Get-GpDmgArchToken {
  param(
    [AllowEmptyCollection()]
    [string[]]$Archs = @()
  )

  $normalized = @($Archs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() } | Sort-Object -Unique)
  if ($normalized.Count -eq 0) {
    return "unknown"
  }

  $hasArm = @($normalized | Where-Object { $_ -like "arm64*" }).Count -gt 0
  $hasIntel = @($normalized | Where-Object { $_ -like "x86_64*" }).Count -gt 0
  if ($hasArm -and $hasIntel) {
    return "universal"
  }
  if ($normalized.Count -eq 1) {
    return [string]$normalized[0]
  }

  return [string]::Join("-", $normalized)
}

function Get-GpDmgAppBundleInfo {
  param(
    [Parameter(Mandatory = $true)]
    [string]$AppPath
  )

  $infoPlistPath = Join-Path $AppPath "Contents/Info.plist"
  $exists = Test-Path -LiteralPath $AppPath -PathType Container
  $hasInfoPlist = Test-Path -LiteralPath $infoPlistPath -PathType Leaf
  $executable = $null
  $executablePath = $null
  $archs = @()

  if ($hasInfoPlist) {
    $executable = Read-GpDmgPlistValue -PlistPath $infoPlistPath -Key "CFBundleExecutable"
  }
  if (-not [string]::IsNullOrWhiteSpace($executable)) {
    $executablePath = Join-Path $AppPath ("Contents/MacOS/{0}" -f $executable)
    if (Test-Path -LiteralPath $executablePath -PathType Leaf) {
      $global:LASTEXITCODE = 0
      $lipoOutput = & lipo -archs $executablePath 2>$null
      if ($LASTEXITCODE -eq 0) {
        $archs = @(([string]$lipoOutput).Trim() -split "\s+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
      }
    }
  }

  return [pscustomobject]@{
    Path = $AppPath
    Exists = [bool]$exists
    InfoPlistPath = $infoPlistPath
    HasInfoPlist = [bool]$hasInfoPlist
    Executable = $executable
    ExecutablePath = $executablePath
    HasExecutable = [bool](-not [string]::IsNullOrWhiteSpace($executablePath) -and (Test-Path -LiteralPath $executablePath -PathType Leaf))
    BundleIdentifier = $(if ($hasInfoPlist) { Read-GpDmgPlistValue -PlistPath $infoPlistPath -Key "CFBundleIdentifier" } else { $null })
    ShortVersion = $(if ($hasInfoPlist) { Read-GpDmgPlistValue -PlistPath $infoPlistPath -Key "CFBundleShortVersionString" } else { $null })
    BundleVersion = $(if ($hasInfoPlist) { Read-GpDmgPlistValue -PlistPath $infoPlistPath -Key "CFBundleVersion" } else { $null })
    MinimumSystemVersion = $(if ($hasInfoPlist) { Read-GpDmgPlistValue -PlistPath $infoPlistPath -Key "LSMinimumSystemVersion" } else { $null })
    Archs = [string[]]@($archs)
    ArchToken = Get-GpDmgArchToken -Archs @($archs)
  }
}

# Reads `codesign -dv` for a bundle or image. Never throws.
function Get-GpDmgSignatureInfo {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $global:LASTEXITCODE = 0
  $output = @(& codesign -dv --verbose=4 $Path 2>&1 | ForEach-Object { [string]$_ })
  $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
  $text = [string]::Join("`n", $output)
  $authorities = @($output | Where-Object { $_ -like "Authority=*" } | ForEach-Object { $_.Substring("Authority=".Length) })
  $flags = $null
  if ($text -match "(?m)^CodeDirectory .*flags=\S+\(([^)]*)\)") {
    $flags = $Matches[1]
  }
  $teamId = $null
  if ($text -match "(?m)^TeamIdentifier=(.+)$") {
    $teamId = $Matches[1].Trim()
  }
  $identifier = $null
  if ($text -match "(?m)^Identifier=(.+)$") {
    $identifier = $Matches[1].Trim()
  }
  $signed = ($exitCode -eq 0) -and ($text -notmatch "not signed at all")
  $adHoc = $signed -and (($text -match "(?m)^Signature=adhoc") -or ($null -ne $flags -and $flags -match "adhoc"))

  return [pscustomobject]@{
    Path = $Path
    Signed = [bool]$signed
    AdHoc = [bool]$adHoc
    Identifier = $identifier
    TeamIdentifier = $teamId
    Authorities = [string[]]@($authorities)
    Flags = $flags
    HardenedRuntime = [bool]($null -ne $flags -and $flags -match "runtime")
    Raw = $text
  }
}

function Get-GpDmgConfig {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context
  )

  $manifest = $Context.Manifest
  $package = $manifest["package"]
  $payload = $manifest["payload"]
  $backend = $manifest["backends"]["dmg"]
  $outputPaths = Get-GpOutputPaths -Context $Context
  $window = Get-GpDmgSection -Parent $backend -Key "window"
  $signing = Get-GpDmgSection -Parent $backend -Key "signing"
  $notarization = Get-GpDmgSection -Parent $backend -Key "notarization"
  $validation = Get-GpDmgSection -Parent $backend -Key "validation"
  $smoke = Get-GpDmgSection -Parent $backend -Key "smoke"
  $noticeReport = Get-GpDmgSection -Parent $backend -Key "noticeReport"

  $displayName = Get-GpPackageDisplayName -Manifest $manifest
  $tokens = @{
    name = [string]$package["name"]
    version = [string]$package["version"]
    packageId = [string]$package["id"]
    backend = "dmg"
  }

  $stageRoot = Resolve-GpManifestPath -Context $Context -RelativePath ([string]$payload["stageRoot"])
  $appRootPath = Resolve-GpPathRelativeToBase -BasePath $stageRoot -Path ([string]$payload["appRoot"])
  $appBundleName = Resolve-GpPatternTokens -Pattern ([string](Get-GpDmgValue -Parent $backend -Key "appBundleName" -Default "{name}.app")) -Tokens $tokens
  $stagedAppPath = Join-Path $appRootPath $appBundleName
  $appInfo = Get-GpDmgAppBundleInfo -AppPath $stagedAppPath

  $artifactTokens = Copy-GpValue -Value $tokens
  $artifactTokens["arch"] = $appInfo.ArchToken
  $artifactName = Resolve-GpPatternTokens -Pattern ([string](Get-GpDmgValue -Parent $backend -Key "artifactNamePattern" -Default "{name}-{version}-macos-{arch}.dmg")) -Tokens $artifactTokens
  $artifactPath = Join-Path $outputPaths.PackageRoot $artifactName

  $volumeName = [string](Get-GpDmgValue -Parent $backend -Key "volumeName" -Default $displayName)
  $volumeName = Resolve-GpPatternTokens -Pattern $volumeName -Tokens $tokens

  $backgroundRelative = [string](Get-GpDmgValue -Parent $backend -Key "backgroundImageRelativePath" -Default "")
  $backgroundPath = if (-not [string]::IsNullOrWhiteSpace($backgroundRelative)) {
    Resolve-GpPathRelativeToBase -BasePath $stageRoot -Path $backgroundRelative
  } else {
    $null
  }

  $identity = [string](Get-GpDmgValue -Parent $signing -Key "identity" -Default "-")
  $entitlementsRelative = [string](Get-GpDmgValue -Parent $signing -Key "entitlementsPath" -Default "")
  $entitlementsPath = if (-not [string]::IsNullOrWhiteSpace($entitlementsRelative)) {
    Resolve-GpManifestPath -Context $Context -RelativePath $entitlementsRelative
  } else {
    $null
  }

  function Get-GpDmgPosition {
    param([System.Collections.IDictionary]$Section, [string]$Key, [int]$X, [int]$Y)
    $position = Get-GpDmgSection -Parent $Section -Key $Key
    return [pscustomobject]@{
      X = [int](Get-GpDmgValue -Parent $position -Key "x" -Default $X)
      Y = [int](Get-GpDmgValue -Parent $position -Key "y" -Default $Y)
    }
  }

  $finderLayout = [string](Get-GpDmgValue -Parent $backend -Key "finderLayout" -Default "auto")
  if (-not [string]::IsNullOrWhiteSpace($env:GP_DMG_FINDER_LAYOUT)) {
    $finderLayout = $env:GP_DMG_FINDER_LAYOUT.Trim().ToLowerInvariant()
    if ($finderLayout -notin @("auto", "applescript", "off")) {
      throw "GP_DMG_FINDER_LAYOUT must be one of: auto, applescript, off."
    }
  }

  return [pscustomobject]@{
    PackageId = [string]$package["id"]
    PackageName = [string]$package["name"]
    DisplayName = $displayName
    Version = [string]$package["version"]
    Manufacturer = [string]$package["manufacturer"]
    Homepage = $(if ($package.Contains("homepage")) { [string]$package["homepage"] } else { $null })
    License = $(if ($package.Contains("license")) { [string]$package["license"] } else { $null })
    StageRoot = $stageRoot
    AppRootRelative = [string]$payload["appRoot"]
    MetadataRootRelative = [string]$payload["metadataRoot"]
    AppBundleName = $appBundleName
    StagedAppPath = $stagedAppPath
    AppInfo = $appInfo
    ArtifactName = $artifactName
    ArtifactPath = $artifactPath
    OutputPaths = $outputPaths
    VolumeName = $volumeName
    Filesystem = [string](Get-GpDmgValue -Parent $backend -Key "filesystem" -Default "APFS")
    Format = [string](Get-GpDmgValue -Parent $backend -Key "format" -Default "UDZO")
    ApplicationsLink = [bool](Get-GpDmgValue -Parent $backend -Key "applicationsLink" -Default $true)
    BackgroundRelativePath = $(if ([string]::IsNullOrWhiteSpace($backgroundRelative)) { $null } else { $backgroundRelative })
    BackgroundPath = $backgroundPath
    BackgroundFileName = $(if ($backgroundPath) { Split-Path -Leaf $backgroundPath } else { $null })
    FinderLayout = $finderLayout
    FinderLayoutTimeoutSeconds = [int](Get-GpDmgValue -Parent $backend -Key "finderLayoutTimeoutSeconds" -Default 60)
    Window = [pscustomobject]@{
      X = [int](Get-GpDmgValue -Parent $window -Key "x" -Default 200)
      Y = [int](Get-GpDmgValue -Parent $window -Key "y" -Default 120)
      Width = [int](Get-GpDmgValue -Parent $window -Key "width" -Default 600)
      Height = [int](Get-GpDmgValue -Parent $window -Key "height" -Default 400)
      IconSize = [int](Get-GpDmgValue -Parent $window -Key "iconSize" -Default 128)
      TextSize = [int](Get-GpDmgValue -Parent $window -Key "textSize" -Default 12)
      AppIcon = Get-GpDmgPosition -Section $window -Key "appIconPosition" -X 150 -Y 190
      ApplicationsIcon = Get-GpDmgPosition -Section $window -Key "applicationsIconPosition" -X 450 -Y 190
      NoticeIcon = Get-GpDmgPosition -Section $window -Key "noticeIconPosition" -X 300 -Y 330
    }
    NoticeReport = [pscustomobject]@{
      Enabled = [bool](Get-GpDmgValue -Parent $noticeReport -Key "enabled" -Default $false)
      FileName = Get-GpNoticeReportRelativePath -Manifest $manifest -Backend "dmg"
    }
    Signing = [pscustomobject]@{
      Identity = $identity
      IsAdHoc = [bool]($identity -eq "-")
      Resign = [bool](Get-GpDmgValue -Parent $signing -Key "resign" -Default $false)
      Deep = [bool](Get-GpDmgValue -Parent $signing -Key "deep" -Default $true)
      HardenedRuntime = [bool](Get-GpDmgValue -Parent $signing -Key "hardenedRuntime" -Default $true)
      EntitlementsRelativePath = $(if ([string]::IsNullOrWhiteSpace($entitlementsRelative)) { $null } else { $entitlementsRelative })
      EntitlementsPath = $entitlementsPath
      Keychain = [string](Get-GpDmgValue -Parent $signing -Key "keychain" -Default "")
      SignDmg = [bool](Get-GpDmgValue -Parent $signing -Key "signDmg" -Default $true)
      AdditionalArguments = [string[]]@(Get-GpDmgValue -Parent $signing -Key "additionalArguments" -Default @())
    }
    Notarization = [pscustomobject]@{
      Enabled = [bool](Get-GpDmgValue -Parent $notarization -Key "enabled" -Default $false)
      KeychainProfileEnvVar = [string](Get-GpDmgValue -Parent $notarization -Key "keychainProfileEnvVar" -Default "GP_NOTARY_KEYCHAIN_PROFILE")
      Staple = [bool](Get-GpDmgValue -Parent $notarization -Key "staple" -Default $true)
      Required = [bool](Get-GpDmgValue -Parent $notarization -Key "required" -Default $false)
    }
    Validation = [pscustomobject]@{
      RequireSignature = [bool](Get-GpDmgValue -Parent $validation -Key "requireSignature" -Default $true)
      RequireGatekeeperAcceptance = [bool](Get-GpDmgValue -Parent $validation -Key "requireGatekeeperAcceptance" -Default $false)
    }
    Smoke = [pscustomobject]@{
      Enabled = [bool](Get-GpDmgValue -Parent $smoke -Key "enabled" -Default $false)
      StartupSeconds = [int](Get-GpDmgValue -Parent $smoke -Key "startupSeconds" -Default 5)
      Arguments = [string[]]@(Get-GpDmgValue -Parent $smoke -Key "arguments" -Default @())
      Environment = $(if ($smoke.Contains("environment") -and ($smoke["environment"] -is [System.Collections.IDictionary])) {
        [hashtable](Copy-GpValue -Value $smoke["environment"])
      } else {
        @{}
      })
    }
    Sidecars = [pscustomobject]@{
      MetadataPath = Get-GpArtifactSidecarPath -ArtifactPath $artifactPath -Suffix "metadata.json"
      DiagnosticsPath = Get-GpArtifactSidecarPath -ArtifactPath $artifactPath -Suffix "diagnostics.txt"
    }
  }
}

function Get-GpDmgWorkPaths {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Config
  )

  $workRoot = Join-Path (Join-Path $Config.OutputPaths.TempRoot "dmg") (New-GpTimestamp)
  return [pscustomobject]@{
    Root = $workRoot
    VolumeRoot = Join-Path $workRoot "volume"
    ReadWriteImage = Join-Path $workRoot "readwrite.dmg"
    LayoutLog = Join-Path $workRoot "finder-layout.log"
  }
}

# Lists manifest settings that the DMG backend does not render. A native macOS
# app bundle carries its own launch behavior (Info.plist, the executable), so
# the GNUstep launch contract, packaged defaults and theme inputs do not apply.
function Get-GpDmgIgnoredSettings {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context
  )

  $manifest = $Context.Manifest
  $notes = [System.Collections.Generic.List[string]]::new()
  $launch = $manifest["launch"]

  if ($launch.Contains("env") -and ($launch["env"] -is [System.Collections.IDictionary]) -and @($launch["env"].Keys).Count -gt 0) {
    $notes.Add(("launch.env ({0}) is not rendered: a macOS app bundle has no generated launcher." -f ([string]::Join(", ", @($launch["env"].Keys | Sort-Object))))) | Out-Null
  }
  foreach ($key in @("pathPrepend", "resourceRoots", "arguments")) {
    if ($launch.Contains($key) -and @($launch[$key] | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
      $notes.Add(("launch.{0} is not rendered: a macOS app bundle has no generated launcher." -f $key)) | Out-Null
    }
  }

  $packagedDefaults = Get-GpPackagedDefaults -Manifest $manifest
  if (-not [string]::IsNullOrWhiteSpace([string]$packagedDefaults.DefaultTheme) -or $null -ne $packagedDefaults.AppDomain) {
    $notes.Add("packagedDefaults is not rendered: seed first-run defaults from the app itself (NSUserDefaults registerDefaults:).") | Out-Null
  }

  if (@(Get-GpThemeInputs -Manifest $manifest -Backend "dmg" -ActiveOnly).Count -gt 0) {
    $notes.Add("themeInputs that apply to macos are not provisioned into a native app bundle.") | Out-Null
  }

  $updates = Get-GpUpdateSettings -Context $Context -Backend "dmg"
  if ($updates.Enabled) {
    $notes.Add("updates.enabled is set, but the DMG backend does not emit updater runtime config or update-feed sidecars yet.") | Out-Null
  }

  return [string[]]@($notes.ToArray())
}

function Copy-GpDmgAppBundle {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Source,
    [Parameter(Mandatory = $true)]
    [string]$Destination,
    [string]$LogPath
  )

  if (Test-Path -LiteralPath $Destination) {
    Remove-Item -Recurse -Force -LiteralPath $Destination
  }
  Ensure-GpDirectory -Path (Split-Path -Parent $Destination) | Out-Null
  # ditto keeps symlinks, extended attributes, resource forks and the code
  # signature intact; Copy-Item does not.
  Invoke-GpDmgTool -FilePath "ditto" -ArgumentList @($Source, $Destination) -LogPath $LogPath -Quiet | Out-Null
}

function Invoke-GpDmgCodesignApp {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [string]$AppPath,
    [string]$LogPath
  )

  $signing = $Config.Signing
  $arguments = [System.Collections.Generic.List[string]]::new()
  $arguments.Add("--force") | Out-Null
  if ($signing.Deep) {
    $arguments.Add("--deep") | Out-Null
  }
  if ($signing.HardenedRuntime) {
    $arguments.Add("--options") | Out-Null
    $arguments.Add("runtime") | Out-Null
  }
  # A secure timestamp needs a real identity and network access; ad-hoc
  # signatures cannot carry one.
  if ($signing.IsAdHoc) {
    $arguments.Add("--timestamp=none") | Out-Null
  } else {
    $arguments.Add("--timestamp") | Out-Null
  }
  if (-not [string]::IsNullOrWhiteSpace($signing.EntitlementsPath)) {
    if (-not (Test-Path -LiteralPath $signing.EntitlementsPath -PathType Leaf)) {
      throw "Configured backends.dmg.signing.entitlementsPath does not exist: $($signing.EntitlementsPath)"
    }
    $arguments.Add("--entitlements") | Out-Null
    $arguments.Add($signing.EntitlementsPath) | Out-Null
  }
  if (-not [string]::IsNullOrWhiteSpace($signing.Keychain)) {
    $arguments.Add("--keychain") | Out-Null
    $arguments.Add($signing.Keychain) | Out-Null
  }
  foreach ($argument in @($signing.AdditionalArguments)) {
    if (-not [string]::IsNullOrWhiteSpace($argument)) {
      $arguments.Add([string]$argument) | Out-Null
    }
  }
  $arguments.Add("--sign") | Out-Null
  $arguments.Add($signing.Identity) | Out-Null
  $arguments.Add($AppPath) | Out-Null

  Write-GpDmgLogLine -LogPath $LogPath -Message ("Signing app bundle with identity '{0}'" -f $signing.Identity)
  Invoke-GpDmgTool -FilePath "codesign" -ArgumentList @($arguments.ToArray()) -LogPath $LogPath -Quiet | Out-Null
}

function Test-GpDmgCodesignVerify {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [string]$LogPath,
    [switch]$Deep
  )

  $arguments = @("--verify", "--strict", "--verbose=2")
  if ($Deep) {
    $arguments = @("--verify", "--deep", "--strict", "--verbose=2")
  }
  $result = Invoke-GpDmgTool -FilePath "codesign" -ArgumentList @($arguments + @($Path)) -LogPath $LogPath -AllowFailure -Quiet
  return [pscustomobject]@{
    Passed = [bool]($result.ExitCode -eq 0)
    ExitCode = $result.ExitCode
    Output = $result.Text
  }
}

function Write-GpDmgNoticeReport {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [string]$VolumeRoot,
    [string]$LogPath
  )

  $package = $Context.Manifest["package"]
  $entries = [System.Collections.Generic.List[psobject]]::new()
  foreach ($entry in @(Get-GpComplianceEntries -Manifest $Context.Manifest)) {
    $stageRelativePath = if ($entry.ContainsKey("stageRelativePath") -and -not [string]::IsNullOrWhiteSpace([string]$entry["stageRelativePath"])) { [string]$entry["stageRelativePath"] } else { $null }
    $stagedPath = $null
    if ($stageRelativePath) {
      $stagedPath = Resolve-GpPathRelativeToBase -BasePath $Config.StageRoot -Path $stageRelativePath
      if (-not (Test-Path -LiteralPath $stagedPath -PathType Leaf)) {
        throw "Configured compliance.runtimeNotices entry '$($entry["name"])' references a missing staged file: $stagedPath"
      }
    }
    $entries.Add([pscustomobject]@{
      Name = [string]$entry["name"]
      Version = $(if ($entry.ContainsKey("version")) { [string]$entry["version"] } else { $null })
      License = $(if ($entry.ContainsKey("license")) { [string]$entry["license"] } else { $null })
      Source = $(if ($entry.ContainsKey("source")) { [string]$entry["source"] } else { $null })
      Homepage = $(if ($entry.ContainsKey("homepage")) { [string]$entry["homepage"] } else { $null })
      StageRelativePath = $stageRelativePath
      StagedPath = $stagedPath
    }) | Out-Null
  }

  # The staged license files are not copied onto the volume, so the report
  # carries their text inline.
  $lines = [System.Collections.Generic.List[string]]::new()
  $lines.Add(("Package: {0}" -f [string]$package["name"])) | Out-Null
  $lines.Add(("Version: {0}" -f [string]$package["version"])) | Out-Null
  $lines.Add(("Manufacturer: {0}" -f [string]$package["manufacturer"])) | Out-Null
  $lines.Add("") | Out-Null
  $lines.Add(("Runtime notice entries: {0}" -f $entries.Count)) | Out-Null
  foreach ($entry in $entries) {
    $lines.Add("") | Out-Null
    $lines.Add(("[{0}]" -f $entry.Name)) | Out-Null
    foreach ($field in @("Version", "License", "Source", "Homepage")) {
      if (-not [string]::IsNullOrWhiteSpace([string]$entry.$field)) {
        $lines.Add(("{0}: {1}" -f $field, $entry.$field)) | Out-Null
      }
    }
    if ($entry.StagedPath) {
      $lines.Add("") | Out-Null
      foreach ($textLine in @(Get-Content -LiteralPath $entry.StagedPath)) {
        $lines.Add([string]$textLine) | Out-Null
      }
    }
  }

  $reportPath = Join-Path $VolumeRoot $Config.NoticeReport.FileName
  Ensure-GpDirectory -Path (Split-Path -Parent $reportPath) | Out-Null
  Set-Content -Path $reportPath -Value $lines -Encoding utf8
  Write-GpDmgLogLine -LogPath $LogPath -Message ("Generated notice report: {0}" -f $reportPath)
  return [pscustomobject]@{
    ReportPath = $reportPath
    Entries = @($entries.ToArray())
  }
}

function Get-GpDirectorySizeBytes {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $global:LASTEXITCODE = 0
  $output = & du -sk $Path 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$output)) {
    return 0
  }
  return ([long](([string]$output -split "\s+")[0])) * 1024
}

function Mount-GpDmgImage {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ImagePath,
    [string]$MountPoint,
    [switch]$ReadWrite,
    [switch]$Browse,
    [string]$LogPath
  )

  $arguments = [System.Collections.Generic.List[string]]::new()
  foreach ($item in @("attach", $ImagePath, "-plist", "-noautoopen", "-noverify")) {
    $arguments.Add($item) | Out-Null
  }
  if ($ReadWrite) {
    $arguments.Add("-readwrite") | Out-Null
  } else {
    $arguments.Add("-readonly") | Out-Null
  }
  if (-not $Browse) {
    $arguments.Add("-nobrowse") | Out-Null
  }
  if (-not [string]::IsNullOrWhiteSpace($MountPoint)) {
    Ensure-GpDirectory -Path $MountPoint | Out-Null
    $arguments.Add("-mountpoint") | Out-Null
    $arguments.Add($MountPoint) | Out-Null
  }

  $result = Invoke-GpDmgTool -FilePath "hdiutil" -ArgumentList @($arguments.ToArray()) -LogPath $LogPath -Quiet
  $plist = Convert-GpDmgPlistTextToObject -PlistText $result.Text
  $entities = @($plist."system-entities")
  $mounted = @($entities | Where-Object { $_.PSObject.Properties["mount-point"] -and -not [string]::IsNullOrWhiteSpace([string]$_."mount-point") })
  if ($mounted.Count -eq 0) {
    throw "hdiutil attach did not report a mount point for $ImagePath. See log: $LogPath"
  }

  # The image's own whole-disk node detaches every synthesized volume with it
  # (APFS images add a container disk on top of the image disk).
  $wholeDisks = @($entities | ForEach-Object { [string]$_."dev-entry" } | Where-Object { $_ -match '^/dev/disk\d+$' })
  $device = if ($wholeDisks.Count -gt 0) { $wholeDisks[0] } else { [string]$mounted[0]."dev-entry" }

  return [pscustomobject]@{
    ImagePath = $ImagePath
    MountPoint = [string]$mounted[0]."mount-point"
    Device = $device
    Devices = [string[]]@($entities | ForEach-Object { [string]$_."dev-entry" })
  }
}

function Dismount-GpDmgImage {
  param(
    [AllowNull()]
    [psobject]$Mount,
    [string]$LogPath
  )

  if ($null -eq $Mount) {
    return $true
  }

  foreach ($attempt in 1..5) {
    $arguments = @("detach", $Mount.Device)
    if ($attempt -ge 3) {
      $arguments += "-force"
    }
    $result = Invoke-GpDmgTool -FilePath "hdiutil" -ArgumentList $arguments -LogPath $LogPath -AllowFailure -Quiet
    if ($result.ExitCode -eq 0) {
      return $true
    }
    # Already gone (e.g. detached by an earlier attempt).
    if ($result.Text -match "No such file or directory|not currently mounted|no mounted") {
      return $true
    }
    Start-Sleep -Seconds ([Math]::Min($attempt * 2, 6))
  }

  Write-GpDmgLogLine -LogPath $LogPath -Message ("WARN could not detach {0} ({1})" -f $Mount.Device, $Mount.MountPoint)
  return $false
}

# Decides whether the AppleScript Finder layout can run on this host without
# prompting anyone. Returns a reason when it should be skipped.
function Get-GpDmgFinderLayoutBlocker {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [string]$LogPath
  )

  if ($Config.FinderLayout -eq "off") {
    return "finderLayout is off"
  }

  if (-not (Get-Command osascript -ErrorAction SilentlyContinue)) {
    return "osascript is not available"
  }

  if ($Config.FinderLayout -eq "applescript") {
    return $null
  }

  if (-not [string]::IsNullOrWhiteSpace($env:CI)) {
    return "CI environment (set finderLayout to 'applescript' to force it on a runner with a GUI session)"
  }

  $global:LASTEXITCODE = 0
  $manager = [string](& launchctl managername 2>$null)
  if ($LASTEXITCODE -ne 0 -or $manager.Trim() -ne "Aqua") {
    return ("no Aqua GUI session (launchctl managername: '{0}')" -f $manager.Trim())
  }

  $checkScript = Get-GpDmgAssetPath -Name "finder-automation-check.swift"
  $global:LASTEXITCODE = 0
  $null = & xcrun --find swift 2>$null
  if ($LASTEXITCODE -eq 0 -and (Test-Path $checkScript)) {
    $check = Invoke-GpDmgProcessWithTimeout -FilePath "xcrun" -ArgumentList @("swift", $checkScript) -TimeoutSeconds 60
    $status = ([string]$check.StdOut).Trim()
    Write-GpDmgLogLine -LogPath $LogPath -Message ("Finder automation permission check: {0}" -f $(if ($status) { $status } else { "(no result) $($check.StdErr)" }))
    switch ($status) {
      "0" { return $null }
      "-1743" { return "Finder automation is denied for this terminal (System Settings > Privacy & Security > Automation)" }
      "-1744" { return "Finder automation would require a consent prompt; skipped to stay non-interactive" }
      "-600" { return "Finder is not running" }
    }
  }

  return $null
}

function Invoke-GpDmgFinderLayout {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [string]$MountPoint,
    [Parameter(Mandatory = $true)]
    [string]$LogPath,
    [Parameter(Mandatory = $true)]
    [string]$LayoutLog
  )

  $window = $Config.Window
  $arguments = @(
    (Get-GpDmgAssetPath -Name "finder-layout.applescript"),
    $MountPoint,
    $Config.AppBundleName,
    [string]$window.X,
    [string]$window.Y,
    [string]$window.Width,
    [string]$window.Height,
    [string]$window.IconSize,
    [string]$window.TextSize,
    [string]$window.AppIcon.X,
    [string]$window.AppIcon.Y,
    $(if ($Config.ApplicationsLink) { "Applications" } else { "" }),
    [string]$window.ApplicationsIcon.X,
    [string]$window.ApplicationsIcon.Y,
    $(if ($Config.BackgroundFileName) { $Config.BackgroundFileName } else { "" }),
    $(if ($Config.NoticeReport.Enabled) { $Config.NoticeReport.FileName } else { "" }),
    [string]$window.NoticeIcon.X,
    [string]$window.NoticeIcon.Y
  )

  Write-GpDmgLogLine -LogPath $LogPath -Message ("RUN osascript {0}" -f ([string]::Join(" ", $arguments)))
  $result = Invoke-GpDmgProcessWithTimeout -FilePath "osascript" -ArgumentList $arguments -TimeoutSeconds $Config.FinderLayoutTimeoutSeconds
  Set-Content -Path $LayoutLog -Value @(
    ("exit={0} timedOut={1}" -f $result.ExitCode, $result.TimedOut),
    "[stdout]", $result.StdOut, "[stderr]", $result.StdErr
  )

  if ($result.TimedOut) {
    return [pscustomobject]@{ Applied = $false; Reason = ("osascript timed out after {0}s" -f $Config.FinderLayoutTimeoutSeconds) }
  }
  if ($result.ExitCode -ne 0) {
    return [pscustomobject]@{ Applied = $false; Reason = ("osascript failed ({0}): {1}" -f $result.ExitCode, ([string]$result.StdErr).Trim()) }
  }

  # Finder writes .DS_Store asynchronously after the window closes.
  $dsStore = Join-Path $MountPoint ".DS_Store"
  $deadline = (Get-Date).AddSeconds(15)
  while (-not (Test-Path -LiteralPath $dsStore) -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
  }
  if (-not (Test-Path -LiteralPath $dsStore)) {
    return [pscustomobject]@{ Applied = $false; Reason = "Finder did not write .DS_Store" }
  }

  return [pscustomobject]@{ Applied = $true; Reason = "Finder wrote .DS_Store" }
}

function Invoke-GpDmgNotarization {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [string]$ArtifactPath,
    [string]$LogPath
  )

  $notarization = $Config.Notarization
  $result = [ordered]@{
    enabled = [bool]$notarization.Enabled
    status = "disabled"
    keychainProfileEnvVar = $notarization.KeychainProfileEnvVar
    submissionId = $null
    stapled = $false
    message = "Notarization is disabled (backends.dmg.notarization.enabled is false)."
  }

  if (-not $notarization.Enabled) {
    Write-GpDmgLogLine -LogPath $LogPath -Message $result.message
    return [pscustomobject]$result
  }

  $skipReason = $null
  $profileName = [Environment]::GetEnvironmentVariable($notarization.KeychainProfileEnvVar)
  $credentialsHint = ("Store credentials with 'xcrun notarytool store-credentials <profile>' and export {0}=<profile>." -f $notarization.KeychainProfileEnvVar)
  if ([string]::IsNullOrWhiteSpace($profileName)) {
    $result.status = "skipped-no-credentials"
    $skipReason = ("Notarization skipped: environment variable {0} is not set{1}. {2}" -f $notarization.KeychainProfileEnvVar, $(if ($Config.Signing.IsAdHoc) { ", and the signing identity is ad-hoc ('-')" } else { "" }), $credentialsHint)
  } elseif ($Config.Signing.IsAdHoc) {
    $result.status = "skipped-ad-hoc"
    $skipReason = "Notarization skipped: Apple only notarizes Developer ID-signed code and backends.dmg.signing.identity is ad-hoc ('-')."
  }

  if ($skipReason) {
    $result.message = $skipReason
    Write-GpDmgLogLine -LogPath $LogPath -Message $skipReason
    Write-Host $skipReason
    if ($notarization.Required) {
      throw ("{0} backends.dmg.notarization.required is true." -f $skipReason)
    }
    return [pscustomobject]$result
  }

  Write-GpDmgLogLine -LogPath $LogPath -Message ("Submitting {0} for notarization with keychain profile from {1}" -f $ArtifactPath, $notarization.KeychainProfileEnvVar)
  $submit = Invoke-GpDmgTool -FilePath "xcrun" -ArgumentList @("notarytool", "submit", $ArtifactPath, "--keychain-profile", $profileName, "--wait", "--output-format", "json") -LogPath $LogPath -AllowFailure -Quiet
  $submission = $null
  try {
    $jsonStart = $submit.Text.IndexOf("{")
    if ($jsonStart -ge 0) {
      $submission = $submit.Text.Substring($jsonStart) | ConvertFrom-Json
    }
  } catch {
  }

  $status = if ($null -ne $submission -and $submission.PSObject.Properties["status"]) { [string]$submission.status } else { $null }
  $result.submissionId = $(if ($null -ne $submission -and $submission.PSObject.Properties["id"]) { [string]$submission.id } else { $null })
  if ($submit.ExitCode -ne 0 -or $status -ne "Accepted") {
    if ($result.submissionId) {
      Invoke-GpDmgTool -FilePath "xcrun" -ArgumentList @("notarytool", "log", $result.submissionId, "--keychain-profile", $profileName) -LogPath $LogPath -AllowFailure -Quiet | Out-Null
    }
    $result.status = "failed"
    throw ("Notarization failed (status: {0}). See log: {1}" -f $(if ($status) { $status } else { "exit $($submit.ExitCode)" }), $LogPath)
  }

  $result.status = "accepted"
  $result.message = ("Notarization accepted (submission {0})." -f $result.submissionId)
  Write-GpDmgLogLine -LogPath $LogPath -Message $result.message

  if ($notarization.Staple) {
    Invoke-GpDmgTool -FilePath "xcrun" -ArgumentList @("stapler", "staple", $ArtifactPath) -LogPath $LogPath -Quiet | Out-Null
    Invoke-GpDmgTool -FilePath "xcrun" -ArgumentList @("stapler", "validate", $ArtifactPath) -LogPath $LogPath -Quiet | Out-Null
    $result.stapled = $true
  }

  return [pscustomobject]$result
}

function Assert-GpDmgHostTools {
  foreach ($tool in @("hdiutil", "codesign", "ditto", "plutil", "lipo")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
      throw "The DMG backend requires '$tool' on PATH (part of macOS and the Xcode Command Line Tools)."
    }
  }
}

function Assert-GpDmgStagedApp {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Config
  )

  $info = $Config.AppInfo
  if (-not $info.Exists) {
    throw "Staged app bundle not found: $($Config.StagedAppPath). The DMG backend packages <payload.appRoot>/$($Config.AppBundleName) from the staged payload; run the stage step first."
  }
  if (-not $info.HasInfoPlist) {
    throw "Staged app bundle has no Contents/Info.plist: $($Config.StagedAppPath)"
  }
  if (-not $info.HasExecutable) {
    throw "Staged app bundle has no executable for CFBundleExecutable '$($info.Executable)': $($Config.StagedAppPath)"
  }
}

function Write-GpDmgArtifactMetadata {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Details,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  $hostEnvironment = Get-GpHostEnvironment
  $artifactItem = Get-Item -LiteralPath $Config.ArtifactPath
  $metadata = [ordered]@{
    generatedAt = (Get-Date).ToString("o")
    backend = "dmg"
    manifestPath = $Context.ManifestPath
    targetPlatform = $Context.TargetPlatform
    profiles = [string[]]@(Get-GpRequestedProfiles -Manifest $Context.Manifest)
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
      dmg = [ordered]@{
        path = $Config.ArtifactPath
        sha256 = Get-GpFileSha256 -Path $Config.ArtifactPath
        sizeBytes = $artifactItem.Length
        format = $Config.Format
        filesystem = $Config.Filesystem
        volumeName = $Config.VolumeName
      }
      metadata = [ordered]@{ path = $Config.Sidecars.MetadataPath }
      diagnostics = [ordered]@{ path = $Config.Sidecars.DiagnosticsPath }
    }
    app = [ordered]@{
      stagedPath = $Config.StagedAppPath
      bundleName = $Config.AppBundleName
      bundleIdentifier = $Config.AppInfo.BundleIdentifier
      shortVersion = $Config.AppInfo.ShortVersion
      bundleVersion = $Config.AppInfo.BundleVersion
      minimumSystemVersion = $Config.AppInfo.MinimumSystemVersion
      executable = $Config.AppInfo.Executable
      archs = [string[]]@($Config.AppInfo.Archs)
      arch = $Config.AppInfo.ArchToken
    }
    layout = [ordered]@{
      applicationsLink = [bool]$Config.ApplicationsLink
      backgroundImage = $Config.BackgroundRelativePath
      finderLayoutMode = $Config.FinderLayout
      finderLayoutApplied = [bool]$Details["finderLayoutApplied"]
      finderLayoutReason = $Details["finderLayoutReason"]
      noticeReport = $(if ($Config.NoticeReport.Enabled) { $Config.NoticeReport.FileName } else { $null })
      window = [ordered]@{
        bounds = @($Config.Window.X, $Config.Window.Y, $Config.Window.Width, $Config.Window.Height)
        iconSize = $Config.Window.IconSize
        appIconPosition = @($Config.Window.AppIcon.X, $Config.Window.AppIcon.Y)
        applicationsIconPosition = @($Config.Window.ApplicationsIcon.X, $Config.Window.ApplicationsIcon.Y)
      }
    }
    signing = [ordered]@{
      identity = $Config.Signing.Identity
      adHoc = [bool]$Config.Signing.IsAdHoc
      resigned = [bool]$Config.Signing.Resign
      entitlementsPath = $Config.Signing.EntitlementsPath
      appSignature = $Details["appSignature"]
      dmgSigned = [bool]$Details["dmgSigned"]
    }
    notarization = $Details["notarization"]
    ignoredSettings = [string[]]@($Details["ignoredSettings"])
    warnings = [string[]]@($Details["warnings"])
    outputs = [ordered]@{
      logPath = $LogPath
      diagnosticsDocPath = Get-GpDmgDiagnosticsDocPath
    }
    tooling = [ordered]@{
      hdiutil = (Get-Command hdiutil).Source
      codesign = (Get-Command codesign).Source
      macosVersion = ([string](& sw_vers -productVersion 2>$null)).Trim()
    }
    host = [ordered]@{
      platform = $hostEnvironment.Platform
      pwshVersion = $hostEnvironment.PwshVersion
      currentPath = $hostEnvironment.CurrentPath
      toolRoot = $hostEnvironment.ToolRoot
    }
  }

  $metadata | ConvertTo-Json -Depth 20 | Set-Content -Path $Config.Sidecars.MetadataPath -Encoding utf8
  Write-GpDmgLogLine -LogPath $LogPath -Message ("Wrote artifact metadata: {0}" -f $Config.Sidecars.MetadataPath)
  return $Config.Sidecars.MetadataPath
}

function Write-GpDmgDiagnosticsSummary {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Details,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  $lines = [System.Collections.Generic.List[string]]::new()
  $lines.Add(("DMG packaging summary for {0}" -f $Config.DisplayName)) | Out-Null
  $lines.Add(("Manifest: {0}" -f $Context.ManifestPath)) | Out-Null
  $lines.Add(("Artifact: {0}" -f $Config.ArtifactPath)) | Out-Null
  $lines.Add(("Metadata: {0}" -f $Config.Sidecars.MetadataPath)) | Out-Null
  $lines.Add(("Package log: {0}" -f $LogPath)) | Out-Null
  $lines.Add(("Staged app: {0}" -f $Config.StagedAppPath)) | Out-Null
  $lines.Add(("Architectures: {0} ({1})" -f $Config.AppInfo.ArchToken, ([string]::Join(", ", @($Config.AppInfo.Archs))))) | Out-Null
  $lines.Add(("Image: {0}, {1}, volume '{2}'" -f $Config.Format, $Config.Filesystem, $Config.VolumeName)) | Out-Null
  $lines.Add(("Finder layout: {0} ({1})" -f $(if ($Details["finderLayoutApplied"]) { "applied" } else { "not applied" }), $Details["finderLayoutReason"])) | Out-Null
  $lines.Add(("Signing identity: {0}{1}" -f $Config.Signing.Identity, $(if ($Config.Signing.Resign) { " (re-signed)" } else { " (existing signature kept)" }))) | Out-Null
  $notarization = $Details["notarization"]
  $lines.Add(("Notarization: {0}" -f $notarization["status"])) | Out-Null
  foreach ($warning in @($Details["warnings"])) {
    $lines.Add(("Warning: {0}" -f $warning)) | Out-Null
  }
  foreach ($note in @($Details["ignoredSettings"])) {
    $lines.Add(("Not applied: {0}" -f $note)) | Out-Null
  }
  $lines.Add(("Triage guide: {0}" -f (Get-GpDmgDiagnosticsDocPath))) | Out-Null
  $lines.Add("") | Out-Null
  $lines.Add("Reproduction commands:") | Out-Null
  $lines.Add(("./scripts/gnustep-packager.ps1 -Command package -Manifest `"{0}`" -Backend dmg" -f $Context.ManifestPath)) | Out-Null
  $lines.Add(("./scripts/gnustep-packager.ps1 -Command validate -Manifest `"{0}`" -Backend dmg -RunSmoke" -f $Context.ManifestPath)) | Out-Null
  $lines.Add("") | Out-Null
  $lines.Add("Common failure areas: staged app bundle path, existing code signature, hdiutil create/convert, Finder automation permission, notarytool credentials, leftover mounted volumes (hdiutil info).") | Out-Null

  Set-Content -Path $Config.Sidecars.DiagnosticsPath -Value $lines -Encoding ascii
  Write-GpDmgLogLine -LogPath $LogPath -Message ("Wrote diagnostics summary: {0}" -f $Config.Sidecars.DiagnosticsPath)
  return $Config.Sidecars.DiagnosticsPath
}

function Invoke-GpDmgPackage {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [switch]$DryRun,
    [string]$LogPath
  )

  $config = Get-GpDmgConfig -Context $Context
  $backendSupport = Get-GpBackendSupport -Backend "dmg"
  $summary = [ordered]@{
    Backend = "dmg"
    ManifestPath = $Context.ManifestPath
    TargetPlatform = $Context.TargetPlatform
    ProductName = $config.DisplayName
    Version = $config.Version
    StageRoot = $config.StageRoot
    StagedAppPath = $config.StagedAppPath
    ArtifactPath = $config.ArtifactPath
    VolumeName = $config.VolumeName
    Filesystem = $config.Filesystem
    Format = $config.Format
    FinderLayout = $config.FinderLayout
    SigningIdentity = $config.Signing.Identity
    Resign = [bool]$config.Signing.Resign
    NotarizationEnabled = [bool]$config.Notarization.Enabled
    HostPlatform = $backendSupport.HostPlatform
    RequiredPlatform = $backendSupport.RequiredPlatform
    HostSupported = [bool]$backendSupport.Supported
  }

  if ($DryRun) {
    Write-GpDmgLogLine -LogPath $LogPath -Message ("DMG package dry-run for {0}" -f $config.DisplayName)
    return [pscustomobject]$summary
  }

  if (-not $backendSupport.Supported) {
    throw "DMG packaging requires host platform '$($backendSupport.RequiredPlatform)'. Current host: '$($backendSupport.HostPlatform)'."
  }

  Assert-GpDmgHostTools
  Assert-GpDmgStagedApp -Config $config
  if ($null -ne $config.BackgroundPath -and -not (Test-Path -LiteralPath $config.BackgroundPath -PathType Leaf)) {
    throw "Configured backends.dmg.backgroundImageRelativePath does not exist in the staged payload: $($config.BackgroundPath)"
  }

  $workPaths = Get-GpDmgWorkPaths -Config $config
  Ensure-GpDirectory -Path $workPaths.Root | Out-Null
  Ensure-GpDirectory -Path $config.OutputPaths.PackageRoot | Out-Null
  $details = [ordered]@{
    finderLayoutApplied = $false
    finderLayoutReason = $null
    appSignature = $null
    dmgSigned = $false
    notarization = $null
    ignoredSettings = @()
    warnings = [System.Collections.Generic.List[string]]::new()
  }

  Write-GpDmgLogLine -LogPath $LogPath -Message ("Starting DMG package build for {0} ({1})" -f $config.DisplayName, $config.StagedAppPath)
  $details["ignoredSettings"] = @(Get-GpDmgIgnoredSettings -Context $Context)
  foreach ($note in @($details["ignoredSettings"])) {
    Write-GpDmgLogLine -LogPath $LogPath -Message ("NOTE {0}" -f $note)
  }
  if (-not [string]::IsNullOrWhiteSpace($config.AppInfo.ShortVersion) -and $config.AppInfo.ShortVersion -ne $config.Version) {
    $warning = ("App CFBundleShortVersionString '{0}' differs from package.version '{1}'." -f $config.AppInfo.ShortVersion, $config.Version)
    $details["warnings"].Add($warning) | Out-Null
    Write-GpDmgLogLine -LogPath $LogPath -Message ("WARN {0}" -f $warning)
  }

  $mount = $null
  $succeeded = $false
  try {
    # 1. Volume contents: a copy of the staged app (the stage is never mutated),
    #    the /Applications link, an optional background and notice report.
    Ensure-GpDirectory -Path $workPaths.VolumeRoot | Out-Null
    $volumeApp = Join-Path $workPaths.VolumeRoot $config.AppBundleName
    Copy-GpDmgAppBundle -Source $config.StagedAppPath -Destination $volumeApp -LogPath $LogPath

    if ($config.Signing.Resign) {
      Invoke-GpDmgCodesignApp -Config $config -AppPath $volumeApp -LogPath $LogPath
    } else {
      Write-GpDmgLogLine -LogPath $LogPath -Message "Keeping the staged app's existing code signature (backends.dmg.signing.resign is false)."
    }

    $verify = Test-GpDmgCodesignVerify -Path $volumeApp -LogPath $LogPath -Deep
    $details["appSignature"] = [ordered]@{
      verified = [bool]$verify.Passed
    }
    $signature = Get-GpDmgSignatureInfo -Path $volumeApp
    $details["appSignature"]["signed"] = [bool]$signature.Signed
    $details["appSignature"]["adHoc"] = [bool]$signature.AdHoc
    $details["appSignature"]["identifier"] = $signature.Identifier
    $details["appSignature"]["teamIdentifier"] = $signature.TeamIdentifier
    $details["appSignature"]["authorities"] = [string[]]@($signature.Authorities)
    $details["appSignature"]["hardenedRuntime"] = [bool]$signature.HardenedRuntime
    $details["appSignature"]["flags"] = $signature.Flags
    if (-not $verify.Passed) {
      $message = ("The app bundle's code signature does not verify: {0}" -f ($verify.Output -replace "\s+", " ").Trim())
      if ($config.Validation.RequireSignature) {
        throw ("{0} Sign it in the build, or set backends.dmg.signing.resign to true." -f $message)
      }
      $details["warnings"].Add($message) | Out-Null
      Write-GpDmgLogLine -LogPath $LogPath -Message ("WARN {0}" -f $message)
    }
    if ($config.Notarization.Enabled -and -not $config.Signing.IsAdHoc -and -not $signature.HardenedRuntime) {
      $details["warnings"].Add("Notarization requires the hardened runtime; the app signature has no 'runtime' flag.") | Out-Null
    }

    if ($config.ApplicationsLink) {
      New-Item -ItemType SymbolicLink -Path (Join-Path $workPaths.VolumeRoot "Applications") -Target "/Applications" | Out-Null
    }
    if ($null -ne $config.BackgroundPath) {
      $backgroundRoot = Ensure-GpDirectory -Path (Join-Path $workPaths.VolumeRoot ".background")
      Copy-Item -LiteralPath $config.BackgroundPath -Destination (Join-Path $backgroundRoot $config.BackgroundFileName)
    }
    if ($config.NoticeReport.Enabled) {
      Write-GpDmgNoticeReport -Context $Context -Config $config -VolumeRoot $workPaths.VolumeRoot -LogPath $LogPath | Out-Null
    }

    # 2. Read-write image from the folder, with room for Finder's .DS_Store.
    $contentBytes = Get-GpDirectorySizeBytes -Path $workPaths.VolumeRoot
    $sizeMegabytes = [long][Math]::Ceiling(($contentBytes * 1.2) / 1MB) + 32
    Invoke-GpDmgTool -FilePath "hdiutil" -ArgumentList @(
      "create", "-ov", "-srcfolder", $workPaths.VolumeRoot, "-volname", $config.VolumeName,
      "-fs", $config.Filesystem, "-format", "UDRW", "-size", ("{0}m" -f $sizeMegabytes), "-nospotlight",
      $workPaths.ReadWriteImage
    ) -LogPath $LogPath -Quiet | Out-Null

    # 3. Optional Finder layout. It needs the volume visible to Finder, so this
    #    is the only attach without -nobrowse; it addresses only this volume.
    $blocker = Get-GpDmgFinderLayoutBlocker -Config $config -LogPath $LogPath
    if ($blocker) {
      $details["finderLayoutReason"] = $blocker
      Write-GpDmgLogLine -LogPath $LogPath -Message ("Finder layout skipped: {0}. The image opens with Finder's default window." -f $blocker)
      Write-Host ("Finder layout skipped: {0}" -f $blocker)
    } else {
      $mount = Mount-GpDmgImage -ImagePath $workPaths.ReadWriteImage -ReadWrite -Browse -LogPath $LogPath
      $layout = Invoke-GpDmgFinderLayout -Config $config -MountPoint $mount.MountPoint -LogPath $LogPath -LayoutLog $workPaths.LayoutLog
      $details["finderLayoutApplied"] = [bool]$layout.Applied
      $details["finderLayoutReason"] = $layout.Reason
      Write-GpDmgLogLine -LogPath $LogPath -Message ("Finder layout: applied={0} ({1})" -f $layout.Applied, $layout.Reason)
      if (-not $layout.Applied) {
        if ($config.FinderLayout -eq "applescript") {
          throw ("Finder layout failed: {0}. See {1}." -f $layout.Reason, $workPaths.LayoutLog)
        }
        Write-Host ("Finder layout not applied: {0}" -f $layout.Reason)
      }
      # The read-write mount gave the volume an FSEvents log; it is noise in
      # the shipped image.
      $fseventsd = Join-Path $mount.MountPoint ".fseventsd"
      if (Test-Path -LiteralPath $fseventsd) {
        Remove-Item -Recurse -Force -LiteralPath $fseventsd -ErrorAction SilentlyContinue
      }
      & sync
      if (-not (Dismount-GpDmgImage -Mount $mount -LogPath $LogPath)) {
        throw "Could not detach the read-write image $($workPaths.ReadWriteImage). See log: $LogPath"
      }
      $mount = $null
    }

    # 4. Compressed read-only image.
    if (Test-Path -LiteralPath $config.ArtifactPath) {
      Remove-Item -Force -LiteralPath $config.ArtifactPath
    }
    $convertArguments = @("convert", $workPaths.ReadWriteImage, "-format", $config.Format, "-o", $config.ArtifactPath)
    if ($config.Format -eq "UDZO") {
      $convertArguments += @("-imagekey", "zlib-level=9")
    }
    Invoke-GpDmgTool -FilePath "hdiutil" -ArgumentList $convertArguments -LogPath $LogPath -Quiet | Out-Null

    # 5. Sign the image itself with a real identity (an ad-hoc DMG signature
    #    adds nothing Gatekeeper can use).
    if (-not $config.Signing.IsAdHoc -and $config.Signing.SignDmg) {
      $dmgSignArguments = @("--force", "--timestamp", "--sign", $config.Signing.Identity)
      if (-not [string]::IsNullOrWhiteSpace($config.Signing.Keychain)) {
        $dmgSignArguments = @("--keychain", $config.Signing.Keychain) + $dmgSignArguments
      }
      Invoke-GpDmgTool -FilePath "codesign" -ArgumentList @($dmgSignArguments + @($config.ArtifactPath)) -LogPath $LogPath -Quiet | Out-Null
      $details["dmgSigned"] = $true
    } else {
      Write-GpDmgLogLine -LogPath $LogPath -Message "DMG image left unsigned (ad-hoc identity or signDmg false)."
    }

    # 6. Notarize and staple when configured and credentials are present.
    $details["notarization"] = [ordered]@{}
    $notarizationResult = Invoke-GpDmgNotarization -Config $config -ArtifactPath $config.ArtifactPath -LogPath $LogPath
    foreach ($property in $notarizationResult.PSObject.Properties) {
      $details["notarization"][$property.Name] = $property.Value
    }

    $succeeded = $true
  } finally {
    if ($null -ne $mount) {
      Dismount-GpDmgImage -Mount $mount -LogPath $LogPath | Out-Null
    }
    if (Test-Path -LiteralPath $workPaths.ReadWriteImage) {
      Remove-Item -Force -LiteralPath $workPaths.ReadWriteImage
    }
    if ($succeeded -and (Test-Path -LiteralPath $workPaths.VolumeRoot)) {
      Remove-Item -Recurse -Force -LiteralPath $workPaths.VolumeRoot
    }
  }

  $details["warnings"] = [string[]]@($details["warnings"].ToArray())
  $metadataPath = Write-GpDmgArtifactMetadata -Context $Context -Config $config -Details $details -LogPath $LogPath
  $diagnosticsPath = Write-GpDmgDiagnosticsSummary -Context $Context -Config $config -Details $details -LogPath $LogPath

  return [pscustomobject]@{
    Backend = "dmg"
    ManifestPath = $Context.ManifestPath
    ArtifactPath = $config.ArtifactPath
    SizeBytes = (Get-Item -LiteralPath $config.ArtifactPath).Length
    Arch = $config.AppInfo.ArchToken
    VolumeName = $config.VolumeName
    MetadataPath = $metadataPath
    DiagnosticsPath = $diagnosticsPath
    FinderLayoutApplied = [bool]$details["finderLayoutApplied"]
    FinderLayoutReason = $details["finderLayoutReason"]
    NotarizationStatus = [string]$details["notarization"]["status"]
    WorkRoot = $workPaths.Root
    LogPath = $LogPath
  }
}

function Invoke-GpDmgSmoke {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Config,
    [Parameter(Mandatory = $true)]
    [string]$ExecutablePath,
    [Parameter(Mandatory = $true)]
    [string]$SmokeLog
  )

  $startup = [Math]::Max($Config.Smoke.StartupSeconds, 1)
  Set-Content -Path $SmokeLog -Value ("[{0}] DMG launch smoke: {1}" -f (Get-Date).ToString("o"), $ExecutablePath)
  Write-GpDmgLogLine -LogPath $SmokeLog -Message ("Startup window: {0}s; arguments: {1}" -f $startup, ([string]::Join(" ", @($Config.Smoke.Arguments))))

  # The executable runs directly (not through `open`), so the process can be
  # timed and killed without Launch Services or another app being involved.
  $result = Invoke-GpDmgProcessWithTimeout -FilePath $ExecutablePath -ArgumentList @($Config.Smoke.Arguments) -TimeoutSeconds $startup -Environment $Config.Smoke.Environment
  Add-Content -Path $SmokeLog -Value @("[stdout]", $result.StdOut, "[stderr]", $result.StdErr)

  $outcome = if ($result.TimedOut) {
    "process-remained-running-through-startup-window"
  } elseif ($result.ExitCode -eq 0) {
    "process-exited-cleanly"
  } else {
    $null
  }
  Write-GpDmgLogLine -LogPath $SmokeLog -Message ("Exit code: {0}; timed out (killed): {1}" -f $result.ExitCode, $result.TimedOut)
  if (-not $outcome) {
    throw ("DMG launch smoke failed: the app exited with code {0} within {1}s. See {2}." -f $result.ExitCode, $startup, $SmokeLog)
  }

  Write-GpDmgLogLine -LogPath $SmokeLog -Message ("Smoke validation succeeded: {0}" -f $outcome)
  return [pscustomobject]@{
    Outcome = $outcome
    ExitCode = $result.ExitCode
    SmokeLog = $SmokeLog
  }
}

function Invoke-GpDmgValidation {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [switch]$DryRun,
    [switch]$RunSmoke,
    [string]$LogPath
  )

  $config = Get-GpDmgConfig -Context $Context
  $backendSupport = Get-GpBackendSupport -Backend "dmg"
  $runSmoke = [bool]($RunSmoke -or $config.Smoke.Enabled)

  if ($DryRun) {
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
      Ensure-GpDirectory -Path (Split-Path -Parent $LogPath) | Out-Null
      Set-Content -Path $LogPath -Value ("[{0}] DMG validation dry-run" -f (Get-Date).ToString("o"))
    }
    return [pscustomobject]@{
      Backend = "dmg"
      Mode = "dry-run"
      ArtifactPath = $config.ArtifactPath
      HostPlatform = $backendSupport.HostPlatform
      RequiredPlatform = $backendSupport.RequiredPlatform
      HostSupported = [bool]$backendSupport.Supported
      RunSmoke = $runSmoke
      RequireGatekeeperAcceptance = [bool]$config.Validation.RequireGatekeeperAcceptance
      LogPath = $LogPath
    }
  }

  if (-not $backendSupport.Supported) {
    throw "DMG validation requires host platform '$($backendSupport.RequiredPlatform)'. Current host: '$($backendSupport.HostPlatform)'."
  }
  Assert-GpDmgHostTools
  if (-not (Test-Path -LiteralPath $config.ArtifactPath -PathType Leaf)) {
    throw "DMG artifact not found: $($config.ArtifactPath)"
  }

  Ensure-GpDirectory -Path (Split-Path -Parent $LogPath) | Out-Null
  $validationRoot = Split-Path -Parent $LogPath
  $smokeLog = Join-Path $validationRoot "smoke.log"
  $summaryPath = Join-Path $validationRoot "validation-summary.json"
  $failures = [System.Collections.Generic.List[string]]::new()
  $checks = [System.Collections.Generic.List[psobject]]::new()

  function Add-GpDmgCheck {
    param([string]$Name, [string]$Status, [string]$Detail)
    $checks.Add([pscustomobject]@{ name = $Name; status = $Status; detail = $Detail }) | Out-Null
    Write-GpDmgLogLine -LogPath $LogPath -Message ("{0,-7} {1}: {2}" -f $Status.ToUpperInvariant(), $Name, $Detail)
    if ($Status -eq "fail") {
      $failures.Add(("{0}: {1}" -f $Name, $Detail)) | Out-Null
    }
  }

  Write-GpDmgLogLine -LogPath $LogPath -Message ("Validating DMG artifact: {0}" -f $config.ArtifactPath)

  $verify = Invoke-GpDmgTool -FilePath "hdiutil" -ArgumentList @("verify", $config.ArtifactPath) -LogPath $LogPath -AllowFailure -Quiet
  Add-GpDmgCheck -Name "hdiutil-verify" -Status $(if ($verify.ExitCode -eq 0) { "pass" } else { "fail" }) -Detail $(if ($verify.ExitCode -eq 0) { "checksum valid" } else { "exit $($verify.ExitCode)" })

  $imageInfo = Invoke-GpDmgTool -FilePath "hdiutil" -ArgumentList @("imageinfo", "-plist", $config.ArtifactPath) -LogPath $LogPath -AllowFailure -Quiet
  $actualFormat = $null
  if ($imageInfo.ExitCode -eq 0) {
    try {
      $actualFormat = [string](Convert-GpDmgPlistTextToObject -PlistText $imageInfo.Text).Format
    } catch {
    }
  }
  Add-GpDmgCheck -Name "image-format" -Status $(if ($actualFormat -eq $config.Format) { "pass" } else { "fail" }) -Detail ("expected {0}, found {1}" -f $config.Format, $(if ($actualFormat) { $actualFormat } else { "(unknown)" }))

  $dmgSignature = Get-GpDmgSignatureInfo -Path $config.ArtifactPath
  if ($dmgSignature.Signed) {
    $dmgVerify = Test-GpDmgCodesignVerify -Path $config.ArtifactPath -LogPath $LogPath
    Add-GpDmgCheck -Name "dmg-signature" -Status $(if ($dmgVerify.Passed) { "pass" } else { "fail" }) -Detail ("signed by {0}" -f $(if (@($dmgSignature.Authorities).Count -gt 0) { $dmgSignature.Authorities[0] } else { "ad-hoc" }))
  } else {
    Add-GpDmgCheck -Name "dmg-signature" -Status "info" -Detail "image is not signed"
  }

  $stapler = Invoke-GpDmgTool -FilePath "xcrun" -ArgumentList @("stapler", "validate", $config.ArtifactPath) -LogPath $LogPath -AllowFailure -Quiet
  Add-GpDmgCheck -Name "notarization-ticket" -Status "info" -Detail $(if ($stapler.ExitCode -eq 0) { "stapled ticket present" } else { "no stapled ticket" })

  $mountPoint = Join-Path $validationRoot ("mount-{0}" -f (New-GpTimestamp))
  $mount = $null
  $appSignature = $null
  $gatekeeper = $null
  $smokeResult = $null
  try {
    $mount = Mount-GpDmgImage -ImagePath $config.ArtifactPath -MountPoint $mountPoint -LogPath $LogPath
    Add-GpDmgCheck -Name "attach" -Status "pass" -Detail ("read-only, nobrowse at {0}" -f $mount.MountPoint)

    $mountedApp = Join-Path $mount.MountPoint $config.AppBundleName
    $mountedInfo = Get-GpDmgAppBundleInfo -AppPath $mountedApp
    Add-GpDmgCheck -Name "app-bundle" -Status $(if ($mountedInfo.Exists -and $mountedInfo.HasInfoPlist -and $mountedInfo.HasExecutable) { "pass" } else { "fail" }) -Detail ("{0} (executable {1}, {2})" -f $config.AppBundleName, $mountedInfo.Executable, $mountedInfo.ArchToken)

    if ($config.ApplicationsLink) {
      $linkPath = Join-Path $mount.MountPoint "Applications"
      $linkItem = Get-Item -LiteralPath $linkPath -Force -ErrorAction SilentlyContinue
      $target = if ($null -ne $linkItem -and $linkItem.PSObject.Properties["LinkTarget"]) { [string]$linkItem.LinkTarget } else { $null }
      Add-GpDmgCheck -Name "applications-link" -Status $(if ($target -eq "/Applications") { "pass" } else { "fail" }) -Detail ("Applications -> {0}" -f $(if ($target) { $target } else { "(missing)" }))
    }
    if ($config.BackgroundFileName) {
      $backgroundExists = Test-Path -LiteralPath (Join-Path $mount.MountPoint (".background/{0}" -f $config.BackgroundFileName))
      Add-GpDmgCheck -Name "background" -Status $(if ($backgroundExists) { "pass" } else { "fail" }) -Detail (".background/{0}" -f $config.BackgroundFileName)
    }
    $hasDsStore = Test-Path -LiteralPath (Join-Path $mount.MountPoint ".DS_Store")
    Add-GpDmgCheck -Name "finder-layout" -Status "info" -Detail $(if ($hasDsStore) { ".DS_Store present (custom window layout)" } else { "no .DS_Store (Finder default window)" })

    if ($mountedInfo.Exists) {
      $codesignVerify = Test-GpDmgCodesignVerify -Path $mountedApp -LogPath $LogPath -Deep
      $appSignature = Get-GpDmgSignatureInfo -Path $mountedApp
      $signatureDetail = if ($appSignature.Signed) {
        "{0}; {1}{2}" -f $(if ($appSignature.AdHoc) { "ad-hoc" } else { [string]::Join(" / ", @($appSignature.Authorities)) }), $(if ($appSignature.HardenedRuntime) { "hardened runtime" } else { "no hardened runtime" }), $(if ($appSignature.TeamIdentifier -and $appSignature.TeamIdentifier -ne "not set") { "; team $($appSignature.TeamIdentifier)" } else { "" })
      } else {
        "not signed"
      }
      $signatureStatus = if ($codesignVerify.Passed) { "pass" } elseif ($config.Validation.RequireSignature) { "fail" } else { "warn" }
      Add-GpDmgCheck -Name "codesign-verify" -Status $signatureStatus -Detail ("--deep --strict: {0} ({1})" -f $(if ($codesignVerify.Passed) { "valid" } else { ($codesignVerify.Output -replace "\s+", " ").Trim() }), $signatureDetail)

      $spctl = Invoke-GpDmgTool -FilePath "spctl" -ArgumentList @("--assess", "--type", "execute", "--verbose=4", $mountedApp) -LogPath $LogPath -AllowFailure -Quiet
      $gatekeeper = [ordered]@{
        accepted = [bool]($spctl.ExitCode -eq 0)
        exitCode = $spctl.ExitCode
        output = ($spctl.Text -replace [regex]::Escape($mount.MountPoint), "<volume>").Trim()
      }
      $gatekeeperStatus = if ($spctl.ExitCode -eq 0) { "pass" } elseif ($config.Validation.RequireGatekeeperAcceptance) { "fail" } else { "info" }
      $gatekeeperDetail = if ($spctl.ExitCode -eq 0) { "accepted" } else { "rejected (expected without Developer ID + notarization): {0}" -f (($gatekeeper.output -split "`n") | Select-Object -Last 1) }
      Add-GpDmgCheck -Name "gatekeeper" -Status $gatekeeperStatus -Detail $gatekeeperDetail

      if ($mountedInfo.HasInfoPlist -and $mountedInfo.ShortVersion -and $mountedInfo.ShortVersion -ne $config.Version) {
        Add-GpDmgCheck -Name "bundle-version" -Status "warn" -Detail ("CFBundleShortVersionString {0} != package.version {1}" -f $mountedInfo.ShortVersion, $config.Version)
      } else {
        Add-GpDmgCheck -Name "bundle-version" -Status "pass" -Detail ("{0} ({1})" -f $mountedInfo.ShortVersion, $mountedInfo.BundleVersion)
      }
    }

    $installedContract = Invoke-GpPackageContractAssertions -Context $Context -Scope "installed" -Backend "dmg" -RootPath $mount.MountPoint
    foreach ($line in @($installedContract.Lines)) {
      Write-GpDmgLogLine -LogPath $LogPath -Message ("Installed contract: {0}" -f $line)
    }
    Add-GpDmgCheck -Name "installed-contract" -Status $(if ($installedContract.HasIssues) { "fail" } else { "pass" }) -Detail $(if ($installedContract.HasIssues) { [string]::Join("; ", @($installedContract.Issues)) } else { "{0} assertion(s)" -f @($installedContract.Lines).Count })

    if ($runSmoke) {
      if ($mountedInfo.HasExecutable) {
        try {
          $smokeResult = Invoke-GpDmgSmoke -Config $config -ExecutablePath $mountedInfo.ExecutablePath -SmokeLog $smokeLog
          Add-GpDmgCheck -Name "launch-smoke" -Status "pass" -Detail $smokeResult.Outcome
        } catch {
          Add-GpDmgCheck -Name "launch-smoke" -Status "fail" -Detail $_.Exception.Message
        }
      } else {
        Add-GpDmgCheck -Name "launch-smoke" -Status "fail" -Detail "no executable to launch"
      }
    } else {
      Add-GpDmgCheck -Name "launch-smoke" -Status "skip" -Detail "not requested (-RunSmoke or backends.dmg.smoke.enabled)"
    }
  } catch {
    Add-GpDmgCheck -Name "validation-error" -Status "fail" -Detail $_.Exception.Message
  } finally {
    if ($null -ne $mount) {
      $detached = Dismount-GpDmgImage -Mount $mount -LogPath $LogPath
      if (-not $detached) {
        $failures.Add("detach: could not detach $($mount.Device)") | Out-Null
      }
    }
    if (Test-Path -LiteralPath $mountPoint) {
      Remove-Item -Force -Recurse -LiteralPath $mountPoint -ErrorAction SilentlyContinue
    }
  }

  $summary = [ordered]@{
    generatedAt = (Get-Date).ToString("o")
    artifact = $config.ArtifactPath
    passed = [bool]($failures.Count -eq 0)
    checks = @($checks.ToArray())
    appSignature = $(if ($appSignature) { [ordered]@{ signed = $appSignature.Signed; adHoc = $appSignature.AdHoc; hardenedRuntime = $appSignature.HardenedRuntime; authorities = $appSignature.Authorities; teamIdentifier = $appSignature.TeamIdentifier; flags = $appSignature.Flags } } else { $null })
    gatekeeper = $gatekeeper
    smoke = $(if ($smokeResult) { [ordered]@{ outcome = $smokeResult.Outcome; log = $smokeResult.SmokeLog } } else { $null })
    log = $LogPath
  }
  $summary | ConvertTo-Json -Depth 10 | Set-Content -Path $summaryPath -Encoding utf8

  foreach ($check in $checks) {
    Write-Host ("  {0,-5} {1}: {2}" -f $check.status.ToUpperInvariant(), $check.name, $check.detail)
  }

  if ($failures.Count -gt 0) {
    throw ("DMG validation failed: {0}. See log: {1}" -f ([string]::Join("; ", @($failures.ToArray()))), $LogPath)
  }

  return [pscustomobject]@{
    Backend = "dmg"
    Mode = "execute"
    ArtifactPath = $config.ArtifactPath
    Checks = @($checks.ToArray())
    GatekeeperAccepted = $(if ($gatekeeper) { [bool]$gatekeeper.accepted } else { $false })
    SmokeOutcome = $(if ($smokeResult) { $smokeResult.Outcome } else { $null })
    SmokeLog = $(if ($smokeResult) { $smokeLog } else { $null })
    SummaryPath = $summaryPath
    LogPath = $LogPath
  }
}
