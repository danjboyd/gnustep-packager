Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Consumers copy these files, so a schema or validator change that one of them
# no longer meets should fail here rather than in a consumer's build.
Describe "Example manifests" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
  }

  It "finds and validates every manifest under examples/" {
    $examplesRoot = Join-Path $script:repoRoot "examples"
    # Tracked files only: dist/ and out/ hold build output with stale copies.
    $tracked = @(& git -C $script:repoRoot ls-files -- "examples/*.json")
    if ($LASTEXITCODE -ne 0 -or $tracked.Count -eq 0) {
      throw "Could not list the tracked files under $examplesRoot."
    }
    $paths = @($tracked | Where-Object { (Split-Path -Leaf $_) -match 'manifest' } | ForEach-Object { Join-Path $script:repoRoot $_ })
    $paths.Count | Should -BeGreaterOrEqual 6

    $failures = [System.Collections.Generic.List[string]]::new()
    foreach ($path in $paths) {
      $issues = @()
      $issues += @(Test-GpManifestSchema -Path $path)
      $context = Get-GpManifestContext -Path $path
      $issues += @(Test-GpManifest -Manifest $context.Manifest)
      foreach ($issue in $issues) {
        $failures.Add(("{0}: {1}" -f [System.IO.Path]::GetRelativePath($script:repoRoot, $path), $issue)) | Out-Null
      }
    }

    $failures -join "`n" | Should -BeNullOrEmpty
  }
}
