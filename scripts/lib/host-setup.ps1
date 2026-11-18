# Host setup: which packages an app's manifest needs on the build host
# (hostDependencies), how the reusable workflow plans their installation, and
# the MSYS2 (pacman) and apt installers and preflight that act on that plan.
# Moved out of core.ps1 unchanged. core.ps1 dot-sources this file, so callers
# still load core.ps1 alone. See docs/core-library-layout.md.

Set-StrictMode -Version Latest

function Get-GpHostDependencyProviders {
  $providers = [System.Collections.Generic.List[psobject]]::new()

  $providers.Add([pscustomobject]@{
    Id                      = "windows-msys2"
    Platform                = "windows"
    PackageManager          = "msys2"
    ManifestPlatformKey     = "windows"
    ManifestPackageListKey  = "msys2Packages"
    WorkflowInputName       = "msys2-packages"
    WorkflowOutputPrefix    = "msys2"
    DisplayName             = "Windows MSYS2"
  }) | Out-Null

  $providers.Add([pscustomobject]@{
    Id                      = "linux-apt"
    Platform                = "linux"
    PackageManager          = "apt"
    ManifestPlatformKey     = "linux"
    ManifestPackageListKey  = "aptPackages"
    WorkflowInputName       = "appimage-apt-packages"
    WorkflowOutputPrefix    = "apt"
    DisplayName             = "Linux apt"
  }) | Out-Null

  return @($providers.ToArray())
}

function Get-GpHostDependencyProvider {
  param(
    [string]$Id,
    [string]$Platform,
    [string]$PackageManager
  )

  foreach ($provider in @(Get-GpHostDependencyProviders)) {
    if (-not [string]::IsNullOrWhiteSpace($Id) -and $provider.Id -eq $Id) {
      return $provider
    }

    if (-not [string]::IsNullOrWhiteSpace($Platform) -and
        -not [string]::IsNullOrWhiteSpace($PackageManager) -and
        $provider.Platform -eq $Platform -and
        $provider.PackageManager -eq $PackageManager) {
      return $provider
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($Id)) {
    throw "Unsupported host dependency provider: $Id"
  }

  throw "Unsupported host dependency provider for platform '$Platform' and package manager '$PackageManager'."
}

function Get-GpNonEmptyStringList {
  param(
    [AllowNull()]
    [object[]]$Values
  )

  $items = [System.Collections.Generic.List[string]]::new()
  foreach ($value in @($Values)) {
    if ($value -is [string] -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
      $items.Add(([string]$value).Trim()) | Out-Null
    }
  }

  return [string[]]@($items.ToArray())
}

function Join-GpUniquePackageList {
  param(
    [AllowNull()]
    [object[]]$Values
  )

  $items = [System.Collections.Generic.List[string]]::new()
  foreach ($value in @($Values)) {
    if ($null -eq $value) {
      continue
    }

    foreach ($line in @(([string]$value) -split '\s+')) {
      $trimmed = $line.Trim()
      if (-not [string]::IsNullOrWhiteSpace($trimmed) -and -not $items.Contains($trimmed)) {
        $items.Add($trimmed) | Out-Null
      }
    }
  }

  return [string]::Join(' ', @($items))
}

function Get-GpManifestHostDependencyGroups {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Manifest
  )

  $hostDependencies = if ($Manifest.Contains("hostDependencies") -and ($Manifest["hostDependencies"] -is [System.Collections.IDictionary])) {
    $Manifest["hostDependencies"]
  } else {
    @{}
  }

  $groups = [System.Collections.Generic.List[psobject]]::new()
  foreach ($provider in @(Get-GpHostDependencyProviders)) {
    $platformConfig = if ($hostDependencies.Contains($provider.ManifestPlatformKey) -and ($hostDependencies[$provider.ManifestPlatformKey] -is [System.Collections.IDictionary])) {
      $hostDependencies[$provider.ManifestPlatformKey]
    } else {
      @{}
    }

    $packages = @(Get-GpNonEmptyStringList -Values @($platformConfig[$provider.ManifestPackageListKey]))
    if ($packages.Count -le 0) {
      continue
    }

    $groups.Add([pscustomobject]@{
      ProviderId             = $provider.Id
      Platform               = $provider.Platform
      PackageManager         = $provider.PackageManager
      ManifestPlatformKey    = $provider.ManifestPlatformKey
      ManifestPackageListKey = $provider.ManifestPackageListKey
      Packages               = [string[]]@($packages)
    }) | Out-Null
  }

  return @($groups.ToArray())
}

