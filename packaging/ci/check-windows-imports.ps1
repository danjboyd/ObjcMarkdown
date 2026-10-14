# Checks the packaged Windows payload: every DLL an executable or DLL in it
# imports must be in the payload or in System32. Runs on a Windows runner
# after packaging (windows-packaging.yml), on the portable zip, which holds
# the same files as the MSI.
#
# stage-windows-runtime.sh walks imports from what it stages, but the
# packager provisions the themes (WinUITheme) afterwards, so a theme that
# imports something new would ship broken without this check (#128).
param(
  [Parameter(Mandatory = $true)][string]$PayloadRoot
)

$ErrorActionPreference = 'Stop'

$objdump = Get-Command llvm-objdump -ErrorAction SilentlyContinue
if (-not $objdump) {
  $candidate = Join-Path $env:ProgramFiles 'LLVM\bin\llvm-objdump.exe'
  if (Test-Path $candidate) { $objdump = Get-Item $candidate }
}
if (-not $objdump) { throw 'llvm-objdump not found.' }
$objdumpPath = if ($objdump.Source) { $objdump.Source } else { $objdump.FullName }

$system32 = Join-Path $env:SystemRoot 'System32'
$binaries = @(Get-ChildItem -Path $PayloadRoot -Recurse -File |
  Where-Object { $_.Extension -in @('.exe', '.dll') })
if ($binaries.Count -eq 0) { throw "No executables or DLLs under $PayloadRoot." }

# Every DLL in the payload, by lower-case name. GNUstep's launcher puts
# runtime\bin on PATH, so a DLL there satisfies any importer; others are
# found beside their importer.
$runtimeBin = @(Get-ChildItem -Path $PayloadRoot -Recurse -Directory |
  Where-Object { $_.FullName -match '[\\/]runtime[\\/]bin$' })
if ($runtimeBin.Count -ne 1) { throw "Expected one runtime\bin under $PayloadRoot, found $($runtimeBin.Count)." }
$onPath = @{}
Get-ChildItem -Path $runtimeBin[0].FullName -File -Filter '*.dll' | ForEach-Object { $onPath[$_.Name.ToLowerInvariant()] = $true }

$missing = @()
foreach ($binary in $binaries) {
  $imports = & $objdumpPath -p $binary.FullName 2>$null |
    Select-String -Pattern 'DLL Name:\s*(\S+)' |
    ForEach-Object { $_.Matches[0].Groups[1].Value }
  foreach ($name in $imports) {
    $lower = $name.ToLowerInvariant()
    if ($lower.StartsWith('api-ms-win-') -or $lower.StartsWith('ext-ms-')) { continue }
    if ($onPath.ContainsKey($lower)) { continue }
    if (Test-Path (Join-Path $binary.DirectoryName $name)) { continue }
    if (Test-Path (Join-Path $system32 $name)) { continue }
    $missing += "$($binary.FullName.Substring($PayloadRoot.Length).TrimStart('\', '/')) -> $name"
  }
}

Write-Host "Checked the imports of $($binaries.Count) executables and DLLs under $PayloadRoot."
if ($missing.Count -gt 0) {
  Write-Host "ERROR: imports found neither in the payload nor in System32:"
  $missing | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }
  exit 1
}
Write-Host 'Every import is in the payload or in System32.'
