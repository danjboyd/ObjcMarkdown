param(
  [ValidateSet("build", "test", "run", "stage", "command")]
  [string]$Task = "build",
  [string]$Command,
  [string]$RunTarget = "TableRenderDemo.md",
  [string]$StageDir = "dist/packaging/windows/stage",
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
  [string]$MsysRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Convert-ToMsysPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$WindowsPath,
    [string]$MsysShellRoot = ""
  )

  $fullPath = [System.IO.Path]::GetFullPath($WindowsPath)
  if (-not [string]::IsNullOrWhiteSpace($MsysShellRoot)) {
    $cygpathExe = Join-Path $MsysShellRoot "usr\bin\cygpath.exe"
    if (Test-Path $cygpathExe) {
      $converted = & $cygpathExe '-u' $fullPath
      if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($converted)) {
        return [string]$converted
      }
    }
  }

  $normalized = $fullPath -replace "\\", "/"
  if ($normalized -match "^([A-Za-z]):(/.*)?$") {
    $drive = $Matches[1].ToLowerInvariant()
    $rest = if ($Matches[2]) { $Matches[2] } else { "" }
    return "/$drive$rest"
  }

  throw "Unable to convert Windows path to MSYS2 path: $WindowsPath"
}

function Resolve-MsysShellRoot {
  param([Parameter(Mandatory = $true)][string]$MsysRoot)

  $candidates = [System.Collections.Generic.List[string]]::new()
  if (-not [string]::IsNullOrWhiteSpace($env:MSYS2_LOCATION)) {
    $candidates.Add($env:MSYS2_LOCATION) | Out-Null
  }
  $candidates.Add($MsysRoot) | Out-Null

  foreach ($candidate in @($candidates | Select-Object -Unique)) {
    if ([string]::IsNullOrWhiteSpace($candidate)) {
      continue
    }
    $resolved = [System.IO.Path]::GetFullPath($candidate)
    if (Test-Path (Join-Path $resolved "usr\bin\env.exe")) {
      return $resolved
    }
  }

  throw "Unable to resolve an MSYS2 shell root. Checked: $($candidates -join ', ')"
}

function Resolve-MsysRoot {
  param([string]$RequestedRoot)

  $candidates = [System.Collections.Generic.List[string]]::new()
  if (-not [string]::IsNullOrWhiteSpace($RequestedRoot)) {
    $candidates.Add($RequestedRoot) | Out-Null
  }
  if (-not [string]::IsNullOrWhiteSpace($env:MSYS2_LOCATION)) {
    $candidates.Add($env:MSYS2_LOCATION) | Out-Null
  }
  if (-not [string]::IsNullOrWhiteSpace($env:GP_GNUSTEP_CLI_ROOT)) {
    $candidates.Add($env:GP_GNUSTEP_CLI_ROOT) | Out-Null
    $candidates.Add((Join-Path $env:GP_GNUSTEP_CLI_ROOT "msys64")) | Out-Null
  }
  $candidates.Add("C:\msys64") | Out-Null

  foreach ($candidate in @($candidates | Select-Object -Unique)) {
    if ([string]::IsNullOrWhiteSpace($candidate)) {
      continue
    }
    $resolved = [System.IO.Path]::GetFullPath($candidate)
    if ((Test-Path (Join-Path $resolved "usr\bin\env.exe")) -and
        (Test-Path (Join-Path $resolved "clang64\share\GNUstep\Makefiles\GNUstep.sh"))) {
      return $resolved
    }
  }

  throw "Unable to resolve MSYS2 clang64 root. Checked: $($candidates -join ', ')"
}

function Get-MsysCommand {
  param(
    [Parameter(Mandatory = $true)][string]$SelectedTask,
    [string]$CustomCommand,
    [string]$SelectedRunTarget,
    [string]$SelectedStageDir
  )

  switch ($SelectedTask) {
    "build" { return "make GNUSTEP_MAKEFILES=/clang64/share/GNUstep/Makefiles" }
    "test" {
      return @"
mkdir -p ~/GNUstep/Defaults/.lck
export PATH="$RepoRootMsys/ObjcMarkdown/obj:$RepoRootMsys/third_party/libs-OpenSave/Source/obj:$RepoRootMsys/third_party/TextViewVimKitBuild/obj:`$PATH"
xctest ObjcMarkdownTests/ObjcMarkdownTests.bundle
"@.Trim()
    }
    "run" {
      $runTargetPath = $SelectedRunTarget
      if (-not [string]::IsNullOrWhiteSpace($runTargetPath) -and (Test-Path $runTargetPath)) {
        $runTargetPath = Convert-ToMsysPath -WindowsPath ((Resolve-Path $runTargetPath).Path) -MsysShellRoot $resolvedMsysShellRoot
      }
      $escapedTarget = $runTargetPath.Replace("'", "'\''")
      return "make GNUSTEP_MAKEFILES=/clang64/share/GNUstep/Makefiles run '$escapedTarget'"
    }
    "stage" {
      $escapedStageDir = $SelectedStageDir.Replace("'", "'\''")
      return "./packaging/scripts/stage-windows-runtime.sh '$escapedStageDir'"
    }
    "command" {
      if ([string]::IsNullOrWhiteSpace($CustomCommand)) {
        throw "-Command is required when -Task command is used."
      }
      return $CustomCommand
    }
  }

  throw "Unhandled task: $SelectedTask"
}

