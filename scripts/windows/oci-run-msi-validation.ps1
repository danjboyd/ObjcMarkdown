[CmdletBinding()]
param(
  [string]$Version,
  [string]$MsysRoot = "C:\msys64",
  [string]$StageDir = "dist/ObjcMarkdown",
  [string]$InstallerOutDir = "dist/installer",
  [ValidateSet("legacy", "packager")]
  [string]$PackagingMode = "legacy",
  [string]$PackagerRoot = "..\gnustep-packager",
  [string]$PackagerManifest = "packaging/package.manifest.json",
  [string]$PackagerBackend = "msi",
  [string]$MsiPath,
  [string]$StateFile = "dist/oci/last-validation-vm.json",
  [string]$LogDir,
  [string]$CompartmentId,
  [string]$AvailabilityDomain,
  [string]$SecurityListId,
  [string]$SubnetId = "ocid1.subnet.oc1.phx.aaaaaaaaimvrd2faa744cu34ucvq2vpftgcnuhe7taaqhunvszhn64fzon4a",
  [string]$ImageId = "ocid1.image.oc1.phx.aaaaaaaa6253prkupypnde7blkcsojo66njxkyquiimmkdy7foiu4ywxyiva",
  [string]$Shape = "VM.Standard.E5.Flex",
  [int]$Ocpus = 1,
  [int]$MemoryInGBs = 12,
  [string]$SshPublicKeyPath,
  [string]$IdentityFile,
  [string]$JumpHost,
  [string]$SshUser = "opc",
  [string]$SshSourceCidr,
  [string]$OriginalSshSourceCidr = "0.0.0.0/0",
  [string]$TemporarySshRuleDescription = "Temporary SSH for MSI validation VM",
  [string]$OriginalSshRuleDescription = "",
  [string]$RdpSourceCidr,
  [switch]$OpenRdp,
  [switch]$TemporarilyRestrictSshIngress,
  [switch]$SkipCleanupExistingVm,
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
$temporarySshSourceCidr = $null
$restoredOriginalSshRule = $false
$cleanedExistingVm = $false

try {
  if (-not $SkipCleanupExistingVm) {
    $resolvedExistingStateFile = Resolve-OmdPath -Path $StateFile -AllowMissing
    if (Test-Path $resolvedExistingStateFile) {
      $existingState = Read-OmdStateFile -StateFile $resolvedExistingStateFile
      $existingInstanceId = [string]$existingState.instanceId
      $existingMarkedTerminated = [bool]($existingState.PSObject.Properties["terminated"] -and $existingState.terminated)
      if ((-not $existingMarkedTerminated) -and (-not [string]::IsNullOrWhiteSpace($existingInstanceId))) {
        try {
          $existingLifecycle = Get-OciInstanceLifecycleState -InstanceId $existingInstanceId
          if ($existingLifecycle -and ($existingLifecycle -notin @("TERMINATED", "TERMINATING"))) {
            Write-Host "Cleaning up existing validation VM recorded in state file: $existingInstanceId ($existingLifecycle)"
            & $terminateScript -StateFile $StateFile | Out-Null
            $cleanedExistingVm = $true
          }
        } catch {
          Write-Warning "Unable to inspect or terminate existing validation VM from ${resolvedExistingStateFile}: $($_.Exception.Message)"
        }
      }
    }
  }

  if (-not $MsiPath) {
    if (($PackagingMode -eq "legacy") -and (-not $Version)) {
      $Version = Resolve-OmdVersionFromGit
    }

    if ($PackagingMode -eq "packager") {
      if (-not $SkipTest) {
        & $buildHelper -Task test -MsysRoot $MsysRoot
        if ($LASTEXITCODE -ne 0) {
          throw "Windows tests failed."
        }
      }

      $resolvedPackagerRoot = Resolve-OmdGnustepPackagerRoot -PackagerRoot $PackagerRoot
      $resolvedPackagerManifest = Resolve-OmdGnustepPackagerManifestPath -ManifestPath $PackagerManifest
      $packagerPipeline = Join-Path $resolvedPackagerRoot "scripts\run-packaging-pipeline.ps1"
      if (-not (Test-Path $packagerPipeline)) {
        throw "gnustep-packager pipeline script not found: $packagerPipeline"
      }

      $packagerParams = @{
        Manifest              = $resolvedPackagerManifest
        Backend               = $PackagerBackend
        SkipBackendValidation = $true
      }
      if ($Version) {
        $packagerParams["PackageVersion"] = $Version
      }
      if ($SkipBuild) {
        $packagerParams["SkipBuild"] = $true
      }
      if ($SkipStage) {
        $packagerParams["SkipStage"] = $true
      }
      if ($SkipPackage) {
        $packagerParams["SkipPackage"] = $true
      }

      & $packagerPipeline @packagerParams
      if ($LASTEXITCODE -ne 0) {
        throw "gnustep-packager pipeline failed."
      }

      $artifactPlan = Get-OmdGnustepPackagerArtifactPlan `
        -PackagerRoot $resolvedPackagerRoot `
        -ManifestPath $resolvedPackagerManifest `
        -Backend $PackagerBackend `
        -PackageVersion $Version
      $resolvedMsiPath = $artifactPlan.ArtifactPath
      if (-not (Test-Path $resolvedMsiPath)) {
        throw "gnustep-packager MSI artifact not found: $resolvedMsiPath"
      }
    } else {
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
    }
  } else {
    $resolvedMsiPath = Resolve-OmdPath -Path $MsiPath
  }

  $launchParams = @{
    CompartmentId      = $CompartmentId
    AvailabilityDomain = $AvailabilityDomain
    SubnetId           = $SubnetId
    ImageId            = $ImageId
    Shape              = $Shape
    Ocpus              = $Ocpus
    MemoryInGBs        = $MemoryInGBs
    SshPublicKeyPath   = $SshPublicKeyPath
    IdentityFile       = $IdentityFile
    JumpHost           = $JumpHost
    SshUser            = $SshUser
    StateFile          = $StateFile
  }
  if ($TemporarilyRestrictSshIngress) {
    $launchParams.SkipSshWait = $true
  }

  $launchState = & $launchScript @launchParams

  if ($TemporarilyRestrictSshIngress) {
    $temporarySshSourceCidr = Get-OmdCurrentPublicCidr -SourceCidr $SshSourceCidr
    Write-Host "Adding temporary SSH ingress rule for $temporarySshSourceCidr"
    & $rdpScript `
      -SecurityListId $SecurityListId `
      -SubnetId $SubnetId `
      -Port 22 `
      -SourceCidr $temporarySshSourceCidr `
      -Description $TemporarySshRuleDescription | Out-Null

    if ($OriginalSshSourceCidr) {
      Write-Host "Removing original SSH ingress rule for $OriginalSshSourceCidr"
      & $rdpScript `
        -SecurityListId $SecurityListId `
        -SubnetId $SubnetId `
        -Port 22 `
        -SourceCidr $OriginalSshSourceCidr `
        -Description $OriginalSshRuleDescription `
        -Remove | Out-Null
    }
  }

  if ($OpenRdp) {
    & $rdpScript -SecurityListId $SecurityListId -SubnetId $SubnetId -SourceCidr $RdpSourceCidr
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

  $validationOutput = @(& $pushScript @validationParams)
  $validationResult = $validationOutput |
    Where-Object { $_ -and $_.PSObject -and $_.PSObject.Properties["localLogDir"] } |
    Select-Object -Last 1
} finally {
  if ($TemporarilyRestrictSshIngress -and $temporarySshSourceCidr -and -not $KeepVm) {
    Write-Host "Restoring SSH ingress rules"
    & $rdpScript `
      -SecurityListId $SecurityListId `
      -SubnetId $SubnetId `
      -Port 22 `
      -SourceCidr $temporarySshSourceCidr `
      -Description $TemporarySshRuleDescription `
      -Remove | Out-Null

    if ($OriginalSshSourceCidr) {
      & $rdpScript `
        -SecurityListId $SecurityListId `
        -SubnetId $SubnetId `
        -Port 22 `
        -SourceCidr $OriginalSshSourceCidr `
        -Description $OriginalSshRuleDescription | Out-Null
      $restoredOriginalSshRule = $true
    }
  }

  $resolvedStateFile = Resolve-OmdPath -Path $StateFile -AllowMissing
  if ((-not $KeepVm) -and ($launchState -or (Test-Path $resolvedStateFile))) {
    & $terminateScript -StateFile $StateFile | Out-Null
  }
}

[pscustomobject]@{
  msiPath    = $resolvedMsiPath
  packagingMode = $PackagingMode
  stateFile  = Resolve-OmdPath -Path $StateFile -AllowMissing
  guestHost  = $(if ($launchState) { $launchState.publicIp } else { $null })
  logDir     = $(if ($validationResult -and $validationResult.PSObject.Properties["localLogDir"]) { $validationResult.localLogDir } else { $null })
  keptVm     = [bool]$KeepVm
  temporarySshSourceCidr = $temporarySshSourceCidr
  restoredOriginalSshRule = $restoredOriginalSshRule
  cleanedExistingVm = [bool]$cleanedExistingVm
  finishedAt = (Get-Date).ToString("o")
}
