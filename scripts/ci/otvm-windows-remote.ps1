param(
  [string]$Backend = "windows-msys2-clang64",

  [string]$CLI = "input/gnustep.exe",

  [string]$Manifest = "repo/examples/sample-gui/package.manifest.json"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

$StageRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$OutputRoot = Join-Path $StageRoot "output"
$RepoRoot = Join-Path $StageRoot "repo"
$CliPath = Join-Path $StageRoot $CLI
$ManifestPath = Join-Path $StageRoot $Manifest

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$env:GNUSTEP_CLI_HOME = Join-Path $OutputRoot "gnustep-home"
$env:GOCACHE = Join-Path $OutputRoot "go-build"

if (-not (Test-Path -LiteralPath $CliPath)) {
  throw ("gnustep-cli binary not found: " + $CliPath)
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
  throw ("packager manifest not found: " + $ManifestPath)
}

function Invoke-GpOtvmStep {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(Mandatory = $true)]
    [scriptblock]$Body
  )

  $logPath = Join-Path $OutputRoot ($Name + ".log")
  & $Body *>&1 | Tee-Object -FilePath $logPath
}

function Invoke-GpCliInstallPlan {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Backend,
    [Parameter(Mandatory = $true)]
    [string]$CliPath,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  $planOutput = & $CliPath toolchain install $Backend 2>&1
  $exitCode = $LASTEXITCODE
  $planOutput | Set-Content -Path $LogPath
  if ($exitCode -ne 0) {
    throw ("gnustep toolchain install planning failed with exit code " + $exitCode)
  }

  $planLine = @($planOutput | Where-Object { $_ -is [string] -and $_.StartsWith("Plan: ") } | Select-Object -First 1)
  if ($planLine.Count -eq 0) {
    throw "gnustep toolchain install did not report a plan path."
  }

  $planPath = $planLine[0].Substring(6).Trim()
  if (-not (Test-Path -LiteralPath $planPath)) {
    throw ("gnustep toolchain install reported a missing plan path: " + $planPath)
  }

  $plan = Get-Content -Raw -Path $planPath | ConvertFrom-Json
  foreach ($step in @($plan.steps)) {
    Write-Host ("== " + $step.name)
    foreach ($command in @($step.commands)) {
      Write-Host ("> " + $command)
      $commandOutput = & ([scriptblock]::Create("& {`n" + $command + "`n} 2>&1"))
      $exitCode = $LASTEXITCODE
      if ($null -ne $commandOutput) {
        $commandOutput
      }
      if ($exitCode -ne 0) {
        throw ("toolchain install step failed with exit code " + $exitCode + ": " + $step.name)
      }
    }
  }
}

$failure = $null

try {
  Invoke-GpOtvmStep -Name "toolchain-install" -Body {
    Invoke-GpCliInstallPlan -Backend $Backend -CliPath $CliPath -LogPath (Join-Path $OutputRoot "toolchain-install-plan.log")
  }

  Invoke-GpOtvmStep -Name "toolchain-use" -Body {
    & $CliPath toolchain use ($Backend + "/stable") --json
  }

  Invoke-GpOtvmStep -Name "toolchain-inspect" -Body {
    & $CliPath toolchain inspect ($Backend + "/stable") --json
  }

  if ($Backend -eq "windows-msys2-clang64") {
    $env:MSYS2_LOCATION = "C:\msys64"
  }

  Push-Location (Split-Path -Parent $ManifestPath)
  try {
    Invoke-GpOtvmStep -Name "packager-build" -Body {
      & (Join-Path $RepoRoot "scripts\gnustep-packager.ps1") -Command build -Manifest $ManifestPath
    }

    Invoke-GpOtvmStep -Name "packager-stage" -Body {
      & (Join-Path $RepoRoot "scripts\gnustep-packager.ps1") -Command stage -Manifest $ManifestPath
    }

    Invoke-GpOtvmStep -Name "packager-package-msi" -Body {
      & (Join-Path $RepoRoot "scripts\gnustep-packager.ps1") -Command package -Manifest $ManifestPath -Backend msi
    }

    Invoke-GpOtvmStep -Name "packager-validate-msi" -Body {
      & (Join-Path $RepoRoot "scripts\gnustep-packager.ps1") -Command validate -Manifest $ManifestPath -Backend msi -RunSmoke
    }
  } finally {
    Pop-Location
  }
} catch {
  $failure = $_
} finally {
  $evidenceRoot = Join-Path $OutputRoot "sample-gui"
  New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null
  foreach ($relativePath in @("dist", "out")) {
    $source = Join-Path (Split-Path -Parent $ManifestPath) $relativePath
    $destination = Join-Path $evidenceRoot $relativePath
    if (Test-Path -LiteralPath $source) {
      Copy-Item -Recurse -Force $source $destination
    }
  }
}

if ($null -ne $failure) {
  throw $failure
}
