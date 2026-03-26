Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:OmdOciDefaults = [ordered]@{
  Region       = "us-phoenix-1"
  SubnetId     = "ocid1.subnet.oc1.phx.aaaaaaaaimvrd2faa744cu34ucvq2vpftgcnuhe7taaqhunvszhn64fzon4a"
  ImageId      = "ocid1.image.oc1.phx.aaaaaaaa6253prkupypnde7blkcsojo66njxkyquiimmkdy7foiu4ywxyiva"
  Shape        = "VM.Standard.E5.Flex"
  Ocpus        = 1
  MemoryInGBs  = 12
  SshUser      = "opc"
  StateFile    = "dist/oci/last-validation-vm.json"
  LogRoot      = "dist/oci-logs"
}

function Get-OmdRepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Expand-OmdPath {
  param([Parameter(Mandatory = $true)][string]$Path)

  if ($Path.StartsWith("~\")) {
    return Join-Path $HOME $Path.Substring(2)
  }
  if ($Path -eq "~") {
    return $HOME
  }

  return $Path
}

function Resolve-OmdPath {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$BasePath = (Get-OmdRepoRoot),
    [switch]$AllowMissing
  )

  $expandedPath = Expand-OmdPath -Path $Path
  $candidate = if ([System.IO.Path]::IsPathRooted($expandedPath)) {
    [System.IO.Path]::GetFullPath($expandedPath)
  } else {
    [System.IO.Path]::GetFullPath((Join-Path $BasePath $expandedPath))
  }

  if (-not $AllowMissing -and -not (Test-Path $candidate)) {
    throw "Path not found: $candidate"
  }

  return $candidate
}

function Assert-ExternalCommand {
  param([Parameter(Mandatory = $true)][string]$Name)

  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command not found on PATH: $Name"
  }
}

function Invoke-NativeCapture {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )

  $output = & $FilePath @Arguments 2>&1
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) {
    $message = if ($output) { ($output -join [Environment]::NewLine).Trim() } else { "$FilePath failed with exit code $exitCode" }
    throw $message
  }

  return ($output -join [Environment]::NewLine).Trim()
}

function Invoke-NativePassThru {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )

  & $FilePath @Arguments
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) {
    throw "$FilePath failed with exit code $exitCode"
  }
}

function Invoke-OciJson {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)

  Assert-ExternalCommand -Name "oci"
  $stderrPath = Join-Path ([System.IO.Path]::GetTempPath()) ("omd-oci-stderr-" + [Guid]::NewGuid().ToString("N") + ".log")
  try {
    $stdout = & oci @($Arguments + @("--output", "json")) 2> $stderrPath
    $exitCode = $LASTEXITCODE
    if (Test-Path $stderrPath) {
      $stderrRaw = Get-Content -Path $stderrPath -Raw
      $stderr = if ($null -ne $stderrRaw) { $stderrRaw.Trim() } else { "" }
    } else {
      $stderr = ""
    }
    $stdoutLines = @($stdout)

    if ($exitCode -ne 0) {
      $message = if ($stderr) { $stderr } elseif ($stdoutLines.Count -gt 0) { ($stdoutLines -join [Environment]::NewLine).Trim() } else { "oci failed with exit code $exitCode" }
      throw $message
    }

    $jsonText = ($stdoutLines -join [Environment]::NewLine).Trim()
    if (-not $jsonText) {
      return $null
    }
    if ([string]::IsNullOrWhiteSpace($jsonText)) {
      return $null
    }

    return $jsonText | ConvertFrom-Json
  } finally {
    Remove-Item -Force $stderrPath -ErrorAction SilentlyContinue
  }
}

function Get-OmdPropertyValue {
  param(
    [Parameter(Mandatory = $true)]$InputObject,
    [Parameter(Mandatory = $true)][string[]]$Names
  )

  foreach ($name in $Names) {
    $property = $InputObject.PSObject.Properties[$name]
    if ($property) {
      return $property.Value
    }
  }

  return $null
}

