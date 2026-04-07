param(
  [Parameter(Mandatory = $true)]
  [string]$StageRoot,

  [Parameter(Mandatory = $true)]
  [string]$ArchivePath
)

$ErrorActionPreference = "Stop"

if (Test-Path -LiteralPath $ArchivePath) {
  Remove-Item -LiteralPath $ArchivePath -Force
}

$outputPath = Join-Path $StageRoot "output"
if (-not (Test-Path -LiteralPath $outputPath)) {
  throw ("remote output directory missing: " + $outputPath)
}

& tar.exe -czf $ArchivePath -C $StageRoot output
if ($LASTEXITCODE -ne 0) {
  throw ("tar.exe failed with exit code " + $LASTEXITCODE)
}
