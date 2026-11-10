# AppImage theme metadata: what themes a packaged app can load, and how its
# GSTheme default is set, for tools that must not run or mount the AppImage
# (a standalone theme-settings configurator, for one).
#
# Two documents, one generator:
#   - metadata/gnustep-packager-theme-report.json inside the payload, extended
#     to formatVersion 2 (every v1 field kept);
#   - <artifact-base>.themes.json beside the AppImage, written after
#     appimagetool, bound to the AppImage by its sha256.
#
# Everything read from a theme (plists, names, versions) is untrusted data: it
# is copied as text and never executed or loaded. Paths are payload-relative
# ("usr/..."), never the /tmp/.mount_* path of a running AppImage.

$script:GpThemeSettingsInlineLimit = 262144
$script:GpThemeInfoPlistLimit = 1048576

# --- Property lists ------------------------------------------------------------

# Parses an XML or OpenStep (ASCII) property list into ordered dictionaries,
# arrays and strings. XML numbers and booleans keep their types. Throws on
# anything malformed.
function ConvertFrom-GpPlistText {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

  $trimmed = $Text.TrimStart([char]0xFEFF).Trim()
  if ($trimmed.StartsWith("<?xml", [System.StringComparison]::Ordinal) -or $trimmed.StartsWith("<!DOCTYPE plist", [System.StringComparison]::Ordinal) -or $trimmed.StartsWith("<plist", [System.StringComparison]::Ordinal)) {
    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Ignore
    $settings.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($trimmed), $settings)
    $document = [System.Xml.XmlDocument]::new()
    $document.XmlResolver = $null
    $document.Load($reader)
    $plist = $document.DocumentElement
    if ($null -eq $plist -or $plist.Name -ne "plist") { throw "not a plist document" }
    $first = @($plist.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element }) | Select-Object -First 1
    if ($null -eq $first) { throw "empty plist" }
    return (ConvertFrom-GpPlistXmlNode -Node $first)
  }

  $state = [pscustomobject]@{ Text = $Text; Index = 0 }
  $value = Read-GpOpenStepValue -State $state
  Skip-GpOpenStepSpace -State $state
  if ($state.Index -lt $state.Text.Length) { throw ("unexpected text at offset {0}" -f $state.Index) }
  return $value
}

function ConvertFrom-GpPlistXmlNode {
  param([Parameter(Mandatory = $true)][System.Xml.XmlNode]$Node)

  switch ($Node.Name) {
    "dict" {
      $result = [ordered]@{}
      $children = @($Node.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element })
      if ($children.Count % 2 -ne 0) { throw "dict has a key without a value" }
      for ($i = 0; $i -lt $children.Count; $i += 2) {
        if ($children[$i].Name -ne "key") { throw "dict entry without a key" }
        $result[[string]$children[$i].InnerText] = ConvertFrom-GpPlistXmlNode -Node $children[$i + 1]
      }
      return $result
    }
    "array" {
      return ,@($Node.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element } | ForEach-Object { ConvertFrom-GpPlistXmlNode -Node $_ })
    }
    "string" { return [string]$Node.InnerText }
    "date" { return [string]$Node.InnerText }
    "data" { return ([string]$Node.InnerText -replace "\s", "") }
    "integer" { return [long]::Parse($Node.InnerText.Trim(), [System.Globalization.CultureInfo]::InvariantCulture) }
    "real" { return [double]::Parse($Node.InnerText.Trim(), [System.Globalization.CultureInfo]::InvariantCulture) }
    "true" { return $true }
    "false" { return $false }
    default { throw ("unsupported plist element <{0}>" -f $Node.Name) }
  }
}

function Skip-GpOpenStepSpace {
  param([Parameter(Mandatory = $true)]$State)
  $text = $State.Text
  while ($State.Index -lt $text.Length) {
    $c = $text[$State.Index]
    if ([char]::IsWhiteSpace($c)) { $State.Index++; continue }
    if ($c -eq '/' -and $State.Index + 1 -lt $text.Length) {
      $next = $text[$State.Index + 1]
      if ($next -eq '/') {
        $end = $text.IndexOf("`n", $State.Index)
        $State.Index = if ($end -lt 0) { $text.Length } else { $end + 1 }
        continue
      }
      if ($next -eq '*') {
        $end = $text.IndexOf("*/", $State.Index + 2)
        if ($end -lt 0) { throw "unterminated comment" }
        $State.Index = $end + 2
        continue
      }
    }
    break
  }
}

