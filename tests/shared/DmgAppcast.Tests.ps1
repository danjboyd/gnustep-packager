Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# The Sparkle appcast pieces of the DMG backend that need no macOS tools: the
# sign_update output parser, the XML writer, and the signing flow against a
# stand-in sign_update (a shell script, so that part skips on Windows).
Describe "DMG Sparkle appcast" {
  BeforeAll {
    function Assert-GpEqual {
      param([object]$Actual, [object]$Expected, [string]$Message)
      if ($Actual -ne $Expected) {
        throw "$Message Expected: $Expected Actual: $Actual"
      }
    }

    function Assert-GpTrue {
      param([bool]$Condition, [string]$Message)
      if (-not $Condition) {
        throw $Message
      }
    }

    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
    . (Join-Path $script:repoRoot "backends\\dmg\\lib\\dmg.ps1")

    $script:workRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-dmg-appcast-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $script:workRoot | Out-Null
    $script:imagePath = Join-Path $script:workRoot "App-1.0.dmg"
    [System.IO.File]::WriteAllBytes($script:imagePath, [byte[]](1..200 | ForEach-Object { [byte]($_ % 256) }))

    function New-GpTestAppcastConfig {
      param([bool]$Required, [string]$SignUpdatePath)
      return [pscustomobject]@{
        ArtifactPath = $script:imagePath
        DisplayName = "App & Co"
        Version = "1.0"
        AppInfo = [pscustomobject]@{ ShortVersion = "1.0"; BundleVersion = "7"; MinimumSystemVersion = "11.0" }
        Appcast = [pscustomobject]@{
          Enabled = $true
          Required = $Required
          DownloadUrl = "https://github.com/o/r/releases/download/v1.0/App-1.0.dmg"
          ReleaseNotesUrl = "https://github.com/o/r/releases/tag/v1.0"
          PrivateKeyEnvVar = "GP_TEST_SPARKLE_KEY"
          SignUpdatePath = $SignUpdatePath
          Path = (Join-Path $script:workRoot "App-1.0.appcast.xml")
        }
      }
    }
  }

  AfterAll {
    Remove-Item Env:GP_TEST_SPARKLE_KEY -ErrorAction SilentlyContinue
    if (Test-Path $script:workRoot) {
      Remove-Item -Recurse -Force $script:workRoot
    }
  }

  It "parses sign_update output and rejects output without a signature" {
    $parsed = ConvertFrom-GpSparkleSignUpdateOutput -Text 'sparkle:edSignature="ab+/cd==" length="4096"'
    Assert-GpEqual -Actual $parsed.EdSignature -Expected "ab+/cd==" -Message "The signature should be parsed."
    Assert-GpEqual -Actual $parsed.Length -Expected 4096 -Message "The length should be parsed."
    Assert-GpTrue -Condition ($null -eq (ConvertFrom-GpSparkleSignUpdateOutput -Text "ERROR: no key")) -Message "Output without a signature should give null."
  }

  It "writes well-formed, escaped appcast XML" {
    $xml = New-GpDmgAppcastXml -Title "A & B" -ShortVersion "1.2" -BundleVersion "42" -MinimumSystemVersion "11.0" `
      -DownloadUrl "https://example.invalid/d?a=1&b=2" -ReleaseNotesUrl "https://example.invalid/notes" `
      -EdSignature "c2ln" -Length 10 -PublishedAt ([datetime]::new(2026, 11, 3, 12, 0, 0, [DateTimeKind]::Utc))
    [xml]$document = $xml
    $item = $document.rss.channel.item
    Assert-GpEqual -Actual $item.title -Expected "A & B 1.2" -Message "The item title should round-trip."
    Assert-GpEqual -Actual $item.version -Expected "42" -Message "sparkle:version is the bundle version."
    Assert-GpEqual -Actual $item.shortVersionString -Expected "1.2" -Message "sparkle:shortVersionString is the short version."
    Assert-GpEqual -Actual $item.enclosure.url -Expected "https://example.invalid/d?a=1&b=2" -Message "The enclosure URL should round-trip."
    Assert-GpEqual -Actual $item.enclosure.length -Expected "10" -Message "The enclosure length should be written."
    Assert-GpEqual -Actual $item.pubDate -Expected "Tue, 03 Nov 2026 12:00:00 +0000" -Message "pubDate should be RFC 822 in UTC."
  }

  It "signs with sign_update, never logs the key, and skips or fails without one" -Skip:$IsWindows {
    $signUpdate = Join-Path $script:workRoot "sign_update"
    Set-Content -Path $signUpdate -NoNewline -Value @'
#!/usr/bin/env bash
[ "$1" = "--ed-key-file" ] && [ "$2" = "-" ] || { echo "bad arguments" >&2; exit 2; }
key="$(cat; printf x)"; key="${key%x}"
[ "$key" = "TESTKEY" ] || { echo "unexpected key" >&2; exit 3; }
printf 'sparkle:edSignature="c2lnbmVk" length="%s"\n' "$(wc -c < "$3" | tr -d ' ')"
'@
    & chmod +x $signUpdate
    $logPath = Join-Path $script:workRoot "package.log"

    Remove-Item Env:GP_TEST_SPARKLE_KEY -ErrorAction SilentlyContinue
    $skipped = Invoke-GpDmgAppcast -Config (New-GpTestAppcastConfig -Required $false -SignUpdatePath $signUpdate) -LogPath $logPath
    Assert-GpEqual -Actual $skipped["status"] -Expected "skipped" -Message "No key should skip the appcast."
    $message = $null
    try {
      Invoke-GpDmgAppcast -Config (New-GpTestAppcastConfig -Required $true -SignUpdatePath $signUpdate) -LogPath $logPath | Out-Null
    } catch {
      $message = $_.Exception.Message
    }
    Assert-GpTrue -Condition ($message -match "required but not written") -Message "A required appcast without a key should fail."

    $env:GP_TEST_SPARKLE_KEY = "TESTKEY`n"
    $written = Invoke-GpDmgAppcast -Config (New-GpTestAppcastConfig -Required $true -SignUpdatePath $signUpdate) -LogPath $logPath
    Assert-GpEqual -Actual $written["status"] -Expected "written" -Message "With a key, the appcast should be written."
    [xml]$document = Get-Content -Raw -LiteralPath $written["path"]
    Assert-GpEqual -Actual $document.rss.channel.item.enclosure.edSignature -Expected "c2lnbmVk" -Message "The enclosure should carry sign_update's signature."
    Assert-GpEqual -Actual $document.rss.channel.item.enclosure.length -Expected "200" -Message "The enclosure length should be the image size."
    Assert-GpTrue -Condition (-not ((Get-Content -Raw -LiteralPath $logPath) -match "TESTKEY")) -Message "The private key must never reach the log."
  }
}