function Get-OciConfigValue {
  param(
    [Parameter(Mandatory = $true)][string]$Key,
    [string]$Profile = $(if ($env:OCI_CLI_PROFILE) { $env:OCI_CLI_PROFILE } else { "DEFAULT" }),
    [string]$ConfigPath = $(if ($env:OCI_CLI_CONFIG_FILE) { $env:OCI_CLI_CONFIG_FILE } else { (Join-Path $HOME ".oci\config") })
  )

  if (-not (Test-Path $ConfigPath)) {
    return $null
  }

  $normalizedProfileNames = @($Profile, "profile $Profile")
  $activeProfile = $null

  foreach ($line in Get-Content $ConfigPath) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith("#")) {
      continue
    }

    if ($trimmed -match "^\[(.+)\]$") {
      $activeProfile = $Matches[1].Trim()
      continue
    }

    if ($activeProfile -notin $normalizedProfileNames) {
      continue
    }

    if ($trimmed -match "^([^=]+)=(.*)$") {
      $candidateKey = $Matches[1].Trim()
      if ($candidateKey -eq $Key) {
        return $Matches[2].Trim()
      }
    }
  }

  return $null
}

function Get-OciTenancyId {
  if ($env:OCI_CLI_TENANCY) {
    return $env:OCI_CLI_TENANCY
  }

  $configTenancy = Get-OciConfigValue -Key "tenancy"
  if ($configTenancy) {
    return $configTenancy
  }

  throw "Unable to determine OCI tenancy OCID from OCI_CLI_TENANCY or ~/.oci/config."
}

function Resolve-OciCompartmentId {
  param(
    [string]$CompartmentId,
    [Parameter(Mandatory = $true)][string]$SubnetId
  )

  if ($CompartmentId) {
    return $CompartmentId
  }

  $subnet = Invoke-OciJson -Arguments @("network", "subnet", "get", "--subnet-id", $SubnetId)
  $resolvedCompartment = Get-OmdPropertyValue -InputObject $subnet.data -Names @("compartment-id", "compartmentId")
  if (-not $resolvedCompartment) {
    throw "Unable to determine compartment ID from subnet $SubnetId"
  }

  return $resolvedCompartment
}

function Resolve-OciAvailabilityDomain {
  param([string]$AvailabilityDomain)

  if ($AvailabilityDomain) {
    return $AvailabilityDomain
  }

  $tenancyId = Get-OciTenancyId
  $availabilityDomains = Invoke-OciJson -Arguments @(
    "iam", "availability-domain", "list",
    "--compartment-id", $tenancyId,
    "--all"
  )

  $firstAd = @($availabilityDomains.data | ForEach-Object { $_.name }) | Select-Object -First 1
  if (-not $firstAd) {
    throw "Unable to determine an availability domain in tenancy $tenancyId"
  }

  return $firstAd
}

function Resolve-OmdSshPublicKeyPath {
  param([string]$SshPublicKeyPath)

  if ($SshPublicKeyPath) {
    return Resolve-OmdPath -Path $SshPublicKeyPath
  }

  $candidates = @(
    "~\.ssh\id_rsa.pub",
    "~\.ssh\id_ed25519.pub"
  )

  foreach ($candidate in $candidates) {
    $resolvedCandidate = Resolve-OmdPath -Path $candidate -AllowMissing
    if (Test-Path $resolvedCandidate) {
      return $resolvedCandidate
    }
  }

  throw "No SSH public key found. Pass -SshPublicKeyPath explicitly."
}

function Resolve-OmdIdentityFilePath {
  param(
    [string]$IdentityFile,
    [string]$SshPublicKeyPath
  )

  if ($IdentityFile) {
    return Resolve-OmdPath -Path $IdentityFile
  }

  if ($SshPublicKeyPath) {
    $resolvedPublicKeyPath = Resolve-OmdPath -Path $SshPublicKeyPath
    if ($resolvedPublicKeyPath.EndsWith(".pub")) {
      $candidate = $resolvedPublicKeyPath.Substring(0, $resolvedPublicKeyPath.Length - 4)
      if (Test-Path $candidate) {
        return $candidate
      }
    }
  }

  return $null
}

function Get-OmdSshCommonArguments {
  param(
    [string]$IdentityFile,
    [string]$JumpHost,
    [switch]$DisableHostKeyChecking = $true
  )

  $arguments = @()
  if ($JumpHost) {
    $arguments += @("-J", $JumpHost)
  }
  if ($IdentityFile) {
    $arguments += @("-i", (Resolve-OmdPath -Path $IdentityFile))
  }
  if ($DisableHostKeyChecking) {
    $arguments += @("-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=NUL")
  }

  return $arguments
}

function Invoke-OmdSshCommand {
  param(
    [Parameter(Mandatory = $true)][string]$TargetHost,
    [Parameter(Mandatory = $true)][string]$Command,
    [string]$User = $script:OmdOciDefaults.SshUser,
    [string]$IdentityFile,
    [string]$JumpHost,
    [switch]$DisableHostKeyChecking = $true
  )

  Assert-ExternalCommand -Name "ssh"
  $arguments = @(Get-OmdSshCommonArguments -IdentityFile $IdentityFile -JumpHost $JumpHost -DisableHostKeyChecking:$DisableHostKeyChecking)
  $arguments += @("$User@$TargetHost", $Command)
  Invoke-NativePassThru -FilePath "ssh" -Arguments $arguments
}

