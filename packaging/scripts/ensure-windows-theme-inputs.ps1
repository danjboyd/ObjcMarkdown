[CmdletBinding()]
param(
  [string]$ThemeWorkspace,
  [string]$MsysRoot = $(if (-not [string]::IsNullOrWhiteSpace($env:GP_GNUSTEP_CLI_ROOT)) {
      $env:GP_GNUSTEP_CLI_ROOT
    } elseif (-not [string]::IsNullOrWhiteSpace($env:GNUSTEP_CLI_ROOT)) {
      $env:GNUSTEP_CLI_ROOT
    } elseif (-not [string]::IsNullOrWhiteSpace($env:MSYS2_LOCATION)) {
      $env:MSYS2_LOCATION
    } else {
      "C:\msys64"
    })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$resolvedMsysRoot = [System.IO.Path]::GetFullPath($MsysRoot)

function Convert-ToMsysPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$WindowsPath,
    [string]$DrivePrefix = $script:OmdMsysDrivePrefix
  )

  $fullPath = [System.IO.Path]::GetFullPath($WindowsPath)
  $normalized = $fullPath -replace "\\", "/"
  if ($normalized -match "^([A-Za-z]):(/.*)?$") {
    $drive = $Matches[1].ToLowerInvariant()
    $rest = if ($Matches[2]) { $Matches[2] } else { "" }
    return "$DrivePrefix/$drive$rest"
  }

  throw "Unable to convert Windows path to MSYS2 path: $WindowsPath"
}

function Resolve-OmdMsysDrivePrefix {
  param(
    [Parameter(Mandatory = $true)]
    [string]$EnvExe
  )

  $prefix = Invoke-OmdMsysEnv -EnvExe $EnvExe -Arguments @(
    'MSYSTEM=CLANG64',
    'CHERE_INVOKING=1',
    '/usr/bin/bash',
    '-lc',
    'cygpath -u C:/ 2>/dev/null | grep -q "^/cygdrive/" && printf "/cygdrive"; exit 0'
  )
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to resolve MSYS2 drive mount prefix."
  }

  return [string]$prefix
}

function Invoke-OmdMsysEnv {
  param(
    [Parameter(Mandatory = $true)]
    [string]$EnvExe,
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  $startDirectory = Split-Path -Parent $EnvExe
  $previousLocation = (Get-Location).Path
  Set-Location -LiteralPath $startDirectory
  try {
    & $EnvExe @Arguments
  } finally {
    Set-Location -LiteralPath $previousLocation
  }
}

function Resolve-OmdPathCandidate {
  param(
    [Parameter(Mandatory = $true)]
    [string]$BasePath,
    [Parameter(Mandatory = $true)]
    [string]$Candidate
  )

  if ([string]::IsNullOrWhiteSpace($Candidate)) {
    return $null
  }

  if ([System.IO.Path]::IsPathRooted($Candidate)) {
    return [System.IO.Path]::GetFullPath($Candidate)
  }

  return [System.IO.Path]::GetFullPath((Join-Path $BasePath $Candidate))
}

function Invoke-OmdMsysCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$MsysRoot,
    [Parameter(Mandatory = $true)]
    [string]$WorkingDirectory,
    [Parameter(Mandatory = $true)]
    [string]$InnerCommand,
    [hashtable]$Environment = @{}
  )

  $envExe = Join-Path $MsysRoot "usr\bin\env.exe"
  if (-not (Test-Path $envExe)) {
    throw "MSYS2 env.exe not found at $envExe"
  }

  $gnuStepSh = Join-Path $MsysRoot "clang64\share\GNUstep\Makefiles\GNUstep.sh"
  if (-not (Test-Path $gnuStepSh)) {
    throw "GNUstep.sh not found at $gnuStepSh"
  }

  $drivePrefix = Resolve-OmdMsysDrivePrefix -EnvExe $envExe
  $bootstrapLines = @(
    "if [ -f /etc/profile ]; then source /etc/profile; fi",
    "source /clang64/share/GNUstep/Makefiles/GNUstep.sh",
    "export PATH=/usr/bin:/clang64/bin:/mingw64/bin:`$PATH"
  )

  foreach ($entry in $Environment.GetEnumerator()) {
    $escapedValue = ([string]$entry.Value).Replace("'", "'\''")
    $bootstrapLines += ("export {0}='{1}'" -f $entry.Key, $escapedValue)
  }

  $workingDirectoryMsys = Convert-ToMsysPath -WindowsPath $WorkingDirectory -DrivePrefix $drivePrefix
  $bootstrapLines += ("cd '{0}'" -f $workingDirectoryMsys)
  $bootstrapLines += $InnerCommand
  $bootstrap = ($bootstrapLines -join "; ")

  Invoke-OmdMsysEnv -EnvExe $envExe -Arguments @('MSYSTEM=CLANG64', 'CHERE_INVOKING=1', '/usr/bin/bash', '-lc', $bootstrap) 2>&1 | ForEach-Object {
    $_
  }
  if ($LASTEXITCODE -ne 0) {
    throw "MSYS2 command failed with exit code $LASTEXITCODE"
  }
}

