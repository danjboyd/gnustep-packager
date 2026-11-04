# Stage ThemeDemo and the GNUstep runtime it needs. gnustep-packager builds and
# adds the theme itself from themeInputs after this script.
[CmdletBinding()]
param(
  [string]$StageRoot = "dist/stage"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$msysRoot = @($env:GP_GNUSTEP_CLI_ROOT, $env:MSYS2_LOCATION, "C:\msys64") |
  Where-Object { $_ -and (Test-Path (Join-Path $_ "clang64")) } |
  Select-Object -First 1
if (-not $msysRoot) {
  throw "No CLANG64 root found. Set GP_GNUSTEP_CLI_ROOT or MSYS2_LOCATION."
}
$clang64 = Join-Path $msysRoot "clang64"

$stage = [System.IO.Path]::GetFullPath($StageRoot)
$runtime = Join-Path $stage "runtime"
$runtimeBin = Join-Path $runtime "bin"
$systemLibrary = Join-Path $runtime "System\Library"
$systemTools = Join-Path $runtime "System\Tools"

if (Test-Path $stage) {
  Remove-Item -Recurse -Force $stage
}
foreach ($directory in @((Join-Path $stage "app"), $runtimeBin, $systemLibrary, $systemTools, (Join-Path $stage "metadata\licenses"), (Join-Path $stage "metadata\icons"))) {
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
}

Copy-Item -Recurse -Path "Examples\ThemeDemo\ThemeDemo.app" -Destination (Join-Path $stage "app")

# The bundles GNUstep loads at run time and gnustep-gui's shared resources. The
# toolchain's Themes are left out, so the only theme is the one built here.
foreach ($name in @("Bundles", "Images", "KeyBindings", "Fonts", "ColorPickers", "PostScript", "DTDs", "Services", "Sounds")) {
  $source = Join-Path $clang64 "lib\GNUstep\$name"
  if (Test-Path $source) {
    Copy-Item -Recurse -Path $source -Destination $systemLibrary
  }
}

$fonts = Join-Path $clang64 "etc\fonts"
if (Test-Path $fonts) {
  New-Item -ItemType Directory -Force -Path (Join-Path $runtime "etc") | Out-Null
  Copy-Item -Recurse -Path $fonts -Destination (Join-Path $runtime "etc")
}

# gdnc and make_services start with the app; gpbs with the first pasteboard use.
foreach ($tool in @("gdnc.exe", "gpbs.exe", "make_services.exe")) {
  Copy-Item -Path (Join-Path $clang64 "bin\$tool") -Destination $systemTools
}
# Seeding packagedDefaults.defaultTheme runs the bundled defaults tool from here.
Copy-Item -Path (Join-Path $clang64 "bin\defaults.exe") -Destination $runtimeBin

# The DLLs everything staged so far imports, and the DLLs those import. A name
# that isn't in CLANG64 is taken as Windows' own; the packager's closure check
# fails the build on anything else.
$objdump = Join-Path $clang64 "bin\llvm-objdump.exe"
$available = @{}
foreach ($dll in Get-ChildItem -Path (Join-Path $clang64 "bin") -Filter "*.dll" -File) {
  $available[$dll.Name] = $dll.FullName
}
$queue = [System.Collections.Generic.Queue[string]]::new()
foreach ($file in Get-ChildItem -Path $stage -Recurse -File -Include *.dll, *.exe) {
  $queue.Enqueue($file.FullName)
}
$seen = @{}
while ($queue.Count -gt 0) {
  $target = $queue.Dequeue()
  if ($seen.ContainsKey($target)) {
    continue
  }
  $seen[$target] = $true
  foreach ($line in & $objdump -p $target 2>$null) {
    if ($line -match 'DLL Name:\s+(\S+)' -and $available.ContainsKey($Matches[1])) {
      $destination = Join-Path $runtimeBin $Matches[1]
      if (-not (Test-Path $destination)) {
        Copy-Item -Path $available[$Matches[1]] -Destination $destination
      }
      $queue.Enqueue($destination)
    }
  }
}
$global:LASTEXITCODE = 0

# Point every GNUstep domain into the package. The packager stages the theme in
# runtime/lib/GNUstep/Themes, so that is the Local domain's library.
Set-Content -Path (Join-Path $runtimeBin "GNUstep.conf") -Encoding ascii -Value @(
  "GNUSTEP_USER_CONFIG_FILE=",
  "GNUSTEP_SYSTEM_ROOT=../System",
  "GNUSTEP_LOCAL_ROOT=../System",
  "GNUSTEP_NETWORK_ROOT=../System",
  "GNUSTEP_SYSTEM_LIBRARY=../System/Library",
  "GNUSTEP_SYSTEM_TOOLS=../System/Tools",
  "GNUSTEP_NETWORK_LIBRARY=../System/Library",
  "GNUSTEP_NETWORK_TOOLS=../System/Tools",
  "GNUSTEP_LOCAL_LIBRARY=../lib/GNUstep",
  "GNUSTEP_LOCAL_TOOLS=../System/Tools"
)

Set-Content -Path (Join-Path $stage "metadata\licenses\gnustep-runtime.txt") -Encoding ascii -Value @(
  "This package includes the GNUstep Base and GUI libraries, under the GNU Lesser",
  "General Public License, version 2.1 or later:",
  "https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html"
)
