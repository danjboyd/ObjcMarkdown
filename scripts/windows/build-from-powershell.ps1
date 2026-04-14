param(
  [ValidateSet("build", "test", "run", "stage", "command")]
  [string]$Task = "build",
  [string]$Command,
  [string]$RunTarget = "TableRenderDemo.md",
  [string]$StageDir = "dist/packaging/windows/stage",
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
  [string]$MsysRoot = $(if (-not [string]::IsNullOrWhiteSpace($env:MSYS2_LOCATION)) { $env:MSYS2_LOCATION } else { "C:\msys64" })
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
    return "/$drive$rest"
  }

  throw "Unable to convert Windows path to MSYS2 path: $WindowsPath"
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

$resolvedRepoRoot = (Resolve-Path $RepoRoot).Path
$RepoRootMsys = Convert-ToMsysPath -WindowsPath $resolvedRepoRoot
$msysCommand = Get-MsysCommand -SelectedTask $Task -CustomCommand $Command -SelectedRunTarget $RunTarget -SelectedStageDir $StageDir
$bootstrap = "source /etc/profile; source /clang64/share/GNUstep/Makefiles/GNUstep.sh; cd '$RepoRootMsys'; $msysCommand"

Write-Host "Task: $Task"
Write-Host "Repo: $resolvedRepoRoot"
Write-Host "MSYS2: $resolvedMsysRoot"

& $envExe 'MSYSTEM=CLANG64' 'CHERE_INVOKING=1' '/usr/bin/bash' '-lc' $bootstrap
exit $LASTEXITCODE