function Read-GpOpenStepValue {
  param([Parameter(Mandatory = $true)]$State)
  Skip-GpOpenStepSpace -State $State
  $text = $State.Text
  if ($State.Index -ge $text.Length) { throw "unexpected end of plist" }
  $c = $text[$State.Index]

  if ($c -eq '{') {
    $State.Index++
    $result = [ordered]@{}
    while ($true) {
      Skip-GpOpenStepSpace -State $State
      if ($State.Index -ge $text.Length) { throw "unterminated dictionary" }
      if ($text[$State.Index] -eq '}') { $State.Index++; break }
      $key = Read-GpOpenStepValue -State $State
      if ($key -isnot [string]) { throw "dictionary key is not a string" }
      Skip-GpOpenStepSpace -State $State
      if ($State.Index -ge $text.Length -or $text[$State.Index] -ne '=') { throw ("expected '=' after key '{0}'" -f $key) }
      $State.Index++
      $result[$key] = Read-GpOpenStepValue -State $State
      Skip-GpOpenStepSpace -State $State
      if ($State.Index -ge $text.Length) { throw "unterminated dictionary" }
      if ($text[$State.Index] -eq ';') { $State.Index++; continue }
      if ($text[$State.Index] -ne '}') { throw ("expected ';' after the value of '{0}'" -f $key) }
    }
    return $result
  }

  if ($c -eq '(') {
    $State.Index++
    $items = [System.Collections.Generic.List[object]]::new()
    while ($true) {
      Skip-GpOpenStepSpace -State $State
      if ($State.Index -ge $text.Length) { throw "unterminated array" }
      if ($text[$State.Index] -eq ')') { $State.Index++; break }
      $items.Add((Read-GpOpenStepValue -State $State)) | Out-Null
      Skip-GpOpenStepSpace -State $State
      if ($State.Index -ge $text.Length) { throw "unterminated array" }
      if ($text[$State.Index] -eq ',') { $State.Index++; continue }
      if ($text[$State.Index] -ne ')') { throw "expected ',' or ')' in array" }
    }
    return ,$items.ToArray()
  }

  if ($c -eq '<') {
    $end = $text.IndexOf('>', $State.Index)
    if ($end -lt 0) { throw "unterminated data" }
    $data = $text.Substring($State.Index + 1, $end - $State.Index - 1) -replace "\s", ""
    if ($data -notmatch '^[0-9A-Fa-f]*$') { throw "data is not hexadecimal" }
    $State.Index = $end + 1
    return $data
  }

  if ($c -eq '"') {
    $State.Index++
    $builder = [System.Text.StringBuilder]::new()
    while ($true) {
      if ($State.Index -ge $text.Length) { throw "unterminated string" }
      $ch = $text[$State.Index]
      if ($ch -eq '"') { $State.Index++; break }
      if ($ch -eq '\') {
        if ($State.Index + 1 -ge $text.Length) { throw "unterminated escape" }
        $esc = $text[$State.Index + 1]
        $State.Index += 2
        switch -CaseSensitive ($esc) {
          'n' { [void]$builder.Append("`n") }
          't' { [void]$builder.Append("`t") }
          'r' { [void]$builder.Append("`r") }
          'a' { [void]$builder.Append([char]7) }
          'b' { [void]$builder.Append([char]8) }
          'f' { [void]$builder.Append([char]12) }
          'v' { [void]$builder.Append([char]11) }
          'U' {
            $hex = if ($State.Index + 4 -le $text.Length) { $text.Substring($State.Index, 4) } else { "" }
            if ($hex -notmatch '^[0-9A-Fa-f]{4}$') { throw "bad \\U escape" }
            [void]$builder.Append([char][Convert]::ToInt32($hex, 16))
            $State.Index += 4
          }
          default {
            if ($esc -ge '0' -and $esc -le '7') {
              $digits = [string]$esc
              while ($digits.Length -lt 3 -and $State.Index -lt $text.Length -and $text[$State.Index] -ge '0' -and $text[$State.Index] -le '7') { $digits += $text[$State.Index]; $State.Index++ }
              [void]$builder.Append([char][Convert]::ToInt32($digits, 8))
            } else {
              [void]$builder.Append($esc)
            }
          }
        }
        continue
      }
      [void]$builder.Append($ch)
      $State.Index++
    }
    return $builder.ToString()
  }

  $start = $State.Index
  while ($State.Index -lt $text.Length -and $text[$State.Index] -match '[A-Za-z0-9_$+/:.\-]') { $State.Index++ }
  if ($State.Index -eq $start) { throw ("unexpected character '{0}' at offset {1}" -f $c, $start) }
  return $text.Substring($start, $State.Index - $start)
}

