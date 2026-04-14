[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$MsiPath,
  [string]$GuestHost,
  [string]$StateFile = "dist/oci/last-validation-vm.json",
  [string]$ValidationScriptPath = "scripts/windows/validate-msi.ps1",
  [string]$IdentityFile,
  [string]$JumpHost,
  [string]$SshUser,
  [string]$LocalLogDir,
  [int]$SshReadyTimeoutSeconds = 900,
  [int]$PollIntervalSeconds = 10,
  [switch]$RunSmoke
)

. (Join-Path $PSScriptRoot "oci-common.ps1")

$resolvedMsiPath = Resolve-OmdPath -Path $MsiPath
$resolvedValidationScriptPath = Resolve-OmdPath -Path $ValidationScriptPath

$state = $null
if ((-not $GuestHost) -or (-not $SshUser) -or (-not $IdentityFile) -or (-not $JumpHost)) {
  $resolvedStateFile = Resolve-OmdPath -Path $StateFile -AllowMissing
  if (Test-Path $resolvedStateFile) {
    $state = Read-OmdStateFile -StateFile $resolvedStateFile
  }
}

if (-not $GuestHost) {
  $GuestHost = $state.publicIp
}
if (-not $SshUser) {
  $SshUser = if ($state.sshUser) { $state.sshUser } else { "otvmbootstrap" }
}
if (-not $IdentityFile) {
  $IdentityFile = if ($state.identityFile) {
    $state.identityFile
  } elseif ($state.sshPublicKeyPath) {
    Resolve-OmdIdentityFilePath -SshPublicKeyPath $state.sshPublicKeyPath
  }
}
if (-not $JumpHost -and $state.jumpHost) {
  $JumpHost = $state.jumpHost
}

if (-not $GuestHost) {
  throw "Guest host is required. Pass -GuestHost explicitly or provide a state file with publicIp."
}

if (-not $LocalLogDir) {
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $LocalLogDir = Join-Path "dist/oci-logs" $timestamp
}

$resolvedLocalLogDir = Resolve-OmdPath -Path $LocalLogDir -AllowMissing
New-Item -ItemType Directory -Force -Path $resolvedLocalLogDir | Out-Null

Write-Host "Waiting for SSH on $GuestHost"
Wait-OmdSshReady -TargetHost $GuestHost -User $SshUser -IdentityFile $IdentityFile -JumpHost $JumpHost -TimeoutSeconds $SshReadyTimeoutSeconds -PollIntervalSeconds $PollIntervalSeconds

$remoteMsiName = "ObjcMarkdown.msi"
$remoteValidationName = "validate-msi.ps1"
$remoteUserPrefix = "${SshUser}@${GuestHost}:"

Write-Host "Copying MSI to $GuestHost"
Invoke-OmdScpCopy -Sources @($resolvedMsiPath) -Destination ($remoteUserPrefix + $remoteMsiName) -IdentityFile $IdentityFile -JumpHost $JumpHost

Write-Host "Copying validation script to $GuestHost"
Invoke-OmdScpCopy -Sources @($resolvedValidationScriptPath) -Destination ($remoteUserPrefix + $remoteValidationName) -IdentityFile $IdentityFile -JumpHost $JumpHost

$remoteHome = "C:\Users\$SshUser"
$remoteCommand = "powershell -NoProfile -ExecutionPolicy Bypass -File $remoteHome\$remoteValidationName -MsiPath $remoteHome\$remoteMsiName"
if ($RunSmoke) {
  $remoteCommand += " -RunSmoke"
}

$validationError = $null
try {
  Write-Host "Running remote MSI validation on $GuestHost"
  Invoke-OmdSshCommand -TargetHost $GuestHost -User $SshUser -Command $remoteCommand -IdentityFile $IdentityFile -JumpHost $JumpHost
} catch {
  $validationError = $_
}

$remoteLogs = @(
  "C:/temp/omd-logs/install.log",
  "C:/temp/omd-logs/uninstall.log"
)

foreach ($remoteLog in $remoteLogs) {
  try {
    Invoke-OmdScpCopy -Sources @("${SshUser}@${GuestHost}:$remoteLog") -Destination $resolvedLocalLogDir -IdentityFile $IdentityFile -JumpHost $JumpHost
  } catch {
    Write-Warning "Failed to copy remote log $remoteLog"
  }
}

if ($validationError) {
  throw $validationError
}

[pscustomobject]@{
  guestHost    = $GuestHost
  sshUser      = $SshUser
  localLogDir  = $resolvedLocalLogDir
  msiPath      = $resolvedMsiPath
  validatedAt  = (Get-Date).ToString("o")
  remoteMsi    = "$remoteHome\$remoteMsiName"
}