function Resolve-OmdThemeRepo {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoName,
    [Parameter(Mandatory = $true)]
    [string[]]$Candidates
  )

  foreach ($candidate in $Candidates) {
    if ([string]::IsNullOrWhiteSpace($candidate)) {
      continue
    }

    if ((Test-Path $candidate) -and (Test-Path (Join-Path $candidate "GNUmakefile"))) {
      return [System.IO.Path]::GetFullPath($candidate)
    }
  }

  throw "Required theme repository '$RepoName' was not found. Checked: $($Candidates -join ', ')"
}

function Get-OmdManifestThemeInput {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ThemeName
  )

  $manifestPath = Join-Path $repoRoot "packaging\manifests\windows-msi.manifest.json"
  if (-not (Test-Path $manifestPath)) {
    return $null
  }

  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  foreach ($themeInput in @($manifest.themeInputs)) {
    if ([string]$themeInput.name -eq $ThemeName) {
      return $themeInput
    }
  }

  return $null
}

function Ensure-OmdThemeRepoFromManifest {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ThemeName,
    [Parameter(Mandatory = $true)]
    [string]$RepoName,
    [bool]$Required = $true
  )

  $themeInput = Get-OmdManifestThemeInput -ThemeName $ThemeName
  if (-not $themeInput) {
    return $null
  }

  $repoUrl = [string]$themeInput.repo
  $repoRef = [string]$themeInput.ref
  if ([string]::IsNullOrWhiteSpace($repoUrl) -or [string]::IsNullOrWhiteSpace($repoRef)) {
    return $null
  }

  $themeInputsRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot ".omd-theme-inputs"))
  $destination = [System.IO.Path]::GetFullPath((Join-Path $themeInputsRoot $RepoName))
  if ((Test-Path (Join-Path $destination "GNUmakefile"))) {
    return $destination
  }

  New-Item -ItemType Directory -Force -Path $themeInputsRoot | Out-Null

  if (-not (Test-Path (Join-Path $destination ".git"))) {
    if (Test-Path $destination) {
      Remove-Item -LiteralPath $destination -Recurse -Force
    }

    & git clone $repoUrl $destination
    if ($LASTEXITCODE -ne 0) {
      if (-not $Required) {
        Write-Warning "Skipping optional theme repository $repoUrl; clone failed."
        return $null
      }
      throw "Failed to clone theme repository $repoUrl into $destination"
    }
  }

  & git -C $destination fetch --tags --force origin
  if ($LASTEXITCODE -ne 0) {
    if (-not $Required) {
      Write-Warning "Skipping optional theme repository $repoUrl; fetch failed."
      return $null
    }
    throw "Failed to fetch theme repository $repoUrl"
  }

  & git -C $destination checkout --force $repoRef
  if ($LASTEXITCODE -ne 0) {
    if (-not $Required) {
      Write-Warning "Skipping optional theme repository $repoUrl; checkout of $repoRef failed."
      return $null
    }
    throw "Failed to checkout theme repository $repoUrl at $repoRef"
  }

  if (-not (Test-Path (Join-Path $destination "GNUmakefile"))) {
    if (-not $Required) {
      Write-Warning "Skipping optional theme repository $repoUrl; GNUmakefile was not found at $repoRef."
      return $null
    }
    throw "Theme repository $repoUrl at $repoRef does not contain GNUmakefile"
  }

  return $destination
}

function Sync-OmdThemeImageCompatibilityResources {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ThemeRepository
  )

  $themeImages = Join-Path $ThemeRepository "Resources\ThemeImages"
  if (-not (Test-Path $themeImages)) {
    return
  }

  $gsThemeImages = Join-Path $ThemeRepository "Resources\GSThemeImages"
  New-Item -ItemType Directory -Force -Path $gsThemeImages | Out-Null
  foreach ($image in @(Get-ChildItem -LiteralPath $themeImages -File -ErrorAction SilentlyContinue)) {
    Copy-Item -LiteralPath $image.FullName -Destination $gsThemeImages -Force
    Copy-Item -LiteralPath $image.FullName -Destination (Join-Path $ThemeRepository "Resources") -Force
  }
}

