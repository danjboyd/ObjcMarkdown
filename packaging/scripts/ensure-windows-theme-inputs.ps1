[CmdletBinding()]
param(
  [string]$ThemeWorkspace,
  [string]$MsysRoot = $(if (-not [string]::IsNullOrWhiteSpace($env:MSYS2_LOCATION)) { $env:MSYS2_LOCATION } else { "C:\msys64" })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$resolvedMsysRoot = [System.IO.Path]::GetFullPath($MsysRoot)

function Convert-ToMsysPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$WindowsPath
  )

  $fullPath = [System.IO.Path]::GetFullPath($WindowsPath)
  $normalized = $fullPath -replace "\\", "/"
  if ($normalized -match "^([A-Za-z]):(/.*)?$") {
    $drive = $Matches[1].ToLowerInvariant()
    $rest = if ($Matches[2]) { $Matches[2] } else { "" }
    return "/$drive$rest"
  }

  throw "Unable to convert Windows path to MSYS2 path: $WindowsPath"
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

  $workingDirectoryMsys = Convert-ToMsysPath -WindowsPath $WorkingDirectory
  $bootstrapLines = @(
    "source /etc/profile",
    "source /clang64/share/GNUstep/Makefiles/GNUstep.sh",
    "export PATH=/usr/bin:/clang64/bin:/mingw64/bin:`$PATH"
  )

  foreach ($entry in $Environment.GetEnumerator()) {
    $escapedValue = ([string]$entry.Value).Replace("'", "'\''")
    $bootstrapLines += ("export {0}='{1}'" -f $entry.Key, $escapedValue)
  }

  $bootstrapLines += ("cd '{0}'" -f $workingDirectoryMsys)
  $bootstrapLines += $InnerCommand
  $bootstrap = ($bootstrapLines -join "; ")

  & $envExe 'MSYSTEM=CLANG64' 'CHERE_INVOKING=1' '/usr/bin/bash' '-lc' $bootstrap 2>&1 | ForEach-Object {
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
    [string[]]$Candidates,
    [bool]$Required = $true
  )

  foreach ($candidate in $Candidates) {
    if ([string]::IsNullOrWhiteSpace($candidate)) {
      continue
    }

    if ((Test-Path $candidate) -and (Test-Path (Join-Path $candidate "GNUmakefile"))) {
      return [System.IO.Path]::GetFullPath($candidate)
    }
  }

  if ($Required) {
    throw "Required theme repository '$RepoName' was not found. Checked: $($Candidates -join ', ')"
  }

  return $null
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
    Required = $false
  },
  @{
    Name = "WinUITheme"
    RepoName = "plugins-themes-winuitheme"
    RepoOverride = $env:OMD_WINUI_THEME_REPO
    Required = $true
  }
)

$themeResults = [System.Collections.Generic.List[object]]::new()

foreach ($themeSpec in $themeSpecs) {
  $repoCandidates = [System.Collections.Generic.List[string]]::new()
  $themeRepoOverride = [string]$themeSpec["RepoOverride"]
  $themeRepoName = [string]$themeSpec["RepoName"]
  $themeName = [string]$themeSpec["Name"]
  $themeRequired = [bool]$themeSpec["Required"]

  if (-not [string]::IsNullOrWhiteSpace($themeRepoOverride)) {
    $repoCandidates.Add([System.IO.Path]::GetFullPath($themeRepoOverride)) | Out-Null
  }

  foreach ($workspacePath in $themeWorkspaceCandidates) {
    $repoCandidates.Add([System.IO.Path]::GetFullPath((Join-Path $workspacePath $themeRepoName))) | Out-Null
  }

  $resolvedThemeRepo = Resolve-OmdThemeRepo -RepoName $themeRepoName -Candidates @($repoCandidates | Select-Object -Unique) -Required:$themeRequired
  if (-not $resolvedThemeRepo) {
    Write-Host ("Skipping optional theme input '{0}' because its repository is not present." -f $themeName)
    continue
  }

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
