Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# docs/theme-bundling.md's Gumdrop example is the manifest an app author
# copies. Keep it valid: merged into examples/sample-gui, it must pass the
# schema and the manifest validator for both installers.
Describe "docs/theme-bundling.md Gumdrop example" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")

    $docText = Get-Content -Raw (Join-Path $script:repoRoot "docs/theme-bundling.md")
    $match = [regex]::Match($docText, '(?s)### Example \(Gumdrop\)\s*```json\s*(.*?)```')
    if (-not $match.Success) {
      throw "docs/theme-bundling.md should have a json block under '### Example (Gumdrop)'."
    }
    $script:example = $match.Groups[1].Value | ConvertFrom-Json -AsHashtable
  }

  It "names a theme input for both platforms and fonts for both backends" {
    @($script:example["themeInputs"]).Count | Should -Be 1
    $theme = $script:example["themeInputs"][0]
    @($theme["platforms"]) | Should -Be @("linux", "windows")
    $theme["default"] | Should -BeTrue
    foreach ($backend in @("appimage", "msi")) {
      $entry = @($script:example["backends"][$backend]["fonts"]["bundle"])[0]
      $entry["name"] | Should -Be "DejaVu"
      $entry["licenseFile"] | Should -Not -BeNullOrEmpty
    }
  }

  It "passes the schema and the validator when merged into a real manifest" {
    $samplePath = Join-Path $script:repoRoot "examples/sample-gui/package.manifest.json"
    $manifest = Get-Content -Raw $samplePath | ConvertFrom-Json -AsHashtable
    $manifest["themeInputs"] = $script:example["themeInputs"]
    # The sample's own default theme is WinUXTheme. Drop the sample's settings
    # for it, so the example alone decides the default.
    if ($manifest.Contains("packagedDefaults")) {
      $manifest["packagedDefaults"].Remove("defaultTheme")
    }
    if ($manifest["launch"].Contains("env")) {
      $manifest["launch"]["env"].Remove("GSTheme")
    }
    foreach ($backend in @("appimage", "msi")) {
      $manifest["backends"][$backend]["fonts"] = $script:example["backends"][$backend]["fonts"]
    }

    # Beside the sample, so the manifest's relative paths mean what they do there.
    $mergedPath = Join-Path (Split-Path -Parent $samplePath) ("docs-example-" + [guid]::NewGuid().ToString("N") + ".json")
    try {
      Set-Content -Path $mergedPath -Value ($manifest | ConvertTo-Json -Depth 32) -Encoding utf8
      $schemaIssues = @(Test-GpManifestSchema -Path $mergedPath)
      $schemaIssues.Count | Should -Be 0 -Because ([string]::Join("; ", $schemaIssues))
      $context = Get-GpManifestContext -Path $mergedPath
      $issues = @(Test-GpManifest -Manifest $context.Manifest)
      $issues.Count | Should -Be 0 -Because ([string]::Join("; ", $issues))
    } finally {
      Remove-Item -Force $mergedPath -ErrorAction SilentlyContinue
    }
  }
}
