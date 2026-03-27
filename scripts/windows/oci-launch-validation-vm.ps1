[CmdletBinding()]
param(
  [string]$DisplayName = ("objcmarkdown-msi-validation-" + (Get-Date -Format "yyyyMMdd-HHmmss")),
  [string]$CompartmentId,
  [string]$AvailabilityDomain,
  [string]$SubnetId = "ocid1.subnet.oc1.phx.aaaaaaaaimvrd2faa744cu34ucvq2vpftgcnuhe7taaqhunvszhn64fzon4a",
  [string]$ImageId = "ocid1.image.oc1.phx.aaaaaaaa6253prkupypnde7blkcsojo66njxkyquiimmkdy7foiu4ywxyiva",
  [string]$Shape = "VM.Standard.E5.Flex",
  [int]$Ocpus = 1,
  [int]$MemoryInGBs = 12,
  [string]$SshPublicKeyPath,
  [string]$IdentityFile,
  [string]$JumpHost,
  [string]$SshUser = "opc",
  [string]$StateFile = "dist/oci/last-validation-vm.json",
  [int]$PublicIpTimeoutSeconds = 900,
  [int]$SshWaitTimeoutSeconds = 900,
  [int]$PollIntervalSeconds = 10,
  [switch]$SkipSshWait
)

. (Join-Path $PSScriptRoot "oci-common.ps1")

$CompartmentId = Resolve-OciCompartmentId -CompartmentId $CompartmentId -SubnetId $SubnetId
$AvailabilityDomain = Resolve-OciAvailabilityDomain -AvailabilityDomain $AvailabilityDomain
$resolvedSshPublicKeyPath = Resolve-OmdSshPublicKeyPath -SshPublicKeyPath $SshPublicKeyPath
$resolvedIdentityFile = Resolve-OmdIdentityFilePath -IdentityFile $IdentityFile -SshPublicKeyPath $resolvedSshPublicKeyPath

$shapeConfigJson = (@{
  ocpus       = $Ocpus
  memoryInGBs = $MemoryInGBs
} | ConvertTo-Json -Compress)
$freeformTagsJson = (Get-OmdValidationVmFreeformTags -ManagedBy "oci-launch-validation-vm.ps1" | ConvertTo-Json -Compress)

Write-Host "Launching OCI validation VM $DisplayName"
Write-Host "Compartment: $CompartmentId"
Write-Host "Availability Domain: $AvailabilityDomain"
Write-Host "Image: $ImageId"
Write-Host "Shape: $Shape ($Ocpus OCPU / $MemoryInGBs GB)"

$launchResult = Invoke-OciJson -Arguments @(
  "compute", "instance", "launch",
  "--display-name", $DisplayName,
  "--compartment-id", $CompartmentId,
  "--availability-domain", $AvailabilityDomain,
  "--shape", $Shape,
  "--shape-config", $shapeConfigJson,
  "--freeform-tags", $freeformTagsJson,
  "--image-id", $ImageId,
  "--subnet-id", $SubnetId,
  "--assign-public-ip", "true",
  "--vnic-display-name", "$DisplayName-vnic",
  "--ssh-authorized-keys-file", $resolvedSshPublicKeyPath,
  "--wait-for-state", "RUNNING"
)

$instanceId = Get-OmdPropertyValue -InputObject $launchResult.data -Names @("id")
if (-not $instanceId) {
  throw "OCI launch succeeded but no instance ID was returned."
}

$publicIp = Wait-OciInstancePublicIp -InstanceId $instanceId -TimeoutSeconds $PublicIpTimeoutSeconds -PollIntervalSeconds $PollIntervalSeconds
Write-Host "Instance $instanceId has public IP $publicIp"

$resolvedStateFile = Resolve-OmdPath -Path $StateFile -AllowMissing
$state = [ordered]@{
  displayName        = $DisplayName
  instanceId         = $instanceId
  publicIp           = $publicIp
  compartmentId      = $CompartmentId
  availabilityDomain = $AvailabilityDomain
  subnetId           = $SubnetId
  imageId            = $ImageId
  shape              = $Shape
  ocpus              = $Ocpus
  memoryInGBs        = $MemoryInGBs
  sshUser            = $SshUser
  sshPublicKeyPath   = $resolvedSshPublicKeyPath
  identityFile       = $resolvedIdentityFile
  jumpHost           = $JumpHost
  freeformTags       = (Get-OmdValidationVmFreeformTags -ManagedBy "oci-launch-validation-vm.ps1")
  stateFile          = $resolvedStateFile
  launchedAt         = (Get-Date).ToString("o")
}

Save-OmdJsonFile -InputObject $state -Path $resolvedStateFile | Out-Null
Write-Host "Saved instance state to $resolvedStateFile"

if (-not $SkipSshWait) {
  if ($resolvedIdentityFile -or $JumpHost) {
    Write-Host "Waiting for SSH command readiness on $publicIp"
    Wait-OmdSshReady -TargetHost $publicIp -User $SshUser -IdentityFile $resolvedIdentityFile -JumpHost $JumpHost -TimeoutSeconds $SshWaitTimeoutSeconds -PollIntervalSeconds $PollIntervalSeconds
  } else {
    Write-Host "Waiting for SSH on $publicIp:22"
    Wait-OmdTcpPort -TargetHost $publicIp -Port 22 -TimeoutSeconds $SshWaitTimeoutSeconds -PollIntervalSeconds $PollIntervalSeconds
  }

  $state.sshReadyAt = (Get-Date).ToString("o")
  Save-OmdJsonFile -InputObject $state -Path $resolvedStateFile | Out-Null
}

[pscustomobject]$state
