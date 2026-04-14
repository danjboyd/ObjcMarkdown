[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

& .\scripts\windows\build-from-powershell.ps1 -Task command -Command "make OMD_SKIP_TESTS=1"
if ($LASTEXITCODE -ne 0) {
  throw "ObjcMarkdown Windows build failed."
}