# Reads a plist file with a size limit. Returns { Status; Value; Error; Sha256; SizeBytes }.
# Status: "ok", "tooLarge" (not parsed) or "malformed".
function Read-GpLimitedPlistFile {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][long]$Limit)

  $item = Get-Item -LiteralPath $Path
  $sha = Get-GpFileSha256 -Path $item.FullName
  if ($item.Length -gt $Limit) {
    return [pscustomobject]@{ Status = "tooLarge"; Value = $null; Error = $null; Sha256 = $sha; SizeBytes = $item.Length }
  }
  try {
    $value = ConvertFrom-GpPlistText -Text ([System.IO.File]::ReadAllText($item.FullName))
    if ($value -isnot [System.Collections.IDictionary]) { throw "the top level is not a dictionary" }
    return [pscustomobject]@{ Status = "ok"; Value = $value; Error = $null; Sha256 = $sha; SizeBytes = $item.Length }
  } catch {
    return [pscustomobject]@{ Status = "malformed"; Value = $null; Error = $_.Exception.Message; Sha256 = $sha; SizeBytes = $item.Length }
  }
}

function Get-GpPlistString {
  param($Dictionary, [Parameter(Mandatory = $true)][string]$Key)
  if ($Dictionary -isnot [System.Collections.IDictionary] -or -not $Dictionary.Contains($Key)) { return $null }
  $value = $Dictionary[$Key]
  if ($value -is [string] -and -not [string]::IsNullOrWhiteSpace($value)) { return $value }
  if ($value -is [long] -or $value -is [int] -or $value -is [double]) { return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0}", $value) }
  return $null
}

# --- Paths ---------------------------------------------------------------------

function ConvertTo-GpPayloadRelativePath {
  param([Parameter(Mandatory = $true)][string]$PayloadRoot, [Parameter(Mandatory = $true)][string]$Path)
  $relative = [System.IO.Path]::GetRelativePath([System.IO.Path]::GetFullPath($PayloadRoot), [System.IO.Path]::GetFullPath($Path)) -replace "\\", "/"
  if ($relative -eq ".." -or $relative.StartsWith("../", [System.StringComparison]::Ordinal) -or [System.IO.Path]::IsPathRooted($relative)) {
    throw "path is outside the payload: $Path"
  }
  return $relative
}

