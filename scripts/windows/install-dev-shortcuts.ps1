$ErrorActionPreference = "Stop"

$RepoRoot = "C:\Users\Support\git\ObjcMarkdown"
$Target = Join-Path $env:WINDIR "System32\wscript.exe"
$Arguments = '"' + (Join-Path $RepoRoot "MarkdownViewer-dev.vbs") + '"'
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
  if (Test-Path $Icon) {
    $shortcut.IconLocation = $Icon
  }
  $shortcut.Save()
}

Write-Output "Installed shortcuts:"
Write-Output $DesktopShortcut
Write-Output $ProgramsShortcut
