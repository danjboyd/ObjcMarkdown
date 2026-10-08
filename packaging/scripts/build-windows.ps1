[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# cmark-gfm is vendored and compiled into libObjcMarkdown, so no MSYS2 cmark
# package needs syncing into the GNUstep toolchain.

& .\packaging\scripts\ensure-windows-theme-inputs.ps1 | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "ObjcMarkdown Windows theme preparation failed."
}

# The fixes in packaging/patches (#94): rebuild gnustep-base and gnustep-gui
# with them and put their DLLs in the toolchain, which the MSI stages from.
# The script only replaces the DLLs in CI, where the toolchain is thrown away.
& .\scripts\windows\build-from-powershell.ps1 -Task command -Command "bash packaging/scripts/build-windows-gnustep-patches.sh --install"
if ($LASTEXITCODE -ne 0) {
  throw "Building the patched GNUstep libraries failed."
}

& .\scripts\windows\build-from-powershell.ps1 -Task command -Command "make OMD_SKIP_TESTS=1"
if ($LASTEXITCODE -ne 0) {
  throw "ObjcMarkdown Windows build failed."
}
