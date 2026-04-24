Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Describe "Reusable workflow surface" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    $script:workflowText = Get-Content -Raw -Path (Join-Path $script:repoRoot ".github/workflows/package-gnustep-app.yml")
    $script:validateRepoText = Get-Content -Raw -Path (Join-Path $script:repoRoot ".github/workflows/validate-repo.yml")
    $script:githubActionsDocText = Get-Content -Raw -Path (Join-Path $script:repoRoot "docs/github-actions.md")
    $script:consumerSetupDocText = Get-Content -Raw -Path (Join-Path $script:repoRoot "docs/consumer-setup.md")
    $script:gnustepCliDocText = Get-Content -Raw -Path (Join-Path $script:repoRoot "docs/gnustep-cli-new-integration.md")
    $script:windowsHardeningDocText = Get-Content -Raw -Path (Join-Path $script:repoRoot "docs/windows-gnustep-cli-new-hardening.md")
    $script:releaseGateDocText = Get-Content -Raw -Path (Join-Path $script:repoRoot "docs/release-gate.md")
    $script:downstreamMsiText = Get-Content -Raw -Path (Join-Path $script:repoRoot "examples/downstream/package-msi.yml")
    $script:downstreamAppImageText = Get-Content -Raw -Path (Join-Path $script:repoRoot "examples/downstream/package-appimage.yml")
    $script:downstreamReleaseText = Get-Content -Raw -Path (Join-Path $script:repoRoot "examples/downstream/package-release-with-updates.yml")
    $script:downstreamGuiTemplateText = Get-Content -Raw -Path (Join-Path $script:repoRoot "examples/downstream/manifest-gnustep-gui.template.json")
    $script:gnustepCliSmokeText = Get-Content -Raw -Path (Join-Path $script:repoRoot "scripts/ci/gnustep-cli-new-bootstrap-smoke.sh")
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
      "gnustep-cli-manifest-url:",
      "gnustep-cli-bootstrap-url:",
      "gnustep-cli-root:",
      "preflight-shell:",
      "preflight-command:"
    )) {
      if ($script:workflowText -notmatch [regex]::Escape($pattern)) {
        throw "Reusable workflow is missing expected input: $pattern"
      }
    }
  }

  It "wires gnustep-cli-new into the default AppImage workflow path" {
    foreach ($pattern in @(
      "Bootstrap And Smoke Test gnustep-cli-new",
      "scripts/ci/gnustep-cli-new-bootstrap-smoke.sh",
      "GP_GNUSTEP_CLI_MANIFEST_URL",
      "GP_GNUSTEP_CLI_BOOTSTRAP_URL",
      "GP_GNUSTEP_CLI_ROOT",
      "gnustep-cli-new/releases/download/v0.1.0-dev/release-manifest.json"
    )) {
      if ($script:workflowText -notmatch [regex]::Escape($pattern)) {
        throw "Reusable AppImage workflow is missing gnustep-cli-new integration surface: $pattern"
      }
    }
  }

  It "wires gnustep-cli-new into the default MSI workflow path" {
    foreach ($pattern in @(
      "Install MSYS2 Bootstrap Shell",
      "Bootstrap And Smoke Test gnustep-cli-new For MSI",
      "shell: pwsh",
      "GP_GNUSTEP_CLI_MANIFEST_URL",
      "GP_GNUSTEP_CLI_BOOTSTRAP_URL",
      "GP_GNUSTEP_CLI_HOST_KIND",
      "MSYS2_LOCATION",
      "gnustep-bootstrap.ps1"
    )) {
      if ($script:workflowText -notmatch [regex]::Escape($pattern)) {
        throw "Reusable MSI workflow is missing gnustep-cli-new integration surface: $pattern"
      }
    }
    if ($script:validateRepoText -notmatch [regex]::Escape("shell: msys2 {0}") -or
        $script:validateRepoText -notmatch [regex]::Escape("Bootstrap And Smoke Test gnustep-cli-new")) {
      throw "Repo Windows validation should run the gnustep-cli-new bootstrap smoke from MSYS2."
    }
  }

  It "ships an Ubuntu gnustep-cli-new bootstrap smoke for repo validation" {
    foreach ($pattern in @(
      "gnustep-bootstrap.sh",
      "--json --yes setup",
      "gnustep --version",
      "gnustep doctor --json",
      "gnustep new cli-tool HelloPackager --json",
      "gnustep build --json",
      "gnustep run --json"
    )) {
      if ($script:gnustepCliSmokeText -notmatch [regex]::Escape($pattern)) {
        throw "gnustep-cli-new smoke script is missing expected command: $pattern"
      }
    }
    if ($script:validateRepoText -notmatch [regex]::Escape("Bootstrap And Smoke Test gnustep-cli-new")) {
      throw "Repo validation should run the gnustep-cli-new bootstrap smoke on Linux."
    }
  }

  It "keeps direct GNUstep package installation out of the MSI workflow baseline" {
    foreach ($pattern in @(
      "mingw-w64-clang-x86_64-gnustep-make",
      "mingw-w64-clang-x86_64-gnustep-base",
      "mingw-w64-clang-x86_64-gnustep-gui",
      "mingw-w64-clang-x86_64-gnustep-back",
      "mingw-w64-clang-x86_64-toolchain"
    )) {
      if ($script:workflowText -match [regex]::Escape($pattern)) {
        throw "Reusable workflow MSI baseline should use gnustep-cli-new instead of installing GNUstep directly: $pattern"
      }
    }
  }

  It "uploads gnustep-cli-new diagnostic artifacts and blocker reports" {
    foreach ($pattern in @(
      "Upload gnustep-cli-new Diagnostics",
      "-gnustep-cli-new",
      "gnustep-cli-new-blocker-report.md",
      "gnustep-cli-new-host-context.log",
      "gnustep-cli-new-path-context.log",
      "gnustep-cli-new-bootstrap-download.log"
    )) {
      if (($script:workflowText -notmatch [regex]::Escape($pattern)) -and
          ($script:gnustepCliDocText -notmatch [regex]::Escape($pattern)) -and
          ($script:windowsHardeningDocText -notmatch [regex]::Escape($pattern)) -and
          ($script:gnustepCliSmokeText -notmatch [regex]::Escape($pattern))) {
        throw "gnustep-cli-new diagnostic artifact surface is missing: $pattern"
      }
    }
  }

  It "captures Windows path normalization evidence for hosted MSI hardening" {
    foreach ($pattern in @(
      "host_kind",
      "windows-msys2-clang64",
      "cygpath",
      "cmd.exe",
      "where gnustep",
      "MSYS2_LOCATION"
    )) {
      if (($script:workflowText -notmatch [regex]::Escape($pattern)) -and
          ($script:validateRepoText -notmatch [regex]::Escape($pattern)) -and
          ($script:gnustepCliSmokeText -notmatch [regex]::Escape($pattern)) -and
          ($script:windowsHardeningDocText -notmatch [regex]::Escape($pattern))) {
        throw "Windows gnustep-cli-new hardening evidence is missing: $pattern"
      }
    }
  }

  It "uploads repo validation gnustep-cli-new diagnostics for hosted evidence" {
    foreach ($pattern in @(
      "windows-gnustep-cli-new",
      "linux-gnustep-cli-new",
      "dist/logs/gnustep-cli-new",
      "actions/upload-artifact@v4"
    )) {
      if (($script:validateRepoText -notmatch [regex]::Escape($pattern)) -and
          ($script:windowsHardeningDocText -notmatch [regex]::Escape($pattern))) {
        throw "Repo validation should preserve gnustep-cli-new diagnostic evidence: $pattern"
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
      "gnustep-cli-manifest-url",
      "gnustep-cli-new",
      "gnustep-cli-new-blocker-report.md",
      "hostDependencies",
      "gnustep-cmark",
      "msys2-packages",
      "launch-only",
      "marker-file"
    )) {
      if (($script:githubActionsDocText -notmatch [regex]::Escape($pattern)) -and
          ($script:consumerSetupDocText -notmatch [regex]::Escape($pattern)) -and
          ($script:windowsHardeningDocText -notmatch [regex]::Escape($pattern)) -and
          ($script:gnustepCliDocText -notmatch [regex]::Escape($pattern))) {
        throw "Updated docs do not mention expected workflow or smoke-mode surface: $pattern"
      }
    }
  }

  It "documents the theme input migration path in downstream examples" {
    foreach ($pattern in @(
      "themeInputs",
      "WinUITheme",
      "plugins-themes-winuitheme",
      '"defaultTheme": "WinUITheme"'
    )) {
      if ($script:downstreamGuiTemplateText -notmatch [regex]::Escape($pattern)) {
        throw "Downstream GUI template is missing expected theme input example: $pattern"
      }
    }

    foreach ($pattern in @(
      "themeInputs",
      "repo-local fetch/build/install/copy scripts",
      "bundled-theme validation"
    )) {
      if (($script:consumerSetupDocText -notmatch [regex]::Escape($pattern)) -and
          ((Get-Content -Raw -Path (Join-Path $script:repoRoot "examples/downstream/README.md")) -notmatch [regex]::Escape($pattern))) {
        throw "Consumer or downstream docs are missing theme migration guidance: $pattern"
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

  It "ships downstream hosted workflow examples with gnustep-cli-new manifest selection" {
    foreach ($text in @($script:downstreamMsiText, $script:downstreamAppImageText, $script:downstreamReleaseText)) {
      if ($text -notmatch [regex]::Escape("gnustep-cli-manifest-url")) {
        throw "Downstream hosted workflow examples should show gnustep-cli-new manifest selection."
      }
    }
  }

  It "documents the release gate gnustep-cli-new baseline" {
    foreach ($pattern in @(
      "gnustep-cli-new",
      "v0.1.0-dev",
      "gnustep-cli-new-blocker-report.md",
      "windows-latest",
      "MSYS2",
      "CLANG64",
      "WiX baseline",
      "MSI smoke",
      "windows-amd64-msys2-clang64"
    )) {
      if ($script:releaseGateDocText -notmatch [regex]::Escape($pattern)) {
        throw "Release gate docs should record gnustep-cli-new baseline and diagnostics: $pattern"
      }
    }
  }

  It "documents the hosted Windows gnustep-cli-new gate and migration path" {
    foreach ($pattern in @(
      "fail-closed",
      "release packaging",
      "windows-msys2-clang64",
      "hostDependencies.windows.msys2Packages",
      "self-hosted Windows",
      "skip-default-host-setup: true",
      "preflight-command"
    )) {
      if (($script:releaseGateDocText -notmatch [regex]::Escape($pattern)) -and
          ($script:githubActionsDocText -notmatch [regex]::Escape($pattern)) -and
          ($script:consumerSetupDocText -notmatch [regex]::Escape($pattern)) -and
          ($script:windowsHardeningDocText -notmatch [regex]::Escape($pattern))) {
        throw "Hosted Windows gate or migration docs are missing expected text: $pattern"
      }
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