function Sync-ManagedCmarkPackage {
  param(
    [Parameter(Mandatory = $true)][string]$ManagedRoot,
    [Parameter(Mandatory = $true)][string]$ShellRoot
  )

  $managedFullRoot = [System.IO.Path]::GetFullPath($ManagedRoot)
  $shellFullRoot = [System.IO.Path]::GetFullPath($ShellRoot)
  if ($managedFullRoot -eq $shellFullRoot) {
    return
  }

  $managedClangRoot = Join-Path $managedFullRoot "clang64"
  $shellClangRoot = Join-Path $shellFullRoot "clang64"
  $managedHasHeaders =
    (Test-Path (Join-Path $managedClangRoot "include\cmark.h")) -or
    (Test-Path (Join-Path $managedClangRoot "include\cmark\cmark.h"))
  if ($managedHasHeaders) {
    return
  }

  $shellHasHeaders =
    (Test-Path (Join-Path $shellClangRoot "include\cmark.h")) -or
    (Test-Path (Join-Path $shellClangRoot "include\cmark\cmark.h"))
  if (-not $shellHasHeaders) {
    return
  }

  Write-Host "Mirroring cmark package from bootstrap shell into managed GNUstep root"

  $copySpecs = @(
    @{ Source = (Join-Path $shellClangRoot "include\cmark.h"); Destination = (Join-Path $managedClangRoot "include"); Wildcard = $false },
    @{ Source = (Join-Path $shellClangRoot "include\cmark"); Destination = (Join-Path $managedClangRoot "include\cmark"); Wildcard = $false },
    @{ Source = (Join-Path $shellClangRoot "include\*cmark*.h"); Destination = (Join-Path $managedClangRoot "include"); Wildcard = $true },
    @{ Source = (Join-Path $shellClangRoot "lib\libcmark*"); Destination = (Join-Path $managedClangRoot "lib"); Wildcard = $true },
    @{ Source = (Join-Path $shellClangRoot "bin\libcmark*.dll"); Destination = (Join-Path $managedClangRoot "bin"); Wildcard = $true },
    @{ Source = (Join-Path $shellClangRoot "lib\pkgconfig\cmark.pc"); Destination = (Join-Path $managedClangRoot "lib\pkgconfig"); Wildcard = $false },
    @{ Source = (Join-Path $shellClangRoot "lib\pkgconfig\libcmark.pc"); Destination = (Join-Path $managedClangRoot "lib\pkgconfig"); Wildcard = $false }
  )

  foreach ($spec in $copySpecs) {
    New-Item -ItemType Directory -Force -Path $spec.Destination | Out-Null
    if ($spec.Wildcard) {
      $items = @(Get-ChildItem -Path $spec.Source -Force -ErrorAction SilentlyContinue)
      foreach ($item in $items) {
        if ($item.PSIsContainer) {
          Copy-Item -Path $item.FullName -Destination (Join-Path $spec.Destination $item.Name) -Recurse -Force
        } else {
          Copy-Item -Path $item.FullName -Destination $spec.Destination -Force
        }
      }
      continue
    }

    if (Test-Path $spec.Source) {
      Copy-Item -Path $spec.Source -Destination $spec.Destination -Recurse -Force
    }
  }
}

$resolvedMsysRoot = Resolve-MsysRoot -RequestedRoot $MsysRoot
$resolvedMsysShellRoot = Resolve-MsysShellRoot -MsysRoot $resolvedMsysRoot
Sync-ManagedCmarkPackage -ManagedRoot $resolvedMsysRoot -ShellRoot $resolvedMsysShellRoot

$envExe = Join-Path $resolvedMsysShellRoot "usr\bin\env.exe"
if (-not (Test-Path $envExe)) {
  throw "MSYS2 env.exe not found at $envExe"
}

$gnuStepSh = Join-Path $resolvedMsysRoot "clang64\share\GNUstep\Makefiles\GNUstep.sh"
if (-not (Test-Path $gnuStepSh)) {
  throw "GNUstep.sh not found at $gnuStepSh"
}

$resolvedRepoRoot = (Resolve-Path $RepoRoot).Path
$RepoRootMsys = Convert-ToMsysPath -WindowsPath $resolvedRepoRoot -MsysShellRoot $resolvedMsysShellRoot
$clangPrefixMsys = Convert-ToMsysPath -WindowsPath (Join-Path $resolvedMsysRoot "clang64") -MsysShellRoot $resolvedMsysShellRoot
$toolsBinMsys = Convert-ToMsysPath -WindowsPath (Join-Path $resolvedMsysRoot "usr\bin") -MsysShellRoot $resolvedMsysShellRoot
$msysCommand = Get-MsysCommand -SelectedTask $Task -CustomCommand $Command -SelectedRunTarget $RunTarget -SelectedStageDir $StageDir
$bootstrap = "if [ -f /etc/profile ]; then source /etc/profile; fi; export GNUSTEP_MAKEFILES='$clangPrefixMsys/share/GNUstep/Makefiles'; source `$GNUSTEP_MAKEFILES/GNUstep.sh; export GNUSTEP_MAKEFILES='$clangPrefixMsys/share/GNUstep/Makefiles'; export CC='$clangPrefixMsys/bin/clang'; export OBJC_CC='$clangPrefixMsys/bin/clang'; export CXX='$clangPrefixMsys/bin/clang++'; export OBJCXX='$clangPrefixMsys/bin/clang++'; export PATH='$toolsBinMsys':/usr/bin:'$clangPrefixMsys/bin':`$PATH; export OMD_MSYS_CLANG_PREFIX='$clangPrefixMsys'; cd '$RepoRootMsys'; $msysCommand"

Write-Host "Task: $Task"
Write-Host "Repo: $resolvedRepoRoot"
Write-Host "MSYS2: $resolvedMsysRoot"
Write-Host "MSYS2 Shell: $resolvedMsysShellRoot"

& $envExe 'MSYSTEM=CLANG64' 'CHERE_INVOKING=1' '/usr/bin/bash' '-lc' $bootstrap
exit $LASTEXITCODE
