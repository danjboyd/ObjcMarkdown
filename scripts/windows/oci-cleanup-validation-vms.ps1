[CmdletBinding()]
param(
  [string]$CompartmentId,
  [string]$StateFile = "dist/oci/last-validation-vm.json",
  [string]$DisplayNamePrefix = "objcmarkdown-msi-validation-",
  [double]$OlderThanHours = 0,
  [switch]$DryRun
)

. (Join-Path $PSScriptRoot "oci-common.ps1")

$resolvedStateFile = Resolve-OmdPath -Path $StateFile -AllowMissing
$state = $null
if (Test-Path $resolvedStateFile) {
  $state = Read-OmdStateFile -StateFile $resolvedStateFile
}

if (-not $CompartmentId) {
  if ($state -and $state.PSObject.Properties["compartmentId"]) {
    $CompartmentId = [string]$state.compartmentId
  } else {
    $CompartmentId = Resolve-OciCompartmentId -SubnetId $script:OmdOciDefaults.SubnetId
  }
}

$listResult = Invoke-OciJson -Arguments @(
  "compute", "instance", "list",
  "--compartment-id", $CompartmentId,
  "--all"
)

$matched = [System.Collections.Generic.List[psobject]]::new()
$stateInstanceId = if ($state) { [string]$state.instanceId } else { $null }
$cutoff = if ($OlderThanHours -gt 0) { (Get-Date).AddHours(-1 * $OlderThanHours) } else { $null }

foreach ($instance in @($listResult.data)) {
  if (-not (Test-OmdValidationVmMatch -Instance $instance -DisplayNamePrefix $DisplayNamePrefix)) {
    continue
  }

  $instanceId = [string](Get-OmdPropertyValue -InputObject $instance -Names @("id"))
  $displayName = [string](Get-OmdPropertyValue -InputObject $instance -Names @("display-name", "displayName"))
  $lifecycleState = [string](Get-OmdPropertyValue -InputObject $instance -Names @("lifecycle-state", "lifecycleState"))
  if ($lifecycleState -in @("TERMINATED", "TERMINATING")) {
    continue
  }

  $createdRaw = Get-OmdPropertyValue -InputObject $instance -Names @("time-created", "timeCreated")
  $createdAt = $null
  if ($createdRaw) {
    try {
      $createdAt = [datetimeoffset]::Parse([string]$createdRaw)
    } catch {
      $createdAt = $null
    }
  }

  if ($cutoff -and $createdAt) {
    if ($createdAt.LocalDateTime -gt $cutoff) {
      continue
    }
  }

  $matched.Add([pscustomobject]@{
    InstanceId = $instanceId
    DisplayName = $displayName
    LifecycleState = $lifecycleState
    TimeCreated = $createdAt
    MatchesStateFile = [bool]($stateInstanceId -and ($stateInstanceId -eq $instanceId))
  }) | Out-Null
}

if ($matched.Count -eq 0) {
  Write-Host "No live OCI validation VMs matched the cleanup filter."
  return @()
}

foreach ($item in $matched) {
  if ($DryRun) {
    Write-Host ("DRY RUN terminate {0} ({1}) [{2}]" -f $item.InstanceId, $item.DisplayName, $item.LifecycleState)
    continue
  }

  Write-Host ("Terminating validation VM {0} ({1}) [{2}]" -f $item.InstanceId, $item.DisplayName, $item.LifecycleState)
  if ($item.MatchesStateFile) {
    & (Join-Path $PSScriptRoot "oci-terminate-validation-vm.ps1") -StateFile $StateFile | Out-Null
  } else {
    & (Join-Path $PSScriptRoot "oci-terminate-validation-vm.ps1") -InstanceId $item.InstanceId | Out-Null
  }
}

return @($matched.ToArray())