function Get-GpHostDependencies {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context
  )

  $groups = @(Get-GpManifestHostDependencyGroups -Manifest $Context.Manifest)
  $windowsMsys2 = @($groups | Where-Object { $_.ProviderId -eq "windows-msys2" } | Select-Object -First 1)
  $linuxApt = @($groups | Where-Object { $_.ProviderId -eq "linux-apt" } | Select-Object -First 1)

  return [pscustomobject]@{
    Groups = @($groups)
    WindowsMsys2Packages = [string[]]@($(if ($windowsMsys2.Count -gt 0) { $windowsMsys2[0].Packages } else { @() }))
    LinuxAptPackages = [string[]]@($(if ($linuxApt.Count -gt 0) { $linuxApt[0].Packages } else { @() }))
  }
}

function Get-GpHostDependencyPlan {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [string]$Backend
  )

  $platform = Get-GpHostPlatform
  $groups = [System.Collections.Generic.List[psobject]]::new()
  foreach ($group in @(Get-GpManifestHostDependencyGroups -Manifest $Context.Manifest)) {
    if ($group.Platform -ne $platform) {
      continue
    }

    $groups.Add([pscustomobject]@{
      ProviderId = $group.ProviderId
      Platform = $group.Platform
      PackageManager = $group.PackageManager
      Packages = [string[]]@($group.Packages)
      Backend = $(if (-not [string]::IsNullOrWhiteSpace($Backend)) { $Backend } else { $null })
    }) | Out-Null
  }

  return [pscustomobject]@{
    HostPlatform = $platform
    Groups = @($groups.ToArray())
  }
}

function Get-GpWorkflowHostSetupPlan {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [string]$Backend,
    [switch]$SkipDefaultHostSetup,
    [string]$AdditionalMsys2Packages,
    [string]$Msys2PackageUrls,
    [string]$AdditionalAptPackages
  )

  $hostDependencies = Get-GpHostDependencies -Context $Context
  $errors = [System.Collections.Generic.List[string]]::new()
  $mode = if ($SkipDefaultHostSetup) { "verify-only" } else { "install-and-verify" }

  $manifestMsys2Packages = [string[]]@($hostDependencies.WindowsMsys2Packages)
  $manifestAptPackages = [string[]]@($hostDependencies.LinuxAptPackages)
  $additionalMsys2Text = Join-GpUniquePackageList -Values @($AdditionalMsys2Packages)
  $additionalAptText = Join-GpUniquePackageList -Values @($AdditionalAptPackages)
  $msys2PackageUrlText = Join-GpUniquePackageList -Values @($Msys2PackageUrls)

  if ($SkipDefaultHostSetup -and $Backend -eq "msi" -and -not [string]::IsNullOrWhiteSpace($msys2PackageUrlText)) {
    $errors.Add('`msys2-package-urls` is not applied when `skip-default-host-setup: true`. Install those packages in your caller preflight.') | Out-Null
  }

  if ($SkipDefaultHostSetup -and $Backend -eq "msi" -and -not [string]::IsNullOrWhiteSpace($additionalMsys2Text)) {
    $errors.Add('`msys2-packages` is not applied when `skip-default-host-setup: true`. Declare app-specific MSYS2 packages under `hostDependencies.windows.msys2Packages` or install them in your caller preflight.') | Out-Null
  }

  if ($SkipDefaultHostSetup -and $Backend -eq "appimage" -and -not [string]::IsNullOrWhiteSpace($additionalAptText)) {
    $errors.Add('`appimage-apt-packages` is not applied when `skip-default-host-setup: true`. Declare app-specific apt packages under `hostDependencies.linux.aptPackages` or install them in your caller preflight.') | Out-Null
  }

  $summary = if ($SkipDefaultHostSetup) {
    "Default host setup disabled; the workflow will rely on caller preflight and shared manifest-driven verification on the target runner."
  } else {
    "Default host setup enabled; the workflow will install the documented backend baseline plus manifest-declared and additive host packages before packaging."
  }

  return [pscustomobject]@{
    Backend = $Backend
    HostSetupMode = $mode
    Summary = $summary
    ShouldInstallManifestDependencies = (-not [bool]$SkipDefaultHostSetup)
    ManifestMsys2Packages = [string[]]@($manifestMsys2Packages)
    ManifestAptPackages = [string[]]@($manifestAptPackages)
    ManifestMsys2PackageText = Join-GpUniquePackageList -Values @($manifestMsys2Packages)
    ManifestAptPackageText = Join-GpUniquePackageList -Values @($manifestAptPackages)
    ResolvedMsys2PackageText = Join-GpUniquePackageList -Values @($AdditionalMsys2Packages, (Join-GpUniquePackageList -Values @($manifestMsys2Packages)))
    ResolvedAptPackageText = Join-GpUniquePackageList -Values @($AdditionalAptPackages, (Join-GpUniquePackageList -Values @($manifestAptPackages)))
    Msys2PackageUrlText = $msys2PackageUrlText
    Errors = [string[]]@($errors.ToArray())
  }
}

