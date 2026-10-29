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
    $script:cliText = Get-Content -Raw -Path (Join-Path $script:repoRoot "scripts/gnustep-packager.ps1")
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
      "container-appimage:",
      "skip-default-host-setup:",
      "msys2-packages:",
      "appimage-apt-packages:",
      "gnustep-cli-manifest-url:",
      "gnustep-cli-bootstrap-url:",
      "gnustep-cli-bootstrap-sha256:",
      "gnustep-cli-bootstrap-ps1-sha256:",
      "gnustep-cli-root:",
      "preflight-shell:",
      "preflight-command:"
    )) {
      if ($script:workflowText -notmatch [regex]::Escape($pattern)) {
        throw "Reusable workflow is missing expected input: $pattern"
      }
    }
  }

  It "pins the default AppImage runner image instead of following ubuntu-latest" {
    $match = [regex]::Match($script:workflowText, '(?ms)^\s+runs-on-appimage:\s*$.*?^\s+default:\s*''([^'']*)''')
    if (-not $match.Success) {
      throw "Reusable workflow should declare a runs-on-appimage default."
    }
    if ($match.Groups[1].Value -ne '["ubuntu-24.04"]') {
      throw "runs-on-appimage should default to the pinned [""ubuntu-24.04""] (it sets the AppImage's glibc floor); got $($match.Groups[1].Value)"
    }
    if ($script:validateRepoText -notmatch '(?m)^  linux-validation:\s*$(\r?\n\s*#.*)*\r?\n\s+runs-on: ubuntu-24\.04\s*$') {
      throw "Repo CI's linux-validation job should run on the same pinned image as the runs-on-appimage default."
    }
    if ($script:githubActionsDocText -notmatch "### AppImage Runner Image") {
      throw "docs/github-actions.md should explain the pinned AppImage runner and how to opt into a newer image."
    }
  }

  It "checks out its own packager commit instead of the caller's workflow ref" {
    foreach ($pattern in @(
      '${{ job.workflow_repository }}',
      '${{ job.workflow_sha }}'
    )) {
      if ($script:workflowText -notmatch [regex]::Escape($pattern)) {
        throw "Reusable workflow does not resolve the packager checkout from: $pattern"
      }
    }
    if ($script:workflowText -match [regex]::Escape('${{ github.workflow_ref }}')) {
      throw "Reusable workflow must not resolve the packager checkout from github.workflow_ref (it names the caller's workflow in a workflow_call)"
    }
  }

  It "packages DMGs on macOS runners, with optional Developer ID signing and notarization" {
    foreach ($pattern in @(
      "runs-on-dmg:",
      "inputs.backend == 'dmg' && inputs.runs-on-dmg",
      "macos_certificate_p12:",
      "notary_app_password:",
      "dmg_notary_profile_env_var=",
      "Configure macOS Signing",
      "xcrun notarytool store-credentials",
      "Remove macOS Signing Keychain"
    )) {
      if ($script:workflowText -notmatch [regex]::Escape($pattern)) {
        throw "Reusable workflow is missing DMG surface: $pattern"
      }
    }
    if ($script:validateRepoText -notmatch "(?s)macos-reusable-workflow:.*uses: \./\.github/workflows/package-gnustep-app\.yml.*backend: dmg") {
      throw "validate-repo should run the reusable workflow's dmg path."
    }
    if ($script:validateRepoText -notmatch "(?s)windows-reusable-workflow:.*uses: \./\.github/workflows/package-gnustep-app\.yml.*backend: msi") {
      throw "validate-repo should run the reusable workflow's msi path."
    }
    if ($script:githubActionsDocText -notmatch [regex]::Escape("runs-on-dmg")) {
      throw "docs/github-actions.md should document runs-on-dmg."
    }
  }

  It "wires gnustep-cli-new into the default AppImage workflow path" {
    foreach ($pattern in @(
      "Bootstrap And Smoke Test gnustep-cli-new",
      "scripts/ci/gnustep-cli-new-bootstrap-smoke.sh",
      "GP_GNUSTEP_CLI_MANIFEST_URL",
      "GP_GNUSTEP_CLI_BOOTSTRAP_URL",
      "GP_GNUSTEP_CLI_ROOT",
      "gnustep-cli-new/releases/download/v0.1.3/release-manifest.json"
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
      "container-appimage",
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

  It "documents and surfaces backend-aware theme validation behavior" {
    foreach ($pattern in @(
      "Shared validation checks the current staged layout only",
      "Use -Backend for backend-aware theme validation",
      "provision -Backend msi"
    )) {
      if (($script:cliText -notmatch [regex]::Escape($pattern)) -and
          ($script:consumerSetupDocText -notmatch [regex]::Escape($pattern)) -and
          ((Get-Content -Raw -Path (Join-Path $script:repoRoot "docs/shared-cli.md")) -notmatch [regex]::Escape($pattern))) {
        throw "Backend-aware theme validation guidance is missing: $pattern"
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

  It "checks the downloaded gnustep-cli-new bootstrap against a pinned digest" {
    foreach ($pattern in @(
      "GP_GNUSTEP_CLI_BOOTSTRAP_SHA256: `${{ inputs.gnustep-cli-bootstrap-sha256 }}",
      "GP_GNUSTEP_CLI_BOOTSTRAP_PS1_SHA256: `${{ inputs.gnustep-cli-bootstrap-ps1-sha256 }}",
      "Get-FileHash -Algorithm SHA256 -LiteralPath `$bootstrapPath"
    )) {
      if ($script:workflowText -notmatch [regex]::Escape($pattern)) {
        throw "Reusable workflow is missing bootstrap digest check: $pattern"
      }
    }
  }

  It "refuses a bootstrap script whose digest does not match, before running it" {
    if (-not $IsLinux) {
      Set-ItResult -Skipped -Because "the POSIX smoke path runs on Linux"
      return
    }
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-bootstrap-sha-" + [guid]::NewGuid().ToString("N"))
    try {
      New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
      $bootstrap = Join-Path $tempRoot "gnustep-bootstrap.sh"
      Set-Content -Path $bootstrap -Value @("#!/bin/sh", "touch '$tempRoot/ran'")
      $logRoot = Join-Path $tempRoot "logs"
      $output = @(& env "GP_GNUSTEP_CLI_BOOTSTRAP_URL=file://$bootstrap" "GP_GNUSTEP_CLI_BOOTSTRAP_SHA256=0000" `
          "GP_GNUSTEP_CLI_ROOT=$tempRoot/root" "GP_GNUSTEP_CLI_LOG_ROOT=$logRoot" "GP_GNUSTEP_CLI_SMOKE_ROOT=$tempRoot/smoke" `
          sh (Join-Path $script:repoRoot "scripts/ci/gnustep-cli-new-bootstrap-smoke.sh") 2>&1)
      if ($LASTEXITCODE -eq 0) {
        throw "Bootstrap smoke should fail on a digest mismatch. Output: $($output -join "`n")"
      }
      if (($output -join "`n") -notmatch "sha256 mismatch") {
        throw "Bootstrap smoke should report the digest mismatch. Output: $($output -join "`n")"
      }
      if (Test-Path -LiteralPath (Join-Path $tempRoot "ran")) {
        throw "Bootstrap smoke ran a bootstrap script whose digest did not match."
      }
      if (-not (Test-Path -LiteralPath (Join-Path $logRoot "gnustep-cli-new-blocker-report.md"))) {
        throw "Bootstrap smoke should still write the blocker report on a digest mismatch."
      }
    }
    finally {
      Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $tempRoot
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
      "v0.1.3",
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
