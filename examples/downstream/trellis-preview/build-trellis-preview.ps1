# Build Trellis and TrellisPreview in the toolchain's CLANG64 shell, with
# TRLoader's dev hot reload compiled out (hot_reload=no).
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$msysRoot = @($env:GP_GNUSTEP_CLI_ROOT, $env:MSYS2_LOCATION, "C:\msys64") |
  Where-Object { $_ -and (Test-Path (Join-Path $_ "clang64")) } |
  Select-Object -First 1
if (-not $msysRoot) {
  throw "No CLANG64 root found. Set GP_GNUSTEP_CLI_ROOT or MSYS2_LOCATION."
}
$clang64 = Join-Path $msysRoot "clang64"
$gnustepSh = Get-ChildItem -Path $clang64 -Recurse -File -Filter "GNUstep.sh" | Select-Object -First 1
if (-not $gnustepSh) {
  throw "GNUstep.sh not found under $clang64."
}

$env:MSYSTEM = "CLANG64"
$repo = (Get-Location).Path
$command = "set -e; cd `"`$(cygpath -u '$repo')`"; . `"`$(cygpath -u '$($gnustepSh.FullName)')`"; make hot_reload=no"
& (Join-Path $msysRoot "usr\bin\bash.exe") -lc $command
if ($LASTEXITCODE -ne 0) {
  throw "Trellis build failed with exit code $LASTEXITCODE"
}
