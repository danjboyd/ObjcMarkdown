param(
  [Parameter(Mandatory=$true)]
  [string]$MsiPath,
  [string]$InstallDir = "C:\Program Files\ObjcMarkdown",
  [string]$LogDir = "C:\temp\omd-logs",
  [switch]$RunSmoke
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $MsiPath)) {
  throw "MSI not found at $MsiPath"
}

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

Write-Host "Installing MSI: $MsiPath"
$installProcess = Start-Process msiexec.exe -Wait -PassThru -ArgumentList "/i", $MsiPath, "/qn", "/norestart", "/l*v", (Join-Path $LogDir "install.log")
if ($installProcess.ExitCode -ne 0) {
  throw "MSI install failed with exit code $($installProcess.ExitCode)"
}

if (-not (Test-Path $InstallDir)) {
  $fallbackInstallDir = "C:\Program Files (x86)\ObjcMarkdown"
  if (Test-Path $fallbackInstallDir) {
    $InstallDir = $fallbackInstallDir
  }
}

$launcherPath = Join-Path $InstallDir "MarkdownViewer.exe"
if (-not (Test-Path $launcherPath)) {
  throw "Expected app launcher not found: $launcherPath"
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
  Set-Content -Path $smokeFile -Value "# Smoke Test`n`nOK"
  $proc = Start-Process $launcherPath -ArgumentList $smokeFile -PassThru
  Start-Sleep -Seconds 5
  if (-not $proc.HasExited) {
    $proc | Stop-Process -Force
  }
}

Write-Host "Uninstalling MSI: $MsiPath"
$uninstallProcess = Start-Process msiexec.exe -Wait -PassThru -ArgumentList "/x", $MsiPath, "/qn", "/norestart", "/l*v", (Join-Path $LogDir "uninstall.log")
if ($uninstallProcess.ExitCode -ne 0) {
  throw "MSI uninstall failed with exit code $($uninstallProcess.ExitCode)"
}
