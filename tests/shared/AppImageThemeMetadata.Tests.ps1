Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# backends/appimage/lib/theme-metadata.ps1: the formatVersion 2 theme report and
# the <artifact-base>.themes.json sidecar. Fixtures are plain directories; no
# appimagetool, mount or theme code is involved.
Describe "AppImage theme metadata" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
    . (Join-Path $script:repoRoot "scripts\lib\core.ps1")
    . (Join-Path $script:repoRoot "backends\appimage\lib\appimage.ps1")

    function New-GpTestFile {
      param([string]$Path, [string]$Text)
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
      [System.IO.File]::WriteAllText($Path, $Text)
    }

    function New-GpTestTheme {
      param([string]$ThemesDir, [string]$Name, $InfoText, $SettingsText)
      $bundle = Join-Path $ThemesDir "$Name.theme"
      New-GpTestFile -Path (Join-Path $bundle $Name) -Text "not really a shared object"
      if ($null -ne $InfoText) { New-GpTestFile -Path (Join-Path $bundle "Resources/Info-gnustep.plist") -Text $InfoText }
      if ($null -ne $SettingsText) { New-GpTestFile -Path (Join-Path $bundle "Resources/ThemeSettings.plist") -Text $SettingsText }
      return $bundle
    }

    function New-GpAppDefaults {
      param([string]$Domain, [string]$Theme)
      return [pscustomobject]@{
        Domain = $Domain
        Entries = @([pscustomobject]@{ Key = "GSTheme"; Type = "string"; Value = $Theme; SerializedValue = ('"{0}"' -f $Theme) })
      }
    }

    function New-GpReport {
      param($ExistingReport = $null, $AppDefaults = $null, $LaunchEnvironment = @{}, $GnustepConfig = $null)
      return New-GpAppImageThemeReport -PayloadRoot $script:payload -ExistingReport $ExistingReport `
        -Package ([ordered]@{ id = "org.example.Pkg"; name = "Pkg"; version = "1.2.3" }) `
        -EntryRelativePath "app/Foo.app/Foo" -AppDefaults $AppDefaults -LaunchEnvironment $LaunchEnvironment -GnustepConfig $GnustepConfig
    }
  }

  BeforeEach {
    $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-theme-meta-" + [guid]::NewGuid().ToString("N"))
    $script:payload = Join-Path $script:root "AppDir"
    $script:systemThemes = Join-Path $script:payload "usr/GNUstep/System/Library/Themes"
    $script:runtimeThemes = Join-Path $script:payload "usr/runtime/lib/GNUstep/Themes"
    New-GpTestFile -Path (Join-Path $script:payload "usr/app/Foo.app/Foo") -Text "app"
    New-GpTestFile -Path (Join-Path $script:payload "usr/app/Foo.app/Resources/Info-gnustep.plist") -Text "{ CFBundleIdentifier = org.example.App; NSExecutable = Foo; }"
  }

  AfterEach {
    Remove-Item -Recurse -Force -LiteralPath $script:root -ErrorAction SilentlyContinue
  }

  Context "property lists" {
    It "reads OpenStep plists with comments, quoting, escapes and nesting" {
      $text = @'
/* header */ {
  // a comment
  CFBundleIdentifier = "org.gnustep.Adwaita";
  CFBundleVersion = 1.4;
  Name = "Tab\there \"quoted\" \U00e9";
  List = ( a, "b c", { k = v; } );
  Blob = <0fA1 22>;
}
'@
      $value = ConvertFrom-GpPlistText -Text $text
      $value["CFBundleIdentifier"] | Should -Be "org.gnustep.Adwaita"
      $value["CFBundleVersion"] | Should -Be "1.4"
      $value["Name"] | Should -Be ("Tab`there `"quoted`" " + [char]0xe9)
      @($value["List"]).Count | Should -Be 3
      $value["List"][2]["k"] | Should -Be "v"
      $value["Blob"] | Should -Be "0fA122"
    }

    It "reads XML plists, keeping numbers and booleans, without resolving a DTD" {
      $text = @'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>ThemeIdentifier</key><string>org.example.adwaita</string>
  <key>SchemaVersion</key><integer>1</integer>
  <key>Dark</key><true/>
  <key>Accents</key><array><string>blue</string><real>0.5</real></array>
</dict></plist>
'@
      $value = ConvertFrom-GpPlistText -Text $text
      $value["ThemeIdentifier"] | Should -Be "org.example.adwaita"
      $value["SchemaVersion"] | Should -Be 1
      $value["Dark"] | Should -BeTrue
      $value["Accents"][1] | Should -Be 0.5
    }

    It "rejects malformed plists" {
      { ConvertFrom-GpPlistText -Text "{ a = b " } | Should -Throw
      { ConvertFrom-GpPlistText -Text "{ a b; }" } | Should -Throw
      { ConvertFrom-GpPlistText -Text "<plist><dict><key>a</key></dict></plist>" } | Should -Throw
      { ConvertFrom-GpPlistText -Text '{ a = "unterminated; }' } | Should -Throw
    }
  }

  Context "discovery" {
    It "lists themeInputs and stage-script themes once each, keeping every v1 field" {
      New-GpTestTheme -ThemesDir $script:systemThemes -Name "Adwaita" -InfoText "{ CFBundleIdentifier = org.gnustep.Adwaita; CFBundleVersion = 14; CFBundleShortVersionString = 1.4.0; }" -SettingsText "{ ThemeIdentifier = org.example.adwaita; SchemaVersion = 1; }" | Out-Null
      New-GpTestTheme -ThemesDir $script:runtimeThemes -Name "Plain" -InfoText "{ CFBundleIdentifier = org.example.Plain; }" -SettingsText $null | Out-Null
      $v1 = [ordered]@{
        formatVersion = 1
        generatedAt = "2026-11-10T00:00:00.0000000Z"
        package = [ordered]@{ id = "org.example.Pkg"; name = "Pkg"; version = "1.2.3" }
        themes = @([ordered]@{
          name = "Adwaita"
          source = [ordered]@{ repo = "https://example.invalid/adwaita.git"; workspacePath = $null; sourcePath = $null; ref = "main"; resolvedCommit = "abc123" }
          required = $true; default = $true; backend = "appimage"
          stagedPath = "GNUstep/System/Library/Themes/Adwaita.theme"
          executable = "x"; info = "y"; resources = @("Resources/a.png"); validationIssues = @()
        })
      }

      $report = New-GpReport -ExistingReport $v1

      $report["formatVersion"] | Should -Be 2
      $report["generatedAt"] | Should -Be "2026-11-10T00:00:00.0000000Z"
      @($report["themes"]).Count | Should -Be 2
      $adwaita = @($report["themes"] | Where-Object { $_["name"] -eq "Adwaita" })[0]
      $adwaita["origin"] | Should -Be "themeInputs"
      foreach ($key in @("source", "required", "default", "backend", "stagedPath", "executable", "info", "resources", "validationIssues")) { $adwaita.Contains($key) | Should -BeTrue }
      $adwaita["source"]["resolvedCommit"] | Should -Be "abc123"
      $adwaita["required"] | Should -BeTrue
      $adwaita["themeId"] | Should -Be "org.example.adwaita"
      $adwaita["bundleId"] | Should -Be "org.gnustep.Adwaita"
      $adwaita["version"] | Should -Be "14"
      $adwaita["shortVersion"] | Should -Be "1.4.0"
      $adwaita["installation"]["bundledPath"] | Should -Be "usr/GNUstep/System/Library/Themes/Adwaita.theme"
      $plain = @($report["themes"] | Where-Object { $_["name"] -eq "Plain" })[0]
      $plain["origin"] | Should -Be "stage"
      $plain["source"] | Should -BeNullOrEmpty
      $plain["stagedPath"] | Should -Be "runtime/lib/GNUstep/Themes/Plain.theme"
      $plain["settings"] | Should -BeNullOrEmpty
      $plain["themeId"] | Should -BeNullOrEmpty
    }

    It "keeps a themeInputs entry whose bundle is missing, marked missing, not dropped" {
      $v1 = [ordered]@{ formatVersion = 1; themes = @([ordered]@{ name = "Gone"; stagedPath = "GNUstep/System/Library/Themes/Gone.theme"; source = $null }) }
      $report = New-GpReport -ExistingReport $v1
      $gone = @($report["themes"])[0]
      $gone["infoStatus"] | Should -Be "missing"
      $gone["installation"] | Should -BeNullOrEmpty
    }

    It "writes no report when the payload has no themes" {
      New-GpReport | Should -BeNullOrEmpty
    }

    It "uses only payload-relative paths" {
      New-GpTestTheme -ThemesDir $script:systemThemes -Name "Adwaita" -InfoText "{ }" -SettingsText "{ ThemeIdentifier = x; }" | Out-Null
      $json = (New-GpReport) | ConvertTo-Json -Depth 40
      $json | Should -Not -Match ([regex]::Escape($script:root))
      $json | Should -Not -Match "/tmp/\.mount_"
      $json | Should -Match '"bundledPath": "usr/GNUstep/System/Library/Themes/Adwaita.theme"'
    }

    It "doesn't follow a link to a Themes directory outside the payload" -Skip:($IsWindows) {
      $outside = Join-Path $script:root "outside/Themes"
      New-GpTestTheme -ThemesDir $outside -Name "Evil" -InfoText "{ }" -SettingsText $null | Out-Null
      New-Item -ItemType Directory -Force -Path (Join-Path $script:payload "usr/lib") | Out-Null
      New-Item -ItemType SymbolicLink -Path (Join-Path $script:payload "usr/lib/linked") -Target (Split-Path -Parent $outside) | Out-Null
      New-GpReport | Should -BeNullOrEmpty
    }
  }

  Context "links inside a theme bundle" {
    BeforeEach {
      $script:outside = Join-Path $script:root "outside"
      New-GpTestFile -Path (Join-Path $script:outside "Resources/Info-gnustep.plist") -Text "{ CFBundleIdentifier = org.example.Leaked; }"
      New-GpTestFile -Path (Join-Path $script:outside "Resources/ThemeSettings.plist") -Text "{ ThemeIdentifier = leaked; Secret = leaked; }"
      New-GpTestFile -Path (Join-Path $script:outside "Linked") -Text "outside executable"
    }

    It "doesn't read a Resources directory linked outside the payload" -Skip:($IsWindows) {
      $bundle = New-GpTestTheme -ThemesDir $script:systemThemes -Name "Linked" -InfoText $null -SettingsText $null
      New-Item -ItemType SymbolicLink -Path (Join-Path $bundle "Resources") -Target (Join-Path $script:outside "Resources") | Out-Null
      $theme = @((New-GpReport)["themes"])[0]
      $theme["infoStatus"] | Should -Be "unavailable"
      $theme["bundleId"] | Should -BeNullOrEmpty
      $theme["installation"]["infoPlistSha256"] | Should -BeNullOrEmpty
      $theme["settings"]["status"] | Should -Be "unavailable"
      $theme["settings"]["inline"] | Should -BeNullOrEmpty
      $theme["settings"]["sha256"] | Should -BeNullOrEmpty
      $theme["themeId"] | Should -BeNullOrEmpty
      ((New-GpReport) | ConvertTo-Json -Depth 40) | Should -Not -Match "leaked|Leaked"
    }

    It "doesn't read a settings file or an Info plist linked outside the payload" -Skip:($IsWindows) {
      $bundle = New-GpTestTheme -ThemesDir $script:systemThemes -Name "Linked" -InfoText $null -SettingsText $null
      New-Item -ItemType Directory -Force -Path (Join-Path $bundle "Resources") | Out-Null
      New-Item -ItemType SymbolicLink -Path (Join-Path $bundle "Resources/ThemeSettings.plist") -Target (Join-Path $script:outside "Resources/ThemeSettings.plist") | Out-Null
      New-Item -ItemType SymbolicLink -Path (Join-Path $bundle "Resources/Info-gnustep.plist") -Target (Join-Path $script:outside "Resources/Info-gnustep.plist") | Out-Null
      $theme = @((New-GpReport)["themes"])[0]
      $theme["settings"]["status"] | Should -Be "unavailable"
      $theme["settings"]["path"] | Should -Be "usr/GNUstep/System/Library/Themes/Linked.theme/Resources/ThemeSettings.plist"
      $theme["infoStatus"] | Should -Be "unavailable"
      ((New-GpReport) | ConvertTo-Json -Depth 40) | Should -Not -Match "leaked|Leaked"
    }

    It "doesn't hash an executable linked outside the payload" -Skip:($IsWindows) {
      $bundle = Join-Path $script:systemThemes "Linked.theme"
      New-Item -ItemType Directory -Force -Path $bundle | Out-Null
      New-Item -ItemType SymbolicLink -Path (Join-Path $bundle "Linked") -Target (Join-Path $script:outside "Linked") | Out-Null
      $theme = @((New-GpReport)["themes"])[0]
      $theme["installation"]["executableStatus"] | Should -Be "unavailable"
      $theme["installation"]["executableSha256"] | Should -BeNullOrEmpty
    }

    It "reads through a link that stays inside the payload" -Skip:($IsWindows) {
      $shared = Join-Path $script:payload "usr/share/adwaita-resources"
      New-GpTestFile -Path (Join-Path $shared "Info-gnustep.plist") -Text "{ CFBundleIdentifier = org.example.Inside; }"
      New-GpTestFile -Path (Join-Path $shared "ThemeSettings.plist") -Text "{ ThemeIdentifier = inside; }"
      $bundle = New-GpTestTheme -ThemesDir $script:systemThemes -Name "Inside" -InfoText $null -SettingsText $null
      New-Item -ItemType SymbolicLink -Path (Join-Path $bundle "Resources") -Target "../../../../../share/adwaita-resources" | Out-Null
      $theme = @((New-GpReport)["themes"])[0]
      $theme["infoStatus"] | Should -Be "ok"
      $theme["bundleId"] | Should -Be "org.example.Inside"
      $theme["settings"]["status"] | Should -Be "inline"
      $theme["themeId"] | Should -Be "inside"
      $theme["installation"]["executableStatus"] | Should -Be "ok"
    }

    It "treats a link loop as unavailable without hanging" -Skip:($IsWindows) {
      $bundle = New-GpTestTheme -ThemesDir $script:systemThemes -Name "Loop" -InfoText $null -SettingsText $null
      New-Item -ItemType Directory -Force -Path (Join-Path $bundle "Resources") | Out-Null
      New-Item -ItemType SymbolicLink -Path (Join-Path $bundle "Resources/a") -Target "b" | Out-Null
      New-Item -ItemType SymbolicLink -Path (Join-Path $bundle "Resources/b") -Target "a" | Out-Null
      New-Item -ItemType SymbolicLink -Path (Join-Path $bundle "Resources/ThemeSettings.plist") -Target "a" | Out-Null
      $theme = @((New-GpReport)["themes"])[0]
      $theme["settings"]["status"] | Should -Be "unavailable"
    }

    It "doesn't read the app's Info plist through a link outside the payload" -Skip:($IsWindows) {
      New-GpTestTheme -ThemesDir $script:systemThemes -Name "Adwaita" -InfoText "{ }" -SettingsText $null | Out-Null
      $appInfo = Join-Path $script:payload "usr/app/Foo.app/Resources/Info-gnustep.plist"
      Remove-Item -Force $appInfo
      New-Item -ItemType SymbolicLink -Path $appInfo -Target (Join-Path $script:outside "Resources/Info-gnustep.plist") | Out-Null
      $report = New-GpReport -AppDefaults (New-GpAppDefaults -Domain "org.example.Leaked" -Theme "Adwaita")
      $report["app"]["runtimeDomainHintSource"] | Should -Be "unknown"
      $report["app"]["runtimeDomainHint"] | Should -BeNullOrEmpty
      $report["app"]["bundleIdentifier"] | Should -BeNullOrEmpty
    }
  }

  Context "ThemeSettings.plist" {
    It "inlines a small settings file as data, never interpreting its strings" {
      New-GpTestTheme -ThemesDir $script:systemThemes -Name "Adwaita" -InfoText "{ }" -SettingsText '{ ThemeIdentifier = org.example.adwaita; SchemaVersion = 1; Command = "$(rm -rf ~) `x`"; }' | Out-Null
      $settings = @((New-GpReport)["themes"])[0]["settings"]
      $settings["status"] | Should -Be "inline"
      $settings["schemaVersion"] | Should -Be 1
      $settings["inline"]["Command"] | Should -Be '$(rm -rf ~) `x`'
      $settings["sha256"] | Should -Match '^[0-9a-f]{64}$'
      $settings["path"] | Should -Be "usr/GNUstep/System/Library/Themes/Adwaita.theme/Resources/ThemeSettings.plist"
    }

    It "doesn't inline a settings file over 256 KiB, and says its contents are unavailable" {
      $big = "{ ThemeIdentifier = org.example.big; Pad = `"" + ("x" * 270000) + "`"; }"
      New-GpTestTheme -ThemesDir $script:systemThemes -Name "Big" -InfoText "{ }" -SettingsText $big | Out-Null
      $theme = @((New-GpReport)["themes"])[0]
      $theme["settings"]["status"] | Should -Be "notInlined"
      $theme["settings"]["inline"] | Should -BeNullOrEmpty
      $theme["settings"]["sizeBytes"] | Should -BeGreaterThan 262144
      $theme["settings"]["sha256"] | Should -Match '^[0-9a-f]{64}$'
      $theme["settings"]["note"] | Should -Match "unavailable without reading the AppImage"
      $theme["themeId"] | Should -BeNullOrEmpty
      $theme["settings"]["schemaVersion"] | Should -BeNullOrEmpty
    }

    It "looks for settings in Resources, then Contents/Resources, then the bundle root" {
      $bundle = New-GpTestTheme -ThemesDir $script:systemThemes -Name "Mac" -InfoText "{ }" -SettingsText $null
      New-GpTestFile -Path (Join-Path $bundle "ThemeSettings.plist") -Text "{ ThemeIdentifier = root; }"
      New-GpTestFile -Path (Join-Path $bundle "Contents/Resources/ThemeSettings.plist") -Text "{ ThemeIdentifier = contents; }"
      @((New-GpReport)["themes"])[0]["themeId"] | Should -Be "contents"
      New-GpTestFile -Path (Join-Path $bundle "Resources/ThemeSettings.plist") -Text "{ ThemeIdentifier = resources; }"
      @((New-GpReport)["themes"])[0]["themeId"] | Should -Be "resources"
    }

    It "records a malformed settings file as malformed, with no contents" {
      New-GpTestTheme -ThemesDir $script:systemThemes -Name "Broken" -InfoText "{ CFBundleIdentifier = org.example.Broken; }" -SettingsText "{ ThemeIdentifier = " | Out-Null
      $theme = @((New-GpReport)["themes"])[0]
      $theme["settings"]["status"] | Should -Be "malformed"
      $theme["settings"]["inline"] | Should -BeNullOrEmpty
      $theme["settings"]["note"] | Should -Match "could not be parsed"
      $theme["themeId"] | Should -BeNullOrEmpty
      $theme["bundleId"] | Should -Be "org.example.Broken"
    }

    It "records a malformed Info plist without failing the report" {
      New-GpTestTheme -ThemesDir $script:systemThemes -Name "BadInfo" -InfoText "{ CFBundleIdentifier = " -SettingsText $null | Out-Null
      $theme = @((New-GpReport)["themes"])[0]
      $theme["infoStatus"] | Should -Be "malformed"
      $theme["bundleId"] | Should -BeNullOrEmpty
      $theme["installation"]["infoPlistSha256"] | Should -Match '^[0-9a-f]{64}$'
    }
  }

  Context "domains and GSTheme sources" {
    BeforeEach {
      New-GpTestTheme -ThemesDir $script:systemThemes -Name "Adwaita" -InfoText "{ }" -SettingsText $null | Out-Null
    }

    It "flags a seed domain that differs from the app's bundle identifier" {
      $report = New-GpReport -AppDefaults (New-GpAppDefaults -Domain "org.example.Pkg" -Theme "Adwaita")
      $report["app"]["runtimeDomainHint"] | Should -Be "org.example.App"
      $report["app"]["runtimeDomainHintSource"] | Should -Be "bundleIdentifier"
      $report["defaults"]["seedDomain"] | Should -Be "org.example.Pkg"
      $report["defaults"]["seedDomainMatchesRuntimeHint"] | Should -BeFalse
    }

    It "reports a match when the seed domain is the bundle identifier" {
      $report = New-GpReport -AppDefaults (New-GpAppDefaults -Domain "org.example.App" -Theme "Adwaita")
      $report["defaults"]["seedDomainMatchesRuntimeHint"] | Should -BeTrue
    }

    It "falls back to the process name when the app has no bundle identifier" {
      New-GpTestFile -Path (Join-Path $script:payload "usr/app/Foo.app/Resources/Info-gnustep.plist") -Text "{ NSExecutable = Foo; }"
      $report = New-GpReport -AppDefaults (New-GpAppDefaults -Domain "Foo" -Theme "Adwaita")
      $report["app"]["runtimeDomainHint"] | Should -Be "Foo"
      $report["app"]["runtimeDomainHintSource"] | Should -Be "processName"
      $report["defaults"]["seedDomainMatchesRuntimeHint"] | Should -BeTrue
    }

    It "says the domain is unknown when the app's Info plist can't be read, rather than guessing" {
      New-GpTestFile -Path (Join-Path $script:payload "usr/app/Foo.app/Resources/Info-gnustep.plist") -Text "{ CFBundleIdentifier = "
      $report = New-GpReport -AppDefaults (New-GpAppDefaults -Domain "org.example.Pkg" -Theme "Adwaita")
      $report["app"]["runtimeDomainHint"] | Should -BeNullOrEmpty
      $report["app"]["runtimeDomainHintSource"] | Should -Be "unknown"
      $report["defaults"]["seedDomainMatchesRuntimeHint"] | Should -BeNullOrEmpty
    }

    It "ranks the seed over GlobalDefaults and gives the environment variable no rank" {
      $gnustepConfig = [pscustomobject]@{ Enabled = $true; UserLibraryRelative = $null; DefaultTheme = [pscustomobject]@{ Name = "Adwaita"; Desktops = @("GNOME") } }
      $report = New-GpReport -AppDefaults (New-GpAppDefaults -Domain "org.example.App" -Theme "Adwaita") -LaunchEnvironment @{ GSTheme = @{ value = "Adwaita"; policy = "ifUnset" } } -GnustepConfig $gnustepConfig
      $defaults = $report["defaults"]
      $defaults["seeds"][0]["policy"] | Should -Be "each-launch-if-absent"
      $defaults["seeds"][0]["rank"] | Should -Be 1
      $defaults["globalDefaultsTheme"]["rank"] | Should -Be 2
      @($defaults["globalDefaultsTheme"]["desktops"]) | Should -Be @("GNOME")
      $defaults["env"][0]["rank"] | Should -BeNullOrEmpty
      $defaults["env"][0]["effect"] | Should -Match "not read by gnustep-base/gui"
      $report["search"]["order"] | Should -Be @("user", "payload")
    }

    It "has no seed domain when nothing is seeded" {
      $report = New-GpReport
      $report["defaults"]["seedDomain"] | Should -BeNullOrEmpty
      $report["defaults"]["seedDomainMatchesRuntimeHint"] | Should -BeNullOrEmpty
      @($report["defaults"]["seeds"]).Count | Should -Be 0
    }
  }

  Context "the package contract's provisioned themes" {
    It "counts themeInputs and v1 entries as provisioned, not themes a stage script copied in" {
      $report = [ordered]@{ formatVersion = 2; themes = @(
        [ordered]@{ name = "FromInputs"; origin = "themeInputs" },
        [ordered]@{ name = "FromStage"; origin = "stage" },
        [ordered]@{ name = "OldEntry" }
      ) }
      New-GpTestFile -Path (Join-Path $script:payload "metadata/gnustep-packager-theme-report.json") -Text ($report | ConvertTo-Json -Depth 5)
      $names = @(Get-GpProvisionedThemeNamesFromPayload -Manifest @{ payload = @{ metadataRoot = "metadata" } } -PayloadRoot $script:payload)
      $names | Should -Be @("FromInputs", "OldEntry")
    }
  }

  Context "the sidecar" {
    It "binds to the exact AppImage by name and sha256" {
      New-GpTestTheme -ThemesDir $script:systemThemes -Name "Adwaita" -InfoText "{ }" -SettingsText $null | Out-Null
      $artifact = Join-Path $script:root "Pkg-1.2.3-x86_64.AppImage"
      [System.IO.File]::WriteAllBytes($artifact, [byte[]](1..64))
      $sidecar = New-GpAppImageThemeSidecar -Report (New-GpReport) -ArtifactPath $artifact -Architecture "x86_64"
      $sidecarPath = Get-GpArtifactSidecarPath -ArtifactPath $artifact -Suffix "themes.json"
      Write-GpJsonDocument -Document $sidecar -Path $sidecarPath

      (Split-Path -Leaf $sidecarPath) | Should -Be "Pkg-1.2.3-x86_64.themes.json"
      $sidecar["appimage"]["sha256"] | Should -Be (Get-GpFileSha256 -Path $artifact)
      $sidecar["appimage"]["fileName"] | Should -Be "Pkg-1.2.3-x86_64.AppImage"
      Test-GpAppImageThemeSidecarBinding -SidecarPath $sidecarPath -ArtifactPath $artifact | Should -BeTrue

      [System.IO.File]::WriteAllBytes($artifact, [byte[]](2..65))
      Test-GpAppImageThemeSidecarBinding -SidecarPath $sidecarPath -ArtifactPath $artifact | Should -BeFalse

      $renamed = Join-Path $script:root "Other.AppImage"
      [System.IO.File]::WriteAllBytes($renamed, [byte[]](1..64))
      Test-GpAppImageThemeSidecarBinding -SidecarPath $sidecarPath -ArtifactPath $renamed | Should -BeFalse
    }

    It "carries only discovery fields, with source only for themeInputs" {
      New-GpTestTheme -ThemesDir $script:systemThemes -Name "Adwaita" -InfoText "{ }" -SettingsText $null | Out-Null
      $artifact = Join-Path $script:root "Pkg.AppImage"
      [System.IO.File]::WriteAllBytes($artifact, [byte[]](1..8))
      $sidecar = New-GpAppImageThemeSidecar -Report (New-GpReport) -ArtifactPath $artifact
      $theme = @($sidecar["themes"])[0]
      @($theme.Keys) | Should -Be @("name", "themeId", "bundleId", "version", "shortVersion", "infoStatus", "installation", "source", "origin", "settings")
      $theme["source"] | Should -BeNullOrEmpty
      $sidecar["schema"] | Should -Be 1
    }
  }

  Context "the seeding AppRun does on every launch" {
    It "hands AppRun one line per shell statement" {
      $defaults = [pscustomobject]@{
        Domain = "org.example.App"
        Entries = @(
          [pscustomobject]@{ Key = "GSTheme"; Type = "string"; Value = "Adwaita"; SerializedValue = '"Adwaita"' },
          [pscustomobject]@{ Key = "Other"; Type = "bool"; Value = $true; SerializedValue = "YES" }
        )
      }
      # Enumerated the way Write-GpAppImageAppRun does.
      $collected = [System.Collections.Generic.List[string]]::new()
      foreach ($line in @(Get-GpAppImageDefaultsSeedLines -AppDefaults $defaults)) { $collected.Add($line) | Out-Null }
      $collected.Count | Should -Be 6
      $collected[0] | Should -Match '^if ! "\$APP_DEFAULTS_TOOL" read .*GSTheme.* >/dev/null 2>&1; then$'
      $collected[1] | Should -Match '^  "\$APP_DEFAULTS_TOOL" write .*"GSTheme" "\\"Adwaita\\""'
      $collected[2] | Should -Be "fi"
    }

    It "writes GSTheme only when absent: kept when the user changes it, back after the user removes it" -Skip:($IsWindows) {
      $store = Join-Path $script:root "defaults-store"
      New-Item -ItemType Directory -Force -Path $store | Out-Null
      $tool = Join-Path $script:root "fake-defaults"
      # A stand-in for the bundled defaults tool: one file per domain/key.
      New-GpTestFile -Path $tool -Text @"
#!/bin/sh
store='$store'
case "`$1" in
  read) [ -f "`$store/`$2.`$3" ] && cat "`$store/`$2.`$3" ;;
  write) printf '%s' "`$4" > "`$store/`$2.`$3" ;;
  delete) rm -f "`$store/`$2.`$3" ;;
esac
"@
      & chmod +x $tool
      $lines = Get-GpAppImageDefaultsSeedLines -AppDefaults (New-GpAppDefaults -Domain "org.example.App" -Theme "Adwaita")
      $launch = Join-Path $script:root "seed.sh"
      New-GpTestFile -Path $launch -Text ("#!/bin/sh`nAPP_DEFAULTS_TOOL='$tool'`n" + [string]::Join("`n", $lines) + "`n")
      $value = Join-Path $store "org.example.App.GSTheme"

      & sh $launch
      (Get-Content -Raw $value) | Should -Be '"Adwaita"'

      & $tool write org.example.App GSTheme '"Plain"'
      & sh $launch
      (Get-Content -Raw $value) | Should -Be '"Plain"'

      & $tool delete org.example.App GSTheme
      & sh $launch
      (Get-Content -Raw $value) | Should -Be '"Adwaita"'
    }
  }
}
