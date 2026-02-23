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
Start-Process msiexec.exe -Wait -ArgumentList "/i", $MsiPath, "/qn", "/norestart", "/l*v", (Join-Path $LogDir "install.log")
if ($LASTEXITCODE -ne 0) {
  throw "MSI install failed with exit code $LASTEXITCODE"
}

$cmdPath = Join-Path $InstallDir "MarkdownViewer.cmd"
if (-not (Test-Path $cmdPath)) {
  throw "Expected app launcher not found: $cmdPath"
}

$runtimeBin = "C:\clang64\bin"
if (-not (Test-Path $runtimeBin)) {
  throw "Expected runtime not found: $runtimeBin"
}

if ($RunSmoke) {
  Write-Host "Running smoke test"
  $smokeFile = Join-Path $env:TEMP "omd-smoke.md"
  Set-Content -Path $smokeFile -Value "# Smoke Test`n`nOK"
  $proc = Start-Process $cmdPath -ArgumentList $smokeFile -PassThru
  Start-Sleep -Seconds 5
  if (-not $proc.HasExited) {
    $proc | Stop-Process -Force
  }
}

Write-Host "Uninstalling MSI: $MsiPath"
Start-Process msiexec.exe -Wait -ArgumentList "/x", $MsiPath, "/qn", "/norestart", "/l*v", (Join-Path $LogDir "uninstall.log")
if ($LASTEXITCODE -ne 0) {
  throw "MSI uninstall failed with exit code $LASTEXITCODE"
}
