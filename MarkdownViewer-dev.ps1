# Starts the most recent development build of Markdown Viewer, for the
# Start-menu shortcut. Each successful top-level `make` on Windows copies
# the app and the project's DLLs to a new folder under
# %LOCALAPPDATA%\ObjcMarkdown-dev\builds (scripts/windows/snapshot-dev-build.sh)
# and this runs that copy. It doesn't build: run make to update it.
#
# The app's messages go to %TEMP%\MarkdownViewer-dev-<date>-<time>.log (the
# five newest are kept). Files given as arguments are opened.
#
# Windows lets only the program a shortcut starts bring a window to the
# front; this script is that program, so it first lets the app it starts
# take the foreground.
#
# Shortcut target:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File <this file>

param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Files)

$ErrorActionPreference = "Stop"

$msysRoot = if ($env:MSYS2_LOCATION) { $env:MSYS2_LOCATION } else { "C:\msys64" }
$runtime = Join-Path $msysRoot "clang64\bin"
$builds = Join-Path $env:LOCALAPPDATA "ObjcMarkdown-dev\builds"
$currentFile = Join-Path $builds "current"

function Show-Problem([string]$message) {
  [void](New-Object -ComObject WScript.Shell).Popup($message, 0, "Markdown Viewer (development build)", 48)
  exit 1
}

$current = if (Test-Path $currentFile) { (Get-Content -Path $currentFile -TotalCount 1).Trim() } else { "" }
$build = if ($current) { Join-Path $builds $current } else { "" }
$exe = if ($build) { Join-Path $build "MarkdownViewer.app\MarkdownViewer.exe" } else { "" }
if (-not $exe -or -not (Test-Path $exe)) {
  Show-Problem ("There is no development build to run yet.`n`n" +
                "Build the project with make in an MSYS2 CLANG64 shell in`n" +
                "$PSScriptRoot`nand try again.")
}
if (-not (Test-Path (Join-Path $runtime "gnustep-base-*.dll"))) {
  Show-Problem "The GNUstep runtime wasn't found in $runtime (set MSYS2_LOCATION)."
}

Add-Type -Namespace OMD -Name Foreground -MemberDefinition @'
[DllImport("user32.dll")]
public static extern bool AllowSetForegroundWindow(int processId);
'@
# ASFW_ANY: until the user does something else, any process may.
[void][OMD.Foreground]::AllowSetForegroundWindow(-1)

# One log per launch: the app writes to it for as long as it runs.
$log = Join-Path $env:TEMP ("MarkdownViewer-dev-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
Get-ChildItem -Path $env:TEMP -Filter "MarkdownViewer-dev-*.log" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -Skip 4 |
  Remove-Item -ErrorAction SilentlyContinue

# The snapshot's DLLs first, then the GNUstep runtime.
$env:PATH = (Join-Path $build "lib") + ";" + $runtime + ";" + $env:PATH

$arguments = @()
foreach ($file in $Files) {
  $arguments += '"' + [System.IO.Path]::GetFullPath($file) + '"'
}

$start = @{
  FilePath = $exe
  WorkingDirectory = $env:USERPROFILE
  RedirectStandardError = $log
}
if ($arguments.Count -gt 0) {
  $start.ArgumentList = $arguments
}
Start-Process @start
