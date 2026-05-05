param(
  [ValidateSet("build", "test", "run", "stage", "command")]
  [string]$Task = "build",
  [string]$Command,
  [string]$RunTarget = "TableRenderDemo.md",
  [string]$StageDir = "dist/packaging/windows/stage",
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
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

function Convert-ToMsysPath {
  param([Parameter(Mandatory = $true)][string]$WindowsPath)

  $fullPath = [System.IO.Path]::GetFullPath($WindowsPath)
  $normalized = $fullPath -replace "\\", "/"
  if ($normalized -match "^([A-Za-z]):(/.*)?$") {
    $drive = $Matches[1].ToLowerInvariant()
    $rest = if ($Matches[2]) { $Matches[2] } else { "" }
    return "$script:MsysDrivePrefix/$drive$rest"
  }

  throw "Unable to convert Windows path to MSYS2 path: $WindowsPath"
}

function Resolve-MsysDrivePrefix {
  param([Parameter(Mandatory = $true)][string]$EnvExe)

  $prefix = Invoke-MsysEnv -EnvExe $EnvExe -Arguments @(
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

function Invoke-MsysEnv {
  param(
    [Parameter(Mandatory = $true)][string]$EnvExe,
    [Parameter(Mandatory = $true)][string[]]$Arguments
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

function Get-MsysCommand {
  param(
    [Parameter(Mandatory = $true)][string]$SelectedTask,
    [string]$CustomCommand,
    [string]$SelectedRunTarget,
    [string]$SelectedStageDir
  )

  switch ($SelectedTask) {
    "build" { return "make" }
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
        $runTargetPath = Convert-ToMsysPath -WindowsPath ((Resolve-Path $runTargetPath).Path)
      }
      $escapedTarget = $runTargetPath.Replace("'", "'\''")
      return "make run '$escapedTarget'"
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

$resolvedMsysRoot = [System.IO.Path]::GetFullPath($MsysRoot)

$envExe = Join-Path $resolvedMsysRoot "usr\bin\env.exe"
if (-not (Test-Path $envExe)) {
  throw "MSYS2 env.exe not found at $envExe"
}

$gnuStepSh = Join-Path $resolvedMsysRoot "clang64\share\GNUstep\Makefiles\GNUstep.sh"
if (-not (Test-Path $gnuStepSh)) {
  throw "GNUstep.sh not found at $gnuStepSh"
}

$script:MsysDrivePrefix = Resolve-MsysDrivePrefix -EnvExe $envExe
$resolvedRepoRoot = (Resolve-Path $RepoRoot).Path
$RepoRootMsys = Convert-ToMsysPath -WindowsPath $resolvedRepoRoot
$msysCommand = Get-MsysCommand -SelectedTask $Task -CustomCommand $Command -SelectedRunTarget $RunTarget -SelectedStageDir $StageDir
$bootstrap = "if [ -f /etc/profile ]; then source /etc/profile; fi; source /clang64/share/GNUstep/Makefiles/GNUstep.sh; cd '$RepoRootMsys'; $msysCommand"

Write-Host "Task: $Task"
Write-Host "Repo: $resolvedRepoRoot"
Write-Host "MSYS2: $resolvedMsysRoot"

Invoke-MsysEnv -EnvExe $envExe -Arguments @('MSYSTEM=CLANG64', 'CHERE_INVOKING=1', '/usr/bin/bash', '-lc', $bootstrap)
exit $LASTEXITCODE
