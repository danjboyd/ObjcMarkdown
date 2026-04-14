[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

& .\packaging\scripts\ensure-windows-theme-inputs.ps1 | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "ObjcMarkdown Windows theme preparation failed."
}

& .\scripts\windows\build-from-powershell.ps1 -Task command -Command "make OMD_SKIP_TESTS=1"
if ($LASTEXITCODE -ne 0) {
  throw "ObjcMarkdown Windows build failed."
}
