[CmdletBinding()]
param(
  [string]$Version,
  [string]$MsysRoot = "C:\msys64",
  [string]$StageDir = "dist/ObjcMarkdown",
  [string]$InstallerOutDir = "dist/installer",
  [string]$MsiPath,
  [string]$StateFile = "dist/oci/last-validation-vm.json",
  [string]$LogDir,
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
  [string]$RdpSourceCidr,
  [switch]$OpenRdp,
  [switch]$RunSmoke,
  [switch]$SkipBuild,
  [switch]$SkipTest,
  [switch]$SkipStage,
  [switch]$SkipPackage,
  [switch]$KeepVm
)

. (Join-Path $PSScriptRoot "oci-common.ps1")

$buildHelper = Join-Path $PSScriptRoot "build-from-powershell.ps1"
$buildMsiScript = Join-Path $PSScriptRoot "build-msi.ps1"
$launchScript = Join-Path $PSScriptRoot "oci-launch-validation-vm.ps1"
$rdpScript = Join-Path $PSScriptRoot "oci-open-rdp-rule.ps1"
$pushScript = Join-Path $PSScriptRoot "oci-push-and-test-msi.ps1"
$terminateScript = Join-Path $PSScriptRoot "oci-terminate-validation-vm.ps1"

$resolvedMsiPath = $null
$launchState = $null
$validationResult = $null

try {
  if (-not $MsiPath) {
    if (-not $Version) {
      $Version = Resolve-OmdVersionFromGit
    }

    if (-not $SkipBuild) {
      & $buildHelper -Task build -MsysRoot $MsysRoot
      if ($LASTEXITCODE -ne 0) {
        throw "Windows build failed."
      }
    }

    if (-not $SkipTest) {
      & $buildHelper -Task test -MsysRoot $MsysRoot
      if ($LASTEXITCODE -ne 0) {
        throw "Windows tests failed."
      }
    }

    if (-not $SkipStage) {
      & $buildHelper -Task stage -StageDir $StageDir -MsysRoot $MsysRoot
      if ($LASTEXITCODE -ne 0) {
        throw "Windows staging failed."
      }
    }

    if (-not $SkipPackage) {
      $resolvedInstallerOutDir = Resolve-OmdPath -Path $InstallerOutDir -AllowMissing
      New-Item -ItemType Directory -Force -Path $resolvedInstallerOutDir | Out-Null
      & $buildMsiScript -StagingDir $StageDir -Version $Version -OutDir $resolvedInstallerOutDir
      if ($LASTEXITCODE -ne 0) {
        throw "MSI packaging failed."
      }
    }

    $normalizedVersion = Normalize-OmdMsiVersion -Version $Version
    $resolvedMsiPath = Resolve-OmdPath -Path (Join-Path $InstallerOutDir ("ObjcMarkdown-" + $normalizedVersion + "-win64.msi"))
  } else {
    $resolvedMsiPath = Resolve-OmdPath -Path $MsiPath
  }

  $launchState = & $launchScript `
    -CompartmentId $CompartmentId `
    -AvailabilityDomain $AvailabilityDomain `
    -SubnetId $SubnetId `
    -ImageId $ImageId `
    -Shape $Shape `
    -Ocpus $Ocpus `
    -MemoryInGBs $MemoryInGBs `
    -SshPublicKeyPath $SshPublicKeyPath `
    -IdentityFile $IdentityFile `
    -JumpHost $JumpHost `
    -SshUser $SshUser `
    -StateFile $StateFile

  if ($OpenRdp) {
    & $rdpScript -SubnetId $SubnetId -SourceCidr $RdpSourceCidr
  }

  $validationParams = @{
    MsiPath       = $resolvedMsiPath
    StateFile     = $StateFile
    IdentityFile  = $IdentityFile
    JumpHost      = $JumpHost
    SshUser       = $SshUser
    RunSmoke      = $RunSmoke
  }
  if ($LogDir) {
    $validationParams.LocalLogDir = $LogDir
  }

  $validationResult = & $pushScript @validationParams
} finally {
  $resolvedStateFile = Resolve-OmdPath -Path $StateFile -AllowMissing
  if ((-not $KeepVm) -and ($launchState -or (Test-Path $resolvedStateFile))) {
    & $terminateScript -StateFile $StateFile | Out-Null
  }
}

[pscustomobject]@{
  msiPath    = $resolvedMsiPath
  stateFile  = Resolve-OmdPath -Path $StateFile -AllowMissing
  guestHost  = $(if ($launchState) { $launchState.publicIp } else { $null })
  logDir     = $(if ($validationResult) { $validationResult.localLogDir } else { $null })
  keptVm     = [bool]$KeepVm
  finishedAt = (Get-Date).ToString("o")
}
