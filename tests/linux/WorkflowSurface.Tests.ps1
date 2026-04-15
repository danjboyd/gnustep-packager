Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Describe "Reusable workflow surface" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    $script:workflowText = Get-Content -Raw -Path (Join-Path $script:repoRoot ".github/workflows/package-gnustep-app.yml")
    $script:githubActionsDocText = Get-Content -Raw -Path (Join-Path $script:repoRoot "docs/github-actions.md")
    $script:consumerSetupDocText = Get-Content -Raw -Path (Join-Path $script:repoRoot "docs/consumer-setup.md")
    $script:coreText = Get-Content -Raw -Path (Join-Path $script:repoRoot "scripts/lib/core.ps1")
    $script:otvmRemoteText = Get-Content -Raw -Path (Join-Path $script:repoRoot "scripts/ci/otvm-windows-remote.ps1")
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

  It "resolves manifest-declared host dependency packages in workflow setup" {
    foreach ($pattern in @(
      "manifest_msys2_packages",
      "manifest_apt_packages",
      "resolved_msys2_packages",
      "resolved_apt_packages",
      "host_setup_mode",
      "host_setup_summary",
      "Get-GpWorkflowHostSetupPlan",
      "InstallHostDependencies"
    )) {
      if ($script:workflowText -notmatch [regex]::Escape($pattern)) {
        throw "Reusable workflow is missing manifest-driven host dependency integration: $pattern"
      }
    }
  }

  It "documents downstream workflow extension points" {
    foreach ($pattern in @(
      "runs-on-msi",
      "runs-on-appimage",
      "preflight-command",
      "hostDependencies",
      "gnustep-cmark",
      "msys2-packages",
      "launch-only",
      "marker-file"
    )) {
      if (($script:githubActionsDocText -notmatch [regex]::Escape($pattern)) -and ($script:consumerSetupDocText -notmatch [regex]::Escape($pattern))) {
        throw "Updated docs do not mention expected workflow or smoke-mode surface: $pattern"
      }
    }
  }

  It "guards self-hosted verify-only runs against ignored additive package inputs" {
    foreach ($pattern in @(
      '`msys2-packages` is not applied when `skip-default-host-setup: true`',
      '`appimage-apt-packages` is not applied when `skip-default-host-setup: true`',
      'verify-only'
    )) {
      if (($script:workflowText -notmatch [regex]::Escape($pattern)) -and
          ($script:githubActionsDocText -notmatch [regex]::Escape($pattern)) -and
          ($script:coreText -notmatch [regex]::Escape($pattern))) {
        throw "Self-hosted workflow guardrail is missing expected text: $pattern"
      }
    }
  }

  It "ships a self-hosted downstream AppImage workflow example" {
    $examplePath = Join-Path $script:repoRoot "examples/downstream/package-appimage-self-hosted.yml"
    if (-not (Test-Path $examplePath)) {
      throw "Expected self-hosted AppImage workflow example at $examplePath"
    }
  }

  It "runs remote Windows validation through manifest-driven host preflight" {
    if ($script:otvmRemoteText -notmatch [regex]::Escape("packager-host-preflight")) {
      throw "Remote Windows helper should run host preflight before build."
    }
    if ($script:otvmRemoteText -notmatch [regex]::Escape("-InstallHostDependencies")) {
      throw "Remote Windows helper should allow manifest-driven host dependency installation."
    }
  }
}