function Get-GpMsys2PacmanPath {
  $candidates = [System.Collections.Generic.List[string]]::new()
  if (-not [string]::IsNullOrWhiteSpace($env:MSYS2_LOCATION)) {
    $candidates.Add((Join-Path $env:MSYS2_LOCATION "usr\\bin\\pacman.exe")) | Out-Null
  }
  $candidates.Add("C:\\msys64\\usr\\bin\\pacman.exe") | Out-Null

  foreach ($candidate in @($candidates)) {
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
      return $candidate
    }
  }

  $command = Get-Command pacman.exe -ErrorAction SilentlyContinue
  if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source)) {
    return [string]$command.Source
  }

  return $null
}

function Get-GpMissingMsys2Packages {
  param(
    [string[]]$Packages = @()
  )

  $pacmanPath = Get-GpMsys2PacmanPath
  if ([string]::IsNullOrWhiteSpace($pacmanPath)) {
    throw "MSYS2 pacman.exe was not found. Set MSYS2_LOCATION or install the documented MSYS2 CLANG64 baseline."
  }

  $missing = [System.Collections.Generic.List[string]]::new()
  foreach ($packageName in @($Packages)) {
    $result = Invoke-GpCapturedProcess -FilePath $pacmanPath -ArgumentList @("-Q", "--", $packageName)
    if ($result.ExitCode -ne 0) {
      $missing.Add($packageName) | Out-Null
    }
  }

  return [string[]]@($missing.ToArray())
}

function Install-GpMsys2Packages {
  param(
    [string[]]$Packages = @()
  )

  $pacmanPath = Get-GpMsys2PacmanPath
  if ([string]::IsNullOrWhiteSpace($pacmanPath)) {
    throw "MSYS2 pacman.exe was not found. Set MSYS2_LOCATION or install the documented MSYS2 CLANG64 baseline."
  }

  $result = Invoke-GpCapturedProcess -FilePath $pacmanPath -ArgumentList @("-S", "--needed", "--noconfirm", "--") + @($Packages)
  if ($result.ExitCode -ne 0) {
    $detail = @($result.StdOut, $result.StdErr) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    throw ("MSYS2 package installation failed for: {0}. {1}" -f ([string]::Join(", ", @($Packages))), ([string]::Join(" ", $detail)).Trim())
  }
}

function Get-GpAptProgram {
  $command = Get-Command apt-get -ErrorAction SilentlyContinue
  if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source)) {
    return [string]$command.Source
  }
  return $null
}

function Get-GpMissingAptPackages {
  param(
    [string[]]$Packages = @()
  )

  $dpkgQuery = Get-Command dpkg-query -ErrorAction SilentlyContinue
  if ($null -eq $dpkgQuery -or [string]::IsNullOrWhiteSpace([string]$dpkgQuery.Source)) {
    throw "dpkg-query was not found. Linux apt host dependency verification requires a Debian/Ubuntu-style host with dpkg-query available."
  }

  $missing = [System.Collections.Generic.List[string]]::new()
  foreach ($packageName in @($Packages)) {
    $result = Invoke-GpCapturedProcess -FilePath ([string]$dpkgQuery.Source) -ArgumentList @("-W", '-f=${Status}', "--", $packageName)
    if (($result.ExitCode -ne 0) -or ($result.StdOut -notmatch "install ok installed")) {
      $missing.Add($packageName) | Out-Null
    }
  }

  return [string[]]@($missing.ToArray())
}

