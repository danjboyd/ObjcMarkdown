[CmdletBinding()]
param(
  [string]$InstanceId,
  [string]$StateFile = "dist/oci/last-validation-vm.json",
  [switch]$PreserveBootVolume
)

. (Join-Path $PSScriptRoot "oci-common.ps1")

$state = $null
$resolvedStateFile = Resolve-OmdPath -Path $StateFile -AllowMissing
if ((-not $InstanceId) -and (Test-Path $resolvedStateFile)) {
  $state = Read-OmdStateFile -StateFile $resolvedStateFile
  $InstanceId = $state.instanceId
}

if (-not $InstanceId) {
  throw "Instance ID is required. Pass -InstanceId explicitly or provide a state file with instanceId."
}

$arguments = @(
  "compute", "instance", "terminate",
  "--instance-id", $InstanceId,
  "--force",
  "--wait-for-state", "TERMINATED"
)
if ($PreserveBootVolume) {
  $arguments += @("--preserve-boot-volume", "true")
}

Write-Host "Terminating OCI instance $InstanceId"
Invoke-OciJson -Arguments $arguments | Out-Null

if ($state) {
  Add-Member -InputObject $state -NotePropertyName terminatedAt -NotePropertyValue (Get-Date).ToString("o") -Force
  Add-Member -InputObject $state -NotePropertyName terminated -NotePropertyValue $true -Force
  Save-OmdJsonFile -InputObject $state -Path $resolvedStateFile | Out-Null
}

[pscustomobject]@{
  instanceId    = $InstanceId
  stateFile     = $(if (Test-Path $resolvedStateFile) { $resolvedStateFile } else { $null })
  terminatedAt  = (Get-Date).ToString("o")
  bootPreserved = [bool]$PreserveBootVolume
}
