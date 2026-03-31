Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Describe "Reusable workflow surface" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    $script:workflowText = Get-Content -Raw -Path (Join-Path $script:repoRoot ".github/workflows/package-gnustep-app.yml")
    $script:githubActionsDocText = Get-Content -Raw -Path (Join-Path $script:repoRoot "docs/github-actions.md")
    $script:consumerSetupDocText = Get-Content -Raw -Path (Join-Path $script:repoRoot "docs/consumer-setup.md")
  }

  It "exposes runner, preflight, and package-extension inputs" {
    foreach ($pattern in @(
      "runs-on-msi:",
      "runs-on-appimage:",
      "skip-default-host-setup:",
      "msys2-packages:",
      "appimage-apt-packages:",
      "preflight-shell:",
      "preflight-command:"
    )) {
      if ($script:workflowText -notmatch [regex]::Escape($pattern)) {
        throw "Reusable workflow is missing expected input: $pattern"
      }
    }
  }

  It "installs the documented default MSI GNUstep baseline" {
    foreach ($pattern in @(
      "mingw-w64-clang-x86_64-gnustep-make",
      "mingw-w64-clang-x86_64-gnustep-base",
      "mingw-w64-clang-x86_64-gnustep-gui",
      "mingw-w64-clang-x86_64-gnustep-back",
      "mingw-w64-clang-x86_64-libdispatch",
      "mingw-w64-clang-x86_64-libobjc2",
      "mingw-w64-clang-x86_64-toolchain"
    )) {
      if ($script:workflowText -notmatch [regex]::Escape($pattern)) {
        throw "Reusable workflow MSI baseline is missing package: $pattern"
      }
    }
  }

  It "documents downstream workflow extension points" {
    foreach ($pattern in @(
      "runs-on-msi",
      "runs-on-appimage",
      "preflight-command",
      "msys2-packages",
      "launch-only",
      "marker-file"
    )) {
      if (($script:githubActionsDocText -notmatch [regex]::Escape($pattern)) -and ($script:consumerSetupDocText -notmatch [regex]::Escape($pattern))) {
        throw "Updated docs do not mention expected workflow or smoke-mode surface: $pattern"
      }
    }
  }

  It "ships a self-hosted downstream AppImage workflow example" {
    $examplePath = Join-Path $script:repoRoot "examples/downstream/package-appimage-self-hosted.yml"
    if (-not (Test-Path $examplePath)) {
      throw "Expected self-hosted AppImage workflow example at $examplePath"
    }
  }
}
