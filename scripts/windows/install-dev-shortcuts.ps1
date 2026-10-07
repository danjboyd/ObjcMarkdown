$ErrorActionPreference = "Stop"

$RepoRoot = "C:\Users\Support\git\ObjcMarkdown"
# MarkdownViewer-dev.ps1 lets the app come to the front (see the script).
$Target = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
$Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $RepoRoot "MarkdownViewer-dev.ps1") + '"'
$WorkingDirectory = $RepoRoot
$Icon = Join-Path $RepoRoot "ObjcMarkdownViewer\MarkdownViewer.app\MarkdownViewer.exe"

$DesktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "Markdown Viewer.lnk"
$ProgramsShortcut = Join-Path ([Environment]::GetFolderPath("Programs")) "Markdown Viewer.lnk"

$shell = New-Object -ComObject WScript.Shell
foreach ($path in @($DesktopShortcut, $ProgramsShortcut)) {
  $shortcut = $shell.CreateShortcut($path)
  $shortcut.TargetPath = $Target
  $shortcut.Arguments = $Arguments
  $shortcut.WorkingDirectory = $WorkingDirectory
  $shortcut.WindowStyle = 7  # minimized: no flash while PowerShell starts
  if (Test-Path $Icon) {
    $shortcut.IconLocation = $Icon
  }
  $shortcut.Save()
}

Write-Output "Installed shortcuts:"
Write-Output $DesktopShortcut
Write-Output $ProgramsShortcut
