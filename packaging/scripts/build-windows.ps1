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

& .\scripts\windows\build-from-powershell.ps1 -Task command -Command "printf 'pkg-config cmark: '; pkg-config --cflags cmark || printf '(failed)\n'; printf 'pkg-config libcmark: '; pkg-config --cflags libcmark || printf '(failed)\n'; printf 'GP_GNUSTEP_CLI_ROOT=%s\n' \"`$GP_GNUSTEP_CLI_ROOT\"; find /clang64/include -maxdepth 2 \\( -name 'cmark.h' -o -name 'cmark*.h' \\) -print 2>/dev/null || true; make GNUSTEP_MAKEFILES=/clang64/share/GNUstep/Makefiles OMD_SKIP_TESTS=1 messages=yes"
if ($LASTEXITCODE -ne 0) {
  throw "ObjcMarkdown Windows build failed."
}