# Every <Name>.theme directory whose parent is named Themes, anywhere in the
# payload, not descending into a theme bundle. Sorted for stable output.
function Find-GpPayloadThemeBundles {
  param([Parameter(Mandatory = $true)][string]$PayloadRoot)
  if (-not (Test-Path -LiteralPath $PayloadRoot -PathType Container)) { return @() }
  $found = [System.Collections.Generic.List[string]]::new()
  $queue = [System.Collections.Generic.Queue[System.IO.DirectoryInfo]]::new()
  $queue.Enqueue([System.IO.DirectoryInfo]::new([System.IO.Path]::GetFullPath($PayloadRoot)))
  while ($queue.Count -gt 0) {
    $dir = $queue.Dequeue()
    foreach ($child in @($dir.GetDirectories())) {
      # Don't follow links: a theme reached only through one isn't in the payload.
      if (($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
      if ($child.Name.EndsWith(".theme", [System.StringComparison]::Ordinal) -and $dir.Name -eq "Themes") {
        $found.Add($child.FullName) | Out-Null
        continue
      }
      $queue.Enqueue($child)
    }
  }
  # Callers wrap the result in @(); a single path comes back as a string.
  return @($found | Sort-Object { ConvertTo-GpPayloadRelativePath -PayloadRoot $PayloadRoot -Path $_ })
}

# The real location of Path: every symbolic link along it resolved, at most 40
# hops. Returns $null for a loop, a link that can't be read, or a path that
# doesn't exist once resolved.
function Resolve-GpRealPath {
  param([Parameter(Mandatory = $true)][string]$Path)

  $full = [System.IO.Path]::GetFullPath($Path)
  $root = [System.IO.Path]::GetPathRoot($full)
  $pending = [System.Collections.Generic.List[string]]::new()
  foreach ($part in ($full.Substring($root.Length) -split '[\\/]')) { if ($part -ne "") { $pending.Add($part) | Out-Null } }
  $current = $root
  $hops = 0
  while ($pending.Count -gt 0) {
    $part = $pending[0]
    $pending.RemoveAt(0)
    if ($part -eq ".") { continue }
    if ($part -eq "..") { $current = [System.IO.Path]::GetDirectoryName($current.TrimEnd('\', '/')); if ($null -eq $current) { $current = $root }; continue }
    $next = Join-Path $current $part
    $info = if ([System.IO.Directory]::Exists($next)) { [System.IO.DirectoryInfo]::new($next) } else { [System.IO.FileInfo]::new($next) }
    if (-not $info.Exists -and $null -eq $info.LinkTarget) { return $null }
    if ($null -ne $info.LinkTarget) {
      $hops++
      if ($hops -gt 40) { return $null }
      $target = [string]$info.LinkTarget
      if (-not [System.IO.Path]::IsPathRooted($target)) { $target = Join-Path $current $target }
      $target = [System.IO.Path]::GetFullPath($target)
      $targetRoot = [System.IO.Path]::GetPathRoot($target)
      $parts = @($target.Substring($targetRoot.Length) -split '[\\/]' | Where-Object { $_ -ne "" })
      for ($i = $parts.Count - 1; $i -ge 0; $i--) { $pending.Insert(0, $parts[$i]) }
      $current = $targetRoot
      continue
    }
    $current = $next
  }
  return $current
}

# Whether a file may be read for the metadata. "ok": it exists and its real
# location, every link resolved, is inside the payload's real root.
# "unavailable": it exists, but resolves outside the payload, through a loop,
# or to something that isn't a file; it isn't read. "absent": nothing there.
function Get-GpPayloadFileStatus {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$PayloadRoot)

  $lexical = [System.IO.Path]::GetFullPath($Path)
  $exists = [System.IO.File]::Exists($lexical) -or [System.IO.Directory]::Exists($lexical)
  $isLink = $false
  try { $isLink = $null -ne ([System.IO.FileInfo]::new($lexical)).LinkTarget } catch { $isLink = $false }
  if (-not $exists -and -not $isLink) { return "absent" }

  $realRoot = Resolve-GpRealPath -Path $PayloadRoot
  $real = Resolve-GpRealPath -Path $lexical
  if ($null -eq $realRoot -or $null -eq $real) { return "unavailable" }
  $base = $realRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
  if (-not $real.StartsWith($base, [System.StringComparison]::Ordinal)) { return "unavailable" }
  if (-not [System.IO.File]::Exists($real)) { return "unavailable" }
  return "ok"
}

# The first candidate that exists, with whether it may be read. A candidate
# that exists but leaves the payload stops the search, as it would stop a
# loader that looks in the same order; it is reported, not read.
function Get-GpFirstPayloadFile {
  param([string[]]$Candidates, [Parameter(Mandatory = $true)][string]$PayloadRoot)
  foreach ($candidate in @($Candidates)) {
    $status = Get-GpPayloadFileStatus -Path $candidate -PayloadRoot $PayloadRoot
    if ($status -ne "absent") { return [pscustomobject]@{ Path = $candidate; Status = $status } }
  }
  return [pscustomobject]@{ Path = $null; Status = "absent" }
}

# --- One theme -------------------------------------------------------------------

# The new v2 fields for one theme bundle: identity, installation, settings.
function Get-GpThemeBundleDescriptor {
  param(
    [Parameter(Mandatory = $true)][string]$BundlePath,
    [Parameter(Mandatory = $true)][string]$PayloadRoot
  )

  $name = [System.IO.Path]::GetFileNameWithoutExtension($BundlePath)
  $resources = Join-Path $BundlePath "Resources"

  $infoFile = Get-GpFirstPayloadFile -PayloadRoot $PayloadRoot -Candidates @(
    (Join-Path $resources "Info-gnustep.plist"),
    (Join-Path $resources "Info.plist"),
    (Join-Path (Join-Path $BundlePath "Contents") "Info.plist"),
    (Join-Path $BundlePath "Info.plist")
  )
  $info = $null
  $infoStatus = $infoFile.Status
  $infoSha = $null
  if ($infoFile.Status -eq "ok") {
    $read = Read-GpLimitedPlistFile -Path $infoFile.Path -Limit $script:GpThemeInfoPlistLimit
    $infoStatus = $read.Status
    $infoSha = $read.Sha256
    if ($read.Status -eq "ok") { $info = $read.Value }
  }

  # Only the candidate paths: Test-GpThemeBundleStructure would also read the
  # Info plist, following any link.
  $executableFile = Get-GpFirstPayloadFile -PayloadRoot $PayloadRoot -Candidates @(Get-GpThemeExecutableCandidates -ThemePath $BundlePath -ThemeName $name -Backend "appimage")
  $executableStatus = $executableFile.Status
  $executableSha = if ($executableStatus -eq "ok") { Get-GpFileSha256 -Path $executableFile.Path } else { $null }

  # Same order as the theme-settings loader: Resources, then a macOS-style
  # Contents/Resources, then the bundle root.
  $settingsFile = Get-GpFirstPayloadFile -PayloadRoot $PayloadRoot -Candidates @(
    (Join-Path $resources "ThemeSettings.plist"),
    (Join-Path (Join-Path (Join-Path $BundlePath "Contents") "Resources") "ThemeSettings.plist"),
    (Join-Path $BundlePath "ThemeSettings.plist")
  )
  $settingsPath = $settingsFile.Path
  $settings = $null
  $themeId = $null
  if ($settingsFile.Status -eq "unavailable") {
    $settings = [ordered]@{ status = "unavailable"; schemaVersion = $null; sha256 = $null; sizeBytes = $null; inline = $null; path = (ConvertTo-GpPayloadRelativePath -PayloadRoot $PayloadRoot -Path $settingsPath); note = "a link leads outside the payload (or loops), so it was not read; its contents are unavailable" }
  } elseif ($settingsFile.Status -eq "ok") {
    $read = Read-GpLimitedPlistFile -Path $settingsPath -Limit $script:GpThemeSettingsInlineLimit
    $relative = ConvertTo-GpPayloadRelativePath -PayloadRoot $PayloadRoot -Path $settingsPath
    switch ($read.Status) {
      "ok" {
        $themeId = Get-GpPlistString -Dictionary $read.Value -Key "ThemeIdentifier"
        $schemaVersion = $null
        if ($read.Value.Contains("SchemaVersion") -and ($read.Value["SchemaVersion"] -is [long] -or $read.Value["SchemaVersion"] -is [string])) {
          $parsed = 0
          if ([int]::TryParse([string]$read.Value["SchemaVersion"], [ref]$parsed)) { $schemaVersion = $parsed }
        }
        $settings = [ordered]@{ status = "inline"; schemaVersion = $schemaVersion; sha256 = $read.Sha256; sizeBytes = $read.SizeBytes; inline = $read.Value; path = $relative; note = $null }
      }
      "tooLarge" {
        $settings = [ordered]@{ status = "notInlined"; schemaVersion = $null; sha256 = $read.Sha256; sizeBytes = $read.SizeBytes; inline = $null; path = $relative; note = ("larger than {0} bytes, so not inlined; its contents (theme id, schema version, settings) are unavailable without reading the AppImage" -f $script:GpThemeSettingsInlineLimit) }
      }
      default {
        $settings = [ordered]@{ status = "malformed"; schemaVersion = $null; sha256 = $read.Sha256; sizeBytes = $read.SizeBytes; inline = $null; path = $relative; note = ("could not be parsed: {0}" -f $read.Error) }
      }
    }
  }

  return [ordered]@{
    name = $name
    bundledPath = ConvertTo-GpPayloadRelativePath -PayloadRoot $PayloadRoot -Path $BundlePath
    themeId = $themeId
    bundleId = Get-GpPlistString -Dictionary $info -Key "CFBundleIdentifier"
    version = Get-GpPlistString -Dictionary $info -Key "CFBundleVersion"
    shortVersion = Get-GpPlistString -Dictionary $info -Key "CFBundleShortVersionString"
    infoStatus = $infoStatus
    installation = [ordered]@{
      bundledPath = ConvertTo-GpPayloadRelativePath -PayloadRoot $PayloadRoot -Path $BundlePath
      executableSha256 = $executableSha
      executableStatus = $executableStatus
      infoPlistSha256 = $infoSha
    }
    settings = $settings
  }
}

# --- Domains and GSTheme sources ------------------------------------------------

# The domain the running app most likely reads: the app's CFBundleIdentifier
# when its Info plist has a non-empty one, else the process name (the launch
# entry's file name). Unknown when there is an app bundle whose plist can't be read.
function Get-GpAppRuntimeDomainHint {
  param(
    [Parameter(Mandatory = $true)][string]$PayloadRoot,
    [Parameter(Mandatory = $true)][string]$EntryRelativePath
  )

  $entry = Join-Path $PayloadRoot ($EntryRelativePath -replace "/", [System.IO.Path]::DirectorySeparatorChar)
  $executable = [System.IO.Path]::GetFileNameWithoutExtension($entry)
  $bundleDir = Split-Path -Parent $entry
  $bundleId = $null
  $status = "noBundle"
  if ($bundleDir.EndsWith(".app", [System.StringComparison]::OrdinalIgnoreCase)) {
    $infoFile = Get-GpFirstPayloadFile -PayloadRoot $PayloadRoot -Candidates @(
      (Join-Path (Join-Path $bundleDir "Resources") "Info-gnustep.plist"),
      (Join-Path (Join-Path $bundleDir "Resources") "Info.plist"),
      (Join-Path (Join-Path $bundleDir "Contents") "Info.plist")
    )
    if ($infoFile.Status -eq "absent") {
      $status = "noInfoPlist"
    } elseif ($infoFile.Status -eq "unavailable") {
      $status = "unavailable"
    } else {
      $read = Read-GpLimitedPlistFile -Path $infoFile.Path -Limit $script:GpThemeInfoPlistLimit
      $status = $read.Status
      if ($read.Status -eq "ok") { $bundleId = Get-GpPlistString -Dictionary $read.Value -Key "CFBundleIdentifier" }
    }
  }

  if ($null -ne $bundleId) {
    return [ordered]@{ executable = $executable; bundleIdentifier = $bundleId; runtimeDomainHint = $bundleId; runtimeDomainHintSource = "bundleIdentifier" }
  }
  if ($status -in @("noBundle", "noInfoPlist", "ok")) {
    return [ordered]@{ executable = $executable; bundleIdentifier = $null; runtimeDomainHint = $executable; runtimeDomainHintSource = "processName" }
  }
  # An app bundle whose Info plist is too large, malformed or behind a link that
  # leaves the payload: its identifier,
  # and so the domain, is unknown. Don't guess the process name.
  return [ordered]@{ executable = $executable; bundleIdentifier = $null; runtimeDomainHint = $null; runtimeDomainHintSource = "unknown" }
}

# The GSTheme sources the packager controls, ranked (1 wins over 2). The env
# entry has no rank: gnustep-gui picks the theme from NSUserDefaults alone
# (GSTheme.m, gui 9bd1123a1), whose search list has no environment domain
# (NSUserDefaults.m, base 6479d4483), and AppRun doesn't turn the variable into
# a -GSTheme argument. So it is recorded as exported but not read by GNUstep.
function Get-GpThemeDefaultsDescriptor {
  param(
    $AppDefaults,
    $LaunchEnvironment,
    $GlobalDefaultTheme,
    $RuntimeDomainHint
  )

  $seedDomain = $null
  $seeds = @()
  if ($null -ne $AppDefaults -and @($AppDefaults.Entries | Where-Object { $_.Key -eq "GSTheme" }).Count -gt 0) {
    $seedDomain = [string]$AppDefaults.Domain
    $seeds = @(@($AppDefaults.Entries | Where-Object { $_.Key -eq "GSTheme" }) | ForEach-Object {
      [ordered]@{ key = "GSTheme"; value = [string]$_.Value; policy = "each-launch-if-absent"; rank = 1 }
    })
  }

  $envEntries = @()
  if ($LaunchEnvironment -is [System.Collections.IDictionary] -and $LaunchEnvironment.Contains("GSTheme")) {
    $entry = $LaunchEnvironment["GSTheme"]
    $value = if ($entry -is [System.Collections.IDictionary]) { [string]$entry["value"] } else { [string]$entry }
    $policy = if ($entry -is [System.Collections.IDictionary] -and $entry.Contains("policy")) { [string]$entry["policy"] } else { "override" }
    $envEntries = @([ordered]@{ key = "GSTheme"; value = $value; policy = $policy; rank = $null; effect = "not read by gnustep-base/gui; informational only" })
  }

  $globalTheme = $null
  if ($null -ne $GlobalDefaultTheme -and -not [string]::IsNullOrWhiteSpace([string]$GlobalDefaultTheme.Name)) {
    $globalTheme = [ordered]@{ value = [string]$GlobalDefaultTheme.Name; desktops = [string[]]@($GlobalDefaultTheme.Desktops); rank = 2 }
  }

  $domainMatch = $null
  if ($null -ne $seedDomain -and $null -ne $RuntimeDomainHint) {
    $domainMatch = ($seedDomain -ceq [string]$RuntimeDomainHint)
  }

  return [ordered]@{
    seedDomain = $seedDomain
    seedDomainMatchesRuntimeHint = $domainMatch
    seeds = @($seeds)
    env = @($envEntries)
    globalDefaultsTheme = $globalTheme
  }
}

function Get-GpThemeSearchDescriptor {
  param($GnustepConfig)
  $enabled = ($null -ne $GnustepConfig -and [bool]$GnustepConfig.Enabled)
  $userLibrary = if ($enabled -and -not [string]::IsNullOrWhiteSpace([string]$GnustepConfig.UserLibraryRelative)) { "~/" + [string]$GnustepConfig.UserLibraryRelative } else { "~/GNUstep/Library" }
  return [ordered]@{
    gnustepConfig = $enabled
    userLibrary = $userLibrary
    # Without the AppImage's GNUstep.conf the app reads the one its gnustep-base
    # was built with, so the host's domains apply and the payload's Themes
    # directories are searched only if that configuration names them.
    order = $(if ($enabled) { @("user", "payload") } else { @("user", "host-configured") })
  }
}

# --- Documents -------------------------------------------------------------------

# The formatVersion 2 report: v1's fields (from the payload's existing report,
# when themeInputs wrote one) plus the new fields, for every theme in the
# payload. Returns $null when the payload has no themes and no v1 report.
function New-GpAppImageThemeReport {
  param(
    [Parameter(Mandatory = $true)][string]$PayloadRoot,
    $ExistingReport,
    [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Package,
    [Parameter(Mandatory = $true)][string]$EntryRelativePath,
    $AppDefaults,
    $LaunchEnvironment,
    $GnustepConfig
  )

  $bundles = @(Find-GpPayloadThemeBundles -PayloadRoot $PayloadRoot)
  $v1Themes = @()
  if ($ExistingReport -is [System.Collections.IDictionary] -and $ExistingReport.Contains("themes")) {
    $v1Themes = @($ExistingReport["themes"] | Where-Object { $_ -is [System.Collections.IDictionary] })
  }
  if ($bundles.Count -eq 0 -and $v1Themes.Count -eq 0) { return $null }

  $byPath = @{}
  foreach ($bundle in $bundles) { $byPath[(ConvertTo-GpPayloadRelativePath -PayloadRoot $PayloadRoot -Path $bundle)] = $bundle }

  $themes = [System.Collections.Generic.List[object]]::new()
  $claimed = @{}
  foreach ($v1 in $v1Themes) {
    $item = [ordered]@{}
    foreach ($key in @($v1.Keys)) { $item[$key] = $v1[$key] }
    # v1's stagedPath is relative to the stage root, which the AppDir copies under usr/.
    $payloadPath = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$v1["stagedPath"])) {
      $payloadPath = "usr/" + (([string]$v1["stagedPath"]) -replace "\\", "/").TrimStart("/")
    }
    if ($null -ne $payloadPath -and $byPath.ContainsKey($payloadPath)) {
      $descriptor = Get-GpThemeBundleDescriptor -BundlePath $byPath[$payloadPath] -PayloadRoot $PayloadRoot
      $claimed[$payloadPath] = $true
    } else {
      $descriptor = [ordered]@{ name = [string]$v1["name"]; bundledPath = $payloadPath; themeId = $null; bundleId = $null; version = $null; shortVersion = $null; infoStatus = "missing"; installation = $null; settings = $null }
    }
    foreach ($key in @($descriptor.Keys)) { if ($key -ne "name") { $item[$key] = $descriptor[$key] } }
    $item["origin"] = "themeInputs"
    $themes.Add($item) | Out-Null
  }

  foreach ($path in @($byPath.Keys | Sort-Object)) {
    if ($claimed.ContainsKey($path)) { continue }
    $descriptor = Get-GpThemeBundleDescriptor -BundlePath $byPath[$path] -PayloadRoot $PayloadRoot
    $item = [ordered]@{
      name = $descriptor["name"]
      source = $null
      required = $false
      default = $false
      backend = "appimage"
      stagedPath = $(if ($path.StartsWith("usr/", [System.StringComparison]::Ordinal)) { $path.Substring(4) } else { $path })
      executable = $null
      info = $null
      resources = @()
      validationIssues = @()
    }
    foreach ($key in @($descriptor.Keys)) { if ($key -ne "name") { $item[$key] = $descriptor[$key] } }
    $item["origin"] = "stage"
    $themes.Add($item) | Out-Null
  }

  $app = Get-GpAppRuntimeDomainHint -PayloadRoot $PayloadRoot -EntryRelativePath ("usr/" + ($EntryRelativePath -replace "\\", "/").TrimStart("/"))
  $defaults = Get-GpThemeDefaultsDescriptor -AppDefaults $AppDefaults -LaunchEnvironment $LaunchEnvironment -GlobalDefaultTheme $(if ($null -ne $GnustepConfig) { $GnustepConfig.DefaultTheme } else { $null }) -RuntimeDomainHint $app["runtimeDomainHint"]

  return [ordered]@{
    formatVersion = 2
    generatedAt = $(if ($ExistingReport -is [System.Collections.IDictionary] -and $ExistingReport.Contains("generatedAt")) { $ExistingReport["generatedAt"] } else { (Get-Date).ToUniversalTime().ToString("o") })
    package = [ordered]@{ id = [string]$Package["id"]; name = [string]$Package["name"]; version = [string]$Package["version"] }
    app = $app
    defaults = $defaults
    search = Get-GpThemeSearchDescriptor -GnustepConfig $GnustepConfig
    themes = @($themes.ToArray())
  }
}

# The sidecar: the report's discovery fields, bound to one AppImage file.
function New-GpAppImageThemeSidecar {
  param(
    [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Report,
    [Parameter(Mandatory = $true)][string]$ArtifactPath,
    [string]$Architecture,
    [string]$GeneratorVersion
  )

  $artifact = Get-Item -LiteralPath $ArtifactPath
  $themes = @(foreach ($theme in @($Report["themes"])) {
    [ordered]@{
      name = $theme["name"]
      themeId = $theme["themeId"]
      bundleId = $theme["bundleId"]
      version = $theme["version"]
      shortVersion = $theme["shortVersion"]
      infoStatus = $theme["infoStatus"]
      installation = $theme["installation"]
      source = $(if ($theme["origin"] -eq "themeInputs" -and $theme["source"] -is [System.Collections.IDictionary]) { [ordered]@{ repo = $theme["source"]["repo"]; commit = $theme["source"]["resolvedCommit"] } } else { $null })
      origin = $theme["origin"]
      settings = $theme["settings"]
    }
  })

  return [ordered]@{
    schema = 1
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    generator = [ordered]@{ name = "gnustep-packager"; version = $GeneratorVersion }
    appimage = [ordered]@{ fileName = $artifact.Name; sizeBytes = $artifact.Length; sha256 = Get-GpFileSha256 -Path $artifact.FullName; architecture = $Architecture }
    package = $Report["package"]
    app = $Report["app"]
    defaults = $Report["defaults"]
    search = $Report["search"]
    themes = @($themes)
  }
}

# True when the sidecar names this exact file: same name and same sha256.
function Test-GpAppImageThemeSidecarBinding {
  param([Parameter(Mandatory = $true)][string]$SidecarPath, [Parameter(Mandatory = $true)][string]$ArtifactPath)
  $sidecar = Get-Content -Raw -LiteralPath $SidecarPath | ConvertFrom-Json -AsHashtable
  $artifact = Get-Item -LiteralPath $ArtifactPath
  return ($sidecar["schema"] -eq 1 -and [string]$sidecar["appimage"]["fileName"] -ceq $artifact.Name -and [string]$sidecar["appimage"]["sha256"] -eq (Get-GpFileSha256 -Path $artifact.FullName))
}

function Write-GpJsonDocument {
  param([Parameter(Mandatory = $true)]$Document, [Parameter(Mandatory = $true)][string]$Path)
  $Document | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $Path -Encoding utf8
}

# --- AppImage backend hooks ------------------------------------------------------

# Writes the formatVersion 2 report into the AppDir's metadata root, replacing
# the v1 copy staged there (the stage's own v1 report, which the theme-reuse
# check reads, is untouched). Returns its path, or $null when the payload has
# no themes.
function Write-GpAppImageThemeReport {
  param(
    [Parameter(Mandatory = $true)][psobject]$Context,
    [Parameter(Mandatory = $true)][psobject]$Config,
    [Parameter(Mandatory = $true)][string]$AppDirRoot,
    [Parameter(Mandatory = $true)][string]$MetadataRoot,
    [string]$LogPath
  )

  $reportPath = Join-Path $MetadataRoot "gnustep-packager-theme-report.json"
  $existing = $null
  if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
    try { $existing = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json -AsHashtable } catch { $existing = $null }
  }
  $launch = Get-GpLaunchContract -Context $Context
  $report = New-GpAppImageThemeReport -PayloadRoot $AppDirRoot -ExistingReport $existing -Package $Context.Manifest["package"] `
    -EntryRelativePath $launch.EntryRelativePath -AppDefaults (Get-GpAppImageAppDomainDefaults -Context $Context) `
    -LaunchEnvironment $launch.Environment -GnustepConfig $Config.GnustepConfig
  if ($null -eq $report) { return $null }
  Write-GpJsonDocument -Document $report -Path $reportPath
  Write-GpAppImageLogLine -LogPath $LogPath -Message ("Wrote theme report (formatVersion 2, {0} theme(s)): {1}" -f @($report["themes"]).Count, $reportPath)
  return $reportPath
}

# Writes <artifact-base>.themes.json beside the AppImage, bound to it by name
# and sha256. Returns its path, or $null when the AppDir has no theme report.
function Write-GpAppImageThemeSidecar {
  param(
    [Parameter(Mandatory = $true)][psobject]$Config,
    [Parameter(Mandatory = $true)][psobject]$AppDir,
    [Parameter(Mandatory = $true)][string]$ArtifactPath,
    [string]$LogPath
  )

  $sidecarPath = Get-GpArtifactSidecarPath -ArtifactPath $ArtifactPath -Suffix "themes.json"
  if ([string]::IsNullOrWhiteSpace([string]$AppDir.ThemeReportPath) -or -not (Test-Path -LiteralPath $AppDir.ThemeReportPath -PathType Leaf)) {
    # A sidecar left from an earlier build would describe another AppImage.
    if (Test-Path -LiteralPath $sidecarPath -PathType Leaf) { Remove-Item -LiteralPath $sidecarPath -Force }
    return $null
  }
  $report = Get-Content -Raw -LiteralPath $AppDir.ThemeReportPath | ConvertFrom-Json -AsHashtable
  $sidecar = New-GpAppImageThemeSidecar -Report $report -ArtifactPath $ArtifactPath -Architecture ([string]$Config.Architecture) -GeneratorVersion $null
  Write-GpJsonDocument -Document $sidecar -Path $sidecarPath
  Write-GpAppImageLogLine -LogPath $LogPath -Message ("Wrote theme metadata sidecar: {0}" -f $sidecarPath)
  return $sidecarPath
}
