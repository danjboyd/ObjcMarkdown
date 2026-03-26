[CmdletBinding()]
param(
  [string]$SecurityListId,
  [string]$SubnetId = "ocid1.subnet.oc1.phx.aaaaaaaaimvrd2faa744cu34ucvq2vpftgcnuhe7taaqhunvszhn64fzon4a",
  [string]$SourceCidr,
  [int]$Port = 3389,
  [string]$Description = "Temporary RDP for MSI validation VM",
  [switch]$Remove
)

. (Join-Path $PSScriptRoot "oci-common.ps1")

if (-not $SecurityListId) {
  $subnet = Invoke-OciJson -Arguments @("network", "subnet", "get", "--subnet-id", $SubnetId)
  $securityListIds = @(Get-OmdPropertyValue -InputObject $subnet.data -Names @("security-list-ids", "securityListIds"))
  $SecurityListId = $securityListIds | Select-Object -First 1
  if (-not $SecurityListId) {
    throw "Unable to determine a security list from subnet $SubnetId"
  }
}

$resolvedSourceCidr = Get-OmdCurrentPublicCidr -SourceCidr $SourceCidr
$securityList = Invoke-OciJson -Arguments @("network", "security-list", "get", "--security-list-id", $SecurityListId)
$existingRules = @(Get-OmdPropertyValue -InputObject $securityList.data -Names @("ingress-security-rules", "ingressSecurityRules"))
$updatedRules = New-Object System.Collections.Generic.List[object]
$removedMatch = $false
$matchExists = $false

foreach ($rule in $existingRules) {
  if (Test-OmdRdpIngressRule -Rule $rule -SourceCidr $resolvedSourceCidr -Port $Port -Description $Description) {
    if ($Remove) {
      $removedMatch = $true
      continue
    }

    $matchExists = $true
  }

  $updatedRules.Add((ConvertTo-OmdCanonicalIngressRule -Rule $rule))
}

if (-not $Remove -and -not $matchExists) {
  $newRule = [ordered]@{
    protocol    = "6"
    source      = $resolvedSourceCidr
    sourceType  = "CIDR_BLOCK"
    isStateless = $false
    tcpOptions  = [ordered]@{
      destinationPortRange = [ordered]@{
        min = $Port
        max = $Port
      }
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($Description)) {
    $newRule.description = $Description
  }

  $updatedRules.Add($newRule)
}

if ($Remove -and -not $removedMatch) {
  Write-Host "No matching ingress rule found for $resolvedSourceCidr on $SecurityListId"
  return
}

if (-not $Remove -and $matchExists) {
  Write-Host "Ingress rule already exists for $resolvedSourceCidr on $SecurityListId"
  return
}

$rulesJson = ($updatedRules | ConvertTo-Json -Depth 12 -Compress)
$actionText = if ($Remove) { "Removing" } else { "Adding" }
Write-Host "$actionText ingress rule on $SecurityListId for $resolvedSourceCidr"
Invoke-OciJson -Arguments @(
  "network", "security-list", "update",
  "--security-list-id", $SecurityListId,
  "--force",
  "--ingress-security-rules", $rulesJson
) | Out-Null

[pscustomobject]@{
  action         = $(if ($Remove) { "removed" } else { "added" })
  securityListId = $SecurityListId
  sourceCidr     = $resolvedSourceCidr
  port           = $Port
  description    = $Description
}