function Invoke-OmdScpCopy {
  param(
    [Parameter(Mandatory = $true)][string[]]$Sources,
    [Parameter(Mandatory = $true)][string]$Destination,
    [string]$IdentityFile,
    [string]$JumpHost,
    [switch]$DisableHostKeyChecking = $true
  )

  Assert-ExternalCommand -Name "scp"
  $arguments = @(Get-OmdSshCommonArguments -IdentityFile $IdentityFile -JumpHost $JumpHost -DisableHostKeyChecking:$DisableHostKeyChecking)
  $arguments += $Sources
  $arguments += $Destination
  Invoke-NativePassThru -FilePath "scp" -Arguments $arguments
}

function New-OmdTemporaryDirectory {
  $path = Join-Path ([System.IO.Path]::GetTempPath()) ("omd-oci-" + [Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $path | Out-Null
  return $path
}

function Save-OmdJsonFile {
  param(
    [Parameter(Mandatory = $true)]$InputObject,
    [Parameter(Mandatory = $true)][string]$Path
  )

  $resolvedPath = Resolve-OmdPath -Path $Path -AllowMissing
  $parent = Split-Path -Parent $resolvedPath
  if ($parent) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }

  $InputObject | ConvertTo-Json -Depth 12 | Set-Content -Path $resolvedPath -Encoding UTF8
  return $resolvedPath
}

function Read-OmdStateFile {
  param([Parameter(Mandatory = $true)][string]$StateFile)

  $resolvedStateFile = Resolve-OmdPath -Path $StateFile
  return (Get-Content -Path $resolvedStateFile -Raw) | ConvertFrom-Json
}

function Wait-OmdTcpPort {
  param(
    [Parameter(Mandatory = $true)][string]$TargetHost,
    [int]$Port = 22,
    [int]$TimeoutSeconds = 900,
    [int]$PollIntervalSeconds = 10
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    $client = [System.Net.Sockets.TcpClient]::new()
    $async = $null
    try {
      $async = $client.BeginConnect($TargetHost, $Port, $null, $null)
      if ($async.AsyncWaitHandle.WaitOne(3000, $false) -and $client.Connected) {
        $client.EndConnect($async) | Out-Null
        return
      }
    } catch {
    } finally {
      if ($async) {
        $async.AsyncWaitHandle.Close()
      }
      $client.Dispose()
    }

    Start-Sleep -Seconds $PollIntervalSeconds
  }

  throw "Timed out waiting for TCP $Port on $TargetHost"
}

function Wait-OmdSshReady {
  param(
    [Parameter(Mandatory = $true)][string]$TargetHost,
    [string]$User = $script:OmdOciDefaults.SshUser,
    [string]$IdentityFile,
    [string]$JumpHost,
    [switch]$DisableHostKeyChecking = $true,
    [int]$TimeoutSeconds = 900,
    [int]$PollIntervalSeconds = 10
  )

  Assert-ExternalCommand -Name "ssh"
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    try {
      $arguments = @(Get-OmdSshCommonArguments -IdentityFile $IdentityFile -JumpHost $JumpHost -DisableHostKeyChecking:$DisableHostKeyChecking)
      $arguments += @("-o", "ConnectTimeout=10", "$User@$TargetHost", "hostname")
      Invoke-NativeCapture -FilePath "ssh" -Arguments $arguments | Out-Null
      return
    } catch {
      Start-Sleep -Seconds $PollIntervalSeconds
    }
  }

  throw "Timed out waiting for SSH readiness on $TargetHost"
}

function Get-OciInstancePublicIp {
  param([Parameter(Mandatory = $true)][string]$InstanceId)

  $vnics = Invoke-OciJson -Arguments @("compute", "instance", "list-vnics", "--instance-id", $InstanceId)
  $firstVnic = @($vnics.data)[0]
  if (-not $firstVnic) {
    return $null
  }

  return Get-OmdPropertyValue -InputObject $firstVnic -Names @("public-ip", "publicIp")
}