function Install-GpAptPackages {
  param(
    [string[]]$Packages = @()
  )

  $aptGet = Get-GpAptProgram
  if ([string]::IsNullOrWhiteSpace($aptGet)) {
    throw "apt-get was not found. Linux apt host dependency installation requires a Debian/Ubuntu-style host with apt-get available."
  }

  $sudo = Get-Command sudo -ErrorAction SilentlyContinue
  $prefix = @()
  if ((Get-Command id -ErrorAction SilentlyContinue) -and ((& id -u) -ne "0")) {
    if ($null -eq $sudo -or [string]::IsNullOrWhiteSpace([string]$sudo.Source)) {
      throw "Installing Linux host dependencies requires root or sudo access."
    }
    $prefix = @([string]$sudo.Source)
  }

  foreach ($command in @(
    @($aptGet, "update"),
    @($aptGet, "install", "-y", "--no-install-recommends") + @($Packages)
  )) {
    $filePath = if ($prefix.Count -gt 0) { $prefix[0] } else { $command[0] }
    $argumentList = if ($prefix.Count -gt 0) { @($command) } else { @($command | Select-Object -Skip 1) }
    if ($prefix.Count -eq 0) {
      $filePath = $command[0]
    }

    $result = Invoke-GpCapturedProcess -FilePath $filePath -ArgumentList $argumentList
    if ($result.ExitCode -ne 0) {
      $detail = @($result.StdOut, $result.StdErr) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
      throw ("apt dependency command failed: {0}. {1}" -f ([string]::Join(" ", @($command))), ([string]::Join(" ", $detail)).Trim())
    }
  }
}

function Get-GpMissingHostDependencyPackages {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Provider,
    [string[]]$Packages = @()
  )

  switch ($Provider.PackageManager) {
    "msys2" { return @(Get-GpMissingMsys2Packages -Packages @($Packages)) }
    "apt" { return @(Get-GpMissingAptPackages -Packages @($Packages)) }
    default { throw "Unsupported host package manager: $($Provider.PackageManager)" }
  }
}

function Install-GpHostDependencyPackages {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Provider,
    [string[]]$Packages = @()
  )

  switch ($Provider.PackageManager) {
    "msys2" { Install-GpMsys2Packages -Packages @($Packages); break }
    "apt" { Install-GpAptPackages -Packages @($Packages); break }
    default { throw "Unsupported host package manager: $($Provider.PackageManager)" }
  }
}

function Invoke-GpHostDependencyPreflight {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Context,
    [string]$Backend,
    [string]$LogPath,
    [switch]$InstallMissing,
    [switch]$DryRun
  )

  if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $LogPath = New-GpCommandLogPath -Context $Context -CommandName "host-preflight"
  }

  Ensure-GpDirectory -Path (Split-Path -Parent $LogPath) | Out-Null
  $plan = Get-GpHostDependencyPlan -Context $Context -Backend $Backend
  $lines = [System.Collections.Generic.List[string]]::new()
  $lines.Add(("[{0}] host-platform={1}" -f (Get-Date).ToString("o"), $plan.HostPlatform)) | Out-Null

  if (@($plan.Groups).Count -eq 0) {
    $lines.Add("No manifest-declared host dependencies apply to this host.") | Out-Null
    Set-Content -Path $LogPath -Value $lines
    return [pscustomobject]@{
      HostPlatform = $plan.HostPlatform
      Groups = @()
      LogPath = $LogPath
      InstallMode = [bool]$InstallMissing
      DryRun = [bool]$DryRun
    }
  }

  foreach ($group in @($plan.Groups)) {
    $provider = Get-GpHostDependencyProvider -Id $group.ProviderId
    $lines.Add(("Checking {0} packages: {1}" -f $group.PackageManager, ([string]::Join(", ", @($group.Packages))))) | Out-Null
    if ($DryRun) {
      $lines.Add(("DRYRUN  would verify {0} packages" -f $group.PackageManager)) | Out-Null
      continue
    }

    $missing = @(Get-GpMissingHostDependencyPackages -Provider $provider -Packages @($group.Packages))

    if ($missing.Count -eq 0) {
      $lines.Add(("OK      all declared {0} packages are already present" -f $group.PackageManager)) | Out-Null
      continue
    }

    $lines.Add(("MISSING {0}" -f ([string]::Join(", ", $missing)))) | Out-Null
    if (-not $InstallMissing) {
      Set-Content -Path $LogPath -Value $lines
      throw ("Missing declared {0} host dependencies: {1}. Re-run with -InstallHostDependencies or set GP_INSTALL_HOST_DEPENDENCIES=1. See log: {2}" -f $group.PackageManager, ([string]::Join(", ", $missing)), $LogPath)
    }

    $lines.Add(("INSTALL {0}" -f ([string]::Join(", ", $missing)))) | Out-Null
    Install-GpHostDependencyPackages -Provider $provider -Packages $missing
    $lines.Add(("OK      installed missing {0} packages" -f $group.PackageManager)) | Out-Null
  }

  Set-Content -Path $LogPath -Value $lines
  return [pscustomobject]@{
    HostPlatform = $plan.HostPlatform
    Groups = @($plan.Groups)
    LogPath = $LogPath
    InstallMode = [bool]$InstallMissing
    DryRun = [bool]$DryRun
  }
}
