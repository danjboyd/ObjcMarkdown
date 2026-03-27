[CmdletBinding()]
param(
  [string]$StageRoot = "dist/gnustep-packager-stage"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

& .\scripts\windows\build-from-powershell.ps1 -Task stage -StageDir $StageRoot
if ($LASTEXITCODE -ne 0) {
  throw "ObjcMarkdown Windows staging failed."
}

$resolvedStageRoot = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $StageRoot))
$metadataIcons = Join-Path $resolvedStageRoot "metadata\\icons"
$metadataDocs = Join-Path $resolvedStageRoot "metadata\\docs"
$resourceRoot = Join-Path $resolvedStageRoot "app\\MarkdownViewer.app\\Resources"

foreach ($dir in @($metadataIcons, $metadataDocs)) {
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

foreach ($fileName in @("markdown_icon.png", "open-icon.png")) {
  $source = Join-Path $resourceRoot $fileName
  if (Test-Path $source) {
    Copy-Item -Force $source (Join-Path $metadataIcons $fileName)
  }
}

Copy-Item -Force ".\FileAssociations.md" (Join-Path $metadataDocs "FileAssociations.md")
Set-Content -Path (Join-Path $resolvedStageRoot "metadata\\README.txt") -Value "gnustep-packager metadata for ObjcMarkdown"
