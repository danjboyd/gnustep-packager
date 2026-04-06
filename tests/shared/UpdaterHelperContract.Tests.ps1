Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Describe "Updater helper contract" {
  BeforeAll {
    function Assert-GpTrue {
      param(
        [bool]$Condition,
        [string]$Message
      )

      if (-not $Condition) {
        throw $Message
      }
    }

    function Assert-GpEqual {
      param(
        [object]$Actual,
        [object]$Expected,
        [string]$Message
      )

      if ($Actual -ne $Expected) {
        throw "$Message Expected: $Expected Actual: $Actual"
      }
    }

    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    $script:helperPlanPath = Join-Path $script:repoRoot "updater/contracts/helper-plan.example.json"
    $script:helperStatePath = Join-Path $script:repoRoot "updater/contracts/helper-state.example.json"
    $script:helperDocText = Get-Content -Raw -Path (Join-Path $script:repoRoot "docs/updater-helper-contract.md")
    $script:consumerDocText = Get-Content -Raw -Path (Join-Path $script:repoRoot "docs/updater-consumer-guide.md")

    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
  }

  It "ships a documented helper plan fixture" {
    $plan = Get-GpJsonFile -Path $script:helperPlanPath

    Assert-GpEqual -Actual $plan["formatVersion"] -Expected 1 -Message "Helper plan fixtures should carry a format version."
    Assert-GpEqual -Actual $plan["package"]["backend"] -Expected "appimage" -Message "The helper plan fixture should demonstrate the backend-aware contract."
    Assert-GpEqual -Actual $plan["asset"]["kind"] -Expected "appimage" -Message "The helper plan fixture should preserve asset kind."
    Assert-GpEqual -Actual $plan["execution"]["linux"]["currentAppImagePath"] -Expected "/home/user/Applications/MyGNUstepApp.AppImage" -Message "The helper plan fixture should demonstrate the current AppImage path handoff."
  }

  It "ships a documented helper state fixture" {
    $state = Get-GpJsonFile -Path $script:helperStatePath

    Assert-GpEqual -Actual $state["formatVersion"] -Expected 1 -Message "Helper state fixtures should carry a format version."
    Assert-GpEqual -Actual $state["status"] -Expected "readyToApply" -Message "The helper state fixture should demonstrate a restart-ready state."
    Assert-GpEqual -Actual $state["apply"]["mode"] -Expected "appimage-replace" -Message "The helper state fixture should preserve the apply mode."
    Assert-GpEqual -Actual $state["progress"]["fractionCompleted"] -Expected 1.0 -Message "The helper state fixture should demonstrate progress shape."
  }

  It "documents helper statuses and apply modes" {
    foreach ($pattern in @(
      "readyToApply",
      "manualActionRequired",
      "failed",
      "msi-install",
      "appimage-update",
      "appimage-replace",
      "manual-download"
    )) {
      Assert-GpTrue -Condition ($script:helperDocText -match [regex]::Escape($pattern)) -Message "Updater helper contract docs should mention: $pattern"
    }
  }

  It "ships downstream consumer examples for the updater path" {
    foreach ($relativePath in @(
      "examples/downstream/package-release-with-updates.yml",
      "examples/downstream/objc/AppDelegate+Updates.m",
      "updater/objc/GPUpdaterUI/Headers/GPStandardUpdaterController.h",
      "updater/objc/gp-update-helper/Source/main.m"
    )) {
      Assert-GpTrue -Condition (Test-Path (Join-Path $script:repoRoot $relativePath)) -Message "Expected updater example or source file at $relativePath"
    }
  }

  It "documents the default app integration surface" {
    foreach ($pattern in @(
      "GPStandardUpdaterController",
      "gp-update-helper",
      "Check for Updates",
      "Restart and Install"
    )) {
      Assert-GpTrue -Condition ($script:consumerDocText -match [regex]::Escape($pattern)) -Message "Updater consumer docs should mention: $pattern"
    }
  }
}
