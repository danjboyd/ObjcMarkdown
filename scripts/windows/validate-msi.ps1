param(
  [Parameter(Mandatory=$true)]
  [string]$MsiPath,
  [string]$InstallDir = "C:\Program Files\ObjcMarkdown",
  [string]$LogDir = "C:\temp\omd-logs",
  [switch]$RunSmoke
)

$ErrorActionPreference = "Stop"

function Get-OmdProcessesByExecutablePath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ExecutablePath
  )

  $expectedPath = [System.IO.Path]::GetFullPath($ExecutablePath)
  $processName = [System.IO.Path]::GetFileNameWithoutExtension($expectedPath)
  $matches = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()

  foreach ($process in @(Get-Process -Name $processName -ErrorAction SilentlyContinue)) {
    try {
      if ([string]::IsNullOrWhiteSpace([string]$process.Path)) {
        continue
      }

      $actualPath = [System.IO.Path]::GetFullPath([string]$process.Path)
      if ([string]::Equals($actualPath, $expectedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        $matches.Add($process) | Out-Null
      }
    } catch {
      continue
    }
  }

  return @($matches.ToArray())
}

if (-not (Test-Path $MsiPath)) {
  throw "MSI not found at $MsiPath"
}

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$installLog = Join-Path $LogDir "install.log"
$uninstallLog = Join-Path $LogDir "uninstall.log"
$installCompleted = $false
$validationError = $null
$uninstallError = $null

try {
  Write-Host "Installing MSI: $MsiPath"
  $installProcess = Start-Process msiexec.exe -Wait -PassThru -ArgumentList "/i", $MsiPath, "/qn", "/norestart", "/l*v", $installLog
  if ($installProcess.ExitCode -ne 0) {
    throw "MSI install failed with exit code $($installProcess.ExitCode)"
  }

  $installCompleted = $true

  $installCandidates = @(
    $InstallDir,
    (Join-Path $env:LOCALAPPDATA "ObjcMarkdown"),
    "C:\Program Files\ObjcMarkdown",
    "C:\Program Files (x86)\ObjcMarkdown"
  ) | Select-Object -Unique

  $resolvedInstallDir = $installCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $resolvedInstallDir) {
    throw "Expected install root not found in any of: $($installCandidates -join ', ')"
  }
  $InstallDir = $resolvedInstallDir
  Write-Host "Resolved install root: $InstallDir"

  $launcherPath = Join-Path $InstallDir "MarkdownViewer.exe"
  if (-not (Test-Path $launcherPath)) {
    throw "Expected app launcher not found: $launcherPath"
  }

  $appPath = Join-Path $InstallDir "app\MarkdownViewer.app\MarkdownViewer.exe"
  if (-not (Test-Path $appPath)) {
    throw "Expected packaged app executable not found: $appPath"
  }

  $runtimeCandidates = @(
    (Join-Path $InstallDir "clang64\\bin"),
    "C:\clang64\bin"
  )
  $runtimeBin = $runtimeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $runtimeBin) {
    throw "Expected runtime not found in any of: $($runtimeCandidates -join ', ')"
  }

  if ($RunSmoke) {
    Write-Host "Running smoke test"
    $smokeFile = Join-Path $env:TEMP "omd-smoke.md"
    $probeDeadline = (Get-Date).AddSeconds(10)
    $childProcesses = @()

    Set-Content -Path $smokeFile -Value "# Smoke Test`n`nOK"
    $proc = Start-Process $launcherPath -ArgumentList $smokeFile -PassThru -WorkingDirectory $InstallDir

    do {
      Start-Sleep -Milliseconds 500
      $proc.Refresh()
      $childProcesses = @(Get-OmdProcessesByExecutablePath -ExecutablePath $appPath)
    } while (((-not $proc.HasExited) -or $childProcesses.Count -eq 0) -and (Get-Date) -lt $probeDeadline)

    $proc.Refresh()
    if (-not $proc.HasExited) {
      try {
        $proc | Stop-Process -Force
      } catch {
      }
      throw "Smoke launcher did not exit within the probe window: $launcherPath"
    }

    if ($proc.ExitCode -ne 0) {
      throw "Smoke launcher exited with code $($proc.ExitCode): $launcherPath"
    }

    $childProcesses = @(Get-OmdProcessesByExecutablePath -ExecutablePath $appPath)
    if ($childProcesses.Count -eq 0) {
      throw "Smoke launch did not leave the packaged app running: $appPath"
    }

    foreach ($child in $childProcesses) {
      try {
        $child | Stop-Process -Force
      } catch {
      }
    }
  }
} catch {
  $validationError = $_
} finally {
  if ($installCompleted) {
    try {
      Write-Host "Uninstalling MSI: $MsiPath"
      $uninstallProcess = Start-Process msiexec.exe -Wait -PassThru -ArgumentList "/x", $MsiPath, "/qn", "/norestart", "/l*v", $uninstallLog
      if ($uninstallProcess.ExitCode -ne 0) {
        throw "MSI uninstall failed with exit code $($uninstallProcess.ExitCode)"
      }
    } catch {
      $uninstallError = $_
    }
  }
}

if ($validationError -and $uninstallError) {
  throw "Remote MSI validation failed: $($validationError.Exception.Message) Additionally, uninstall failed: $($uninstallError.Exception.Message)"
}
if ($validationError) {
  throw $validationError
}
if ($uninstallError) {
  throw $uninstallError
}
