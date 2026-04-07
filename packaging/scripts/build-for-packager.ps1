[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$msysRoot = if (-not [string]::IsNullOrWhiteSpace($env:MSYS2_LOCATION)) {
  $env:MSYS2_LOCATION
} else {
  "C:\msys64"
}

& .\scripts\windows\build-from-powershell.ps1 -Task command -Command "make OMD_SKIP_TESTS=1" -MsysRoot $msysRoot
if ($LASTEXITCODE -ne 0) {
  throw "ObjcMarkdown Windows build failed."
}
