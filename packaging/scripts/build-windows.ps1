[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$themeInputs = & .\packaging\scripts\ensure-windows-theme-inputs.ps1
if ($LASTEXITCODE -ne 0) {
  throw "ObjcMarkdown Windows theme preparation failed."
}
if (-not $themeInputs -or -not $themeInputs.userThemeRoot) {
  throw "ObjcMarkdown Windows theme preparation did not return a theme root."
}
$env:OMD_GNUSTEP_USER_THEME_ROOT = [string]$themeInputs.userThemeRoot
Write-Host ("Prepared Windows GNUstep themes in {0}" -f $env:OMD_GNUSTEP_USER_THEME_ROOT)

& .\scripts\windows\build-from-powershell.ps1 -Task command -Command "make GNUSTEP_MAKEFILES=`$GNUSTEP_MAKEFILES OMD_SKIP_TESTS=1"
if ($LASTEXITCODE -ne 0) {
  throw "ObjcMarkdown Windows build failed."
}