function Wait-OciInstancePublicIp {
  param(
    [Parameter(Mandatory = $true)][string]$InstanceId,
    [int]$TimeoutSeconds = 900,
    [int]$PollIntervalSeconds = 10
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    $publicIp = Get-OciInstancePublicIp -InstanceId $InstanceId
    if ($publicIp) {
      return $publicIp
    }

    Start-Sleep -Seconds $PollIntervalSeconds
  }

  throw "Timed out waiting for a public IP on instance $InstanceId"
}

function Normalize-OmdMsiVersion {
  param([Parameter(Mandatory = $true)][string]$Version)

  $parts = @($Version.Split(".") | Where-Object { $_ -ne "" })
  while ($parts.Count -lt 3) {
    $parts += "0"
  }
  if ($parts.Count -eq 3) {
    $parts += "0"
  }
  if ($parts.Count -gt 4) {
    $parts = $parts[0..3]
  }

  return ($parts -join ".")
}

function Resolve-OmdVersionFromGit {
  Assert-ExternalCommand -Name "git"
  $tag = ""
  try {
    $tag = Invoke-NativeCapture -FilePath "git" -Arguments @("describe", "--tags", "--abbrev=0")
  } catch {
    return "0.0.0"
  }

  if ($tag -match "v?(\d+\.\d+\.\d+)") {
    return $Matches[1]
  }

  return "0.0.0"
}

function Get-OmdCurrentPublicCidr {
  param([string]$SourceCidr)

  if ($SourceCidr) {
    if ($SourceCidr.Contains("/")) {
      return $SourceCidr
    }
    return "$SourceCidr/32"
  }

  $services = @(
    "https://checkip.amazonaws.com/",
    "https://api.ipify.org/",
    "https://ifconfig.me/ip"
  )

  foreach ($service in $services) {
    try {
      $value = (Invoke-RestMethod -Uri $service -TimeoutSec 15).ToString().Trim()
      if ($value) {
        return "$value/32"
      }
    } catch {
    }
  }

  throw "Unable to determine current public IP automatically. Pass -SourceCidr explicitly."
}

function ConvertTo-OmdCanonicalIngressRule {
  param([Parameter(Mandatory = $true)]$Rule)

  $tcpOptions = Get-OmdPropertyValue -InputObject $Rule -Names @("tcpOptions", "tcp-options")
  $destinationPortRange = $null
  if ($tcpOptions) {
    $destinationPortRange = Get-OmdPropertyValue -InputObject $tcpOptions -Names @("destinationPortRange", "destination-port-range")
  }

  return [ordered]@{
    description  = Get-OmdPropertyValue -InputObject $Rule -Names @("description")
    protocol     = [string](Get-OmdPropertyValue -InputObject $Rule -Names @("protocol"))
    source       = Get-OmdPropertyValue -InputObject $Rule -Names @("source")
    sourceType   = $(if (Get-OmdPropertyValue -InputObject $Rule -Names @("sourceType", "source-type")) { Get-OmdPropertyValue -InputObject $Rule -Names @("sourceType", "source-type") } else { "CIDR_BLOCK" })
    isStateless  = [bool](Get-OmdPropertyValue -InputObject $Rule -Names @("isStateless", "is-stateless"))
    tcpOptions   = $(if ($destinationPortRange) {
      [ordered]@{
        destinationPortRange = [ordered]@{
          min = [int](Get-OmdPropertyValue -InputObject $destinationPortRange -Names @("min"))
          max = [int](Get-OmdPropertyValue -InputObject $destinationPortRange -Names @("max"))
        }
      }
    } else {
      $null
    })
    udpOptions   = Get-OmdPropertyValue -InputObject $Rule -Names @("udpOptions", "udp-options")
    icmpOptions  = Get-OmdPropertyValue -InputObject $Rule -Names @("icmpOptions", "icmp-options")
  }
}

function Test-OmdRdpIngressRule {
  param(
    [Parameter(Mandatory = $true)]$Rule,
    [Parameter(Mandatory = $true)][string]$SourceCidr,
    [int]$Port = 3389,
    [string]$Description = "Temporary RDP for MSI validation VM"
  )

  $canonical = ConvertTo-OmdCanonicalIngressRule -Rule $Rule
  if ($canonical.protocol -ne "6") {
    return $false
  }
  if ($canonical.source -ne $SourceCidr) {
    return $false
  }
  if ([string]$canonical.description -ne [string]$Description) {
    return $false
  }
  if (-not $canonical.tcpOptions -or -not $canonical.tcpOptions.destinationPortRange) {
    return $false
  }

  return ($canonical.tcpOptions.destinationPortRange.min -eq $Port -and $canonical.tcpOptions.destinationPortRange.max -eq $Port)
}