function Resolve-OmdUserThemeRoot {
  param(
    [Parameter(Mandatory = $true)]
    [string]$MsysRoot,
    [Parameter(Mandatory = $true)]
    [string[]]$ThemeNames
  )

  $candidateRoots = [System.Collections.Generic.List[string]]::new()

  if (-not [string]::IsNullOrWhiteSpace($env:OMD_GNUSTEP_USER_THEME_ROOT)) {
    $candidateRoots.Add([System.IO.Path]::GetFullPath($env:OMD_GNUSTEP_USER_THEME_ROOT)) | Out-Null
  }

  if (-not [string]::IsNullOrWhiteSpace($env:GNUSTEP_USER_ROOT)) {
    $candidateRoots.Add([System.IO.Path]::GetFullPath((Join-Path $env:GNUSTEP_USER_ROOT "Library\Themes"))) | Out-Null
  }

  if (-not [string]::IsNullOrWhiteSpace($env:USERNAME)) {
    $candidateRoots.Add([System.IO.Path]::GetFullPath((Join-Path $MsysRoot ("home\" + $env:USERNAME + "\GNUstep\Library\Themes")))) | Out-Null
  }

  if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    $candidateRoots.Add([System.IO.Path]::GetFullPath((Join-Path $env:USERPROFILE "GNUstep\Library\Themes"))) | Out-Null
  }

  $msysHomeRoot = Join-Path $MsysRoot "home"
  if (Test-Path $msysHomeRoot) {
    foreach ($homeDir in @(Get-ChildItem -Path $msysHomeRoot -Directory -ErrorAction SilentlyContinue)) {
      $candidateRoots.Add([System.IO.Path]::GetFullPath((Join-Path $homeDir.FullName "GNUstep\Library\Themes"))) | Out-Null
    }
  }

  foreach ($candidateRoot in @($candidateRoots | Select-Object -Unique)) {
    if (-not (Test-Path $candidateRoot)) {
      continue
    }

    $hasAllThemes = $true
    foreach ($themeName in $ThemeNames) {
      if (-not (Test-Path (Join-Path $candidateRoot ($themeName + ".theme")))) {
        $hasAllThemes = $false
        break
      }
    }

    if ($hasAllThemes) {
      return $candidateRoot
    }
  }

  foreach ($candidateRoot in @($candidateRoots | Select-Object -Unique)) {
    if (Test-Path $candidateRoot) {
      return $candidateRoot
    }
  }

  if ($candidateRoots.Count -gt 0) {
    return $candidateRoots[0]
  }

  throw "Unable to resolve the GNUstep user theme root."
}

function New-OmdThemeCompatDirectory {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ThemeRepository,
    [Parameter(Mandatory = $true)]
    [string]$MsysRoot
  )

  $compatCandidates = @(
    (Join-Path $MsysRoot "clang64\lib\libgcc_s.a"),
    (Join-Path $MsysRoot "mingw64\lib\libgcc_s.a")
  )
  $sourceLib = $compatCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $sourceLib) {
    return $null
  }

  $compatDir = Join-Path $ThemeRepository "tmp\clang64-linker-compat"
  New-Item -ItemType Directory -Force -Path $compatDir | Out-Null
  Copy-Item $sourceLib (Join-Path $compatDir "libgcc_s.a") -Force
  return $compatDir
}

$resolvedEnvExe = Join-Path $resolvedMsysRoot "usr\bin\env.exe"
if (Test-Path $resolvedEnvExe) {
  $script:OmdMsysDrivePrefix = Resolve-OmdMsysDrivePrefix -EnvExe $resolvedEnvExe
} else {
  $script:OmdMsysDrivePrefix = ""
}

$themeWorkspaceCandidates = [System.Collections.Generic.List[string]]::new()
if (-not [string]::IsNullOrWhiteSpace($ThemeWorkspace)) {
  $themeWorkspaceCandidates.Add((Resolve-OmdPathCandidate -BasePath $repoRoot -Candidate $ThemeWorkspace)) | Out-Null
}
$themeWorkspaceCandidates.Add([System.IO.Path]::GetFullPath((Join-Path $repoRoot ".omd-theme-inputs"))) | Out-Null
$themeWorkspaceCandidates.Add([System.IO.Path]::GetFullPath((Join-Path $repoRoot ".."))) | Out-Null

$themeSpecs = @(
  @{
    Name = "Win11Theme"
    RepoName = "plugins-themes-win11theme"
    RepoOverride = $env:OMD_WIN11_THEME_REPO
  },
  @{
    Name = "WinUITheme"
    RepoName = "plugins-themes-winuitheme"
    RepoOverride = $env:OMD_WINUI_THEME_REPO
  }
)

$themeResults = [System.Collections.Generic.List[object]]::new()

foreach ($themeSpec in $themeSpecs) {
  $repoCandidates = [System.Collections.Generic.List[string]]::new()
  $themeRepoOverride = [string]$themeSpec["RepoOverride"]
  $themeRepoName = [string]$themeSpec["RepoName"]
  $themeName = [string]$themeSpec["Name"]
  $manifestThemeInput = Get-OmdManifestThemeInput -ThemeName $themeName
  $themeRequired = $true
  if ($manifestThemeInput -and ($manifestThemeInput.PSObject.Properties.Name -contains "required")) {
    $themeRequired = [bool]$manifestThemeInput.required
  }

  if (-not [string]::IsNullOrWhiteSpace($themeRepoOverride)) {
    $repoCandidates.Add([System.IO.Path]::GetFullPath($themeRepoOverride)) | Out-Null
  }

  foreach ($workspacePath in $themeWorkspaceCandidates) {
    $repoCandidates.Add([System.IO.Path]::GetFullPath((Join-Path $workspacePath $themeRepoName))) | Out-Null
  }

  Ensure-OmdThemeRepoFromManifest -ThemeName $themeName -RepoName $themeRepoName -Required:$themeRequired | Out-Null

  $resolvedThemeRepo = $null
  try {
    $resolvedThemeRepo = Resolve-OmdThemeRepo -RepoName $themeRepoName -Candidates @($repoCandidates | Select-Object -Unique)
  } catch {
    if ($themeRequired) {
      throw
    }
    Write-Warning "Skipping optional theme repository '$themeRepoName'. $($_.Exception.Message)"
    continue
  }

  Sync-OmdThemeImageCompatibilityResources -ThemeRepository $resolvedThemeRepo

  $extraEnvironment = @{}
  $themeBuildFlags = "-DHAVE_MODE_T=1"
  $compatScriptCandidates = @(
    (Join-Path $resolvedThemeRepo "Scripts\Prepare-GNUstepCompat.ps1"),
    (Join-Path $resolvedThemeRepo "scripts\Prepare-GNUstepCompat.ps1")
  )
  $compatScript = $compatScriptCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
  $compatDir = $null
  if ($compatScript) {
    $compatDir = New-OmdThemeCompatDirectory -ThemeRepository $resolvedThemeRepo -MsysRoot $resolvedMsysRoot
    if (-not $compatDir) {
      Write-Verbose ("Skipping stale GNUstep compatibility shim for {0}; no libgcc_s.a was found in the active MSYS2 toolchain." -f $themeName)
    } else {
      $compatDir = & $compatScript
      if ($LASTEXITCODE -ne 0) {
        throw "Theme compatibility setup failed for $resolvedThemeRepo"
      }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$compatDir)) {
      $extraEnvironment["LIBRARY_PATH"] = ((Convert-ToMsysPath -WindowsPath ([string]$compatDir)) + ":/clang64/lib")
    }
  }

  Invoke-OmdMsysCommand `
    -MsysRoot $resolvedMsysRoot `
    -WorkingDirectory $resolvedThemeRepo `
    -InnerCommand ("make install GNUSTEP_INSTALLATION_DOMAIN=USER " +
      ("ADDITIONAL_CPPFLAGS=`"{0}`" " -f $themeBuildFlags) +
      ("ADDITIONAL_OBJCFLAGS=`"{0}`"" -f $themeBuildFlags)) `
    -Environment $extraEnvironment

  $themeResults.Add([pscustomobject]@{
    name = $themeName
    repo = $resolvedThemeRepo
  }) | Out-Null
}

$resolvedUserThemeRoot = Resolve-OmdUserThemeRoot -MsysRoot $resolvedMsysRoot -ThemeNames @($themeResults | ForEach-Object { [string]$_.name })
$resolvedThemeResults = foreach ($themeResult in $themeResults) {
  $installedBundle = Join-Path $resolvedUserThemeRoot ($themeResult.name + ".theme")
  if (-not (Test-Path $installedBundle)) {
    throw "Installed theme bundle not found after install: $installedBundle"
  }

  [pscustomobject]@{
    name = $themeResult.name
    repo = $themeResult.repo
    installedBundle = $installedBundle
  }
}

[pscustomobject]@{
  msysRoot = $resolvedMsysRoot
  userThemeRoot = $resolvedUserThemeRoot
  themes = @($resolvedThemeResults)
}
