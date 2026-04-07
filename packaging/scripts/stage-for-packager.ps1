[CmdletBinding()]
param(
  [string]$StageRoot = "dist/gnustep-packager-stage"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$msysRoot = if (-not [string]::IsNullOrWhiteSpace($env:MSYS2_LOCATION)) {
  $env:MSYS2_LOCATION
} else {
  "C:\msys64"
}

& .\scripts\windows\build-from-powershell.ps1 -Task stage -StageDir $StageRoot -MsysRoot $msysRoot
if ($LASTEXITCODE -ne 0) {
  throw "ObjcMarkdown Windows staging failed."
}

$themeInputsOutput = @(& .\packaging\scripts\ensure-windows-theme-inputs.ps1 -MsysRoot $msysRoot)
$themeInputs = $themeInputsOutput |
  Where-Object { $_ -and $_.PSObject -and $_.PSObject.Properties["themes"] } |
  Select-Object -Last 1
if (-not $themeInputs) {
  throw "Windows theme preparation did not return a structured theme payload."
}

$tinyTeXInputs = & .\packaging\scripts\ensure-tinytex-runtime.ps1
if (-not $tinyTeXInputs -or -not $tinyTeXInputs.root -or -not $tinyTeXInputs.bin) {
  throw "TinyTeX preparation did not return a structured runtime payload."
}

$resolvedStageRoot = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $StageRoot))
$metadataIcons = Join-Path $resolvedStageRoot "metadata\\icons"
$metadataDocs = Join-Path $resolvedStageRoot "metadata\\docs"
$resourceRoot = Join-Path $resolvedStageRoot "app\\MarkdownViewer.app\\Resources"
$runtimeThemeRoot = Join-Path $resolvedStageRoot "clang64\\lib\\GNUstep\\Themes"
$texLiveStageRoot = Join-Path $resolvedStageRoot "clang64\\texlive"
$tinyTeXStageRoot = Join-Path $texLiveStageRoot "TinyTeX"

foreach ($dir in @($metadataIcons, $metadataDocs, $runtimeThemeRoot, $texLiveStageRoot)) {
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

foreach ($fileName in @("markdown_icon.png", "open-icon.png")) {
  $source = Join-Path $resourceRoot $fileName
  if (Test-Path $source) {
    Copy-Item -Force $source (Join-Path $metadataIcons $fileName)
  }
}

$iconSource = ".\Resources\markdown_icon.ico"
if (Test-Path $iconSource) {
  Copy-Item -Force $iconSource (Join-Path $metadataIcons "markdown_icon.ico")
}

foreach ($theme in @($themeInputs.themes)) {
  $destination = Join-Path $runtimeThemeRoot ([System.IO.Path]::GetFileName([string]$theme.installedBundle))
  if (Test-Path $destination) {
    Remove-Item -LiteralPath $destination -Recurse -Force
  }
  Copy-Item -LiteralPath ([string]$theme.installedBundle) -Destination $runtimeThemeRoot -Recurse -Force
}

if (Test-Path $tinyTeXStageRoot) {
  Remove-Item -LiteralPath $tinyTeXStageRoot -Recurse -Force
}
Copy-Item -LiteralPath ([string]$tinyTeXInputs.root) -Destination $texLiveStageRoot -Recurse -Force

$expectedStageThemes = @(
  (Join-Path $runtimeThemeRoot "WinUXTheme.theme\\WinUXTheme.dll"),
  (Join-Path $runtimeThemeRoot "Win11Theme.theme\\Win11Theme.dll"),
  (Join-Path $runtimeThemeRoot "WinUITheme.theme\\WinUITheme.dll")
)
$missingStageThemes = @($expectedStageThemes | Where-Object { -not (Test-Path $_) })
if ($missingStageThemes.Count -gt 0) {
  throw "Required bundled themes were not staged: $($missingStageThemes -join ', ')"
}

$requiredTinyTeXPaths = @(
  (Join-Path $tinyTeXStageRoot "bin\\windows\\latex.exe"),
  (Join-Path $tinyTeXStageRoot "bin\\windows\\dvisvgm.exe"),
  (Join-Path $tinyTeXStageRoot "bin\\windows\\dvipng.exe")
)
$missingTinyTeXPaths = @($requiredTinyTeXPaths | Where-Object { -not (Test-Path $_) })
if ($missingTinyTeXPaths.Count -gt 0) {
  throw "Required TinyTeX runtime files were not staged: $($missingTinyTeXPaths -join ', ')"
}

Copy-Item -Force ".\FileAssociations.md" (Join-Path $metadataDocs "FileAssociations.md")
Set-Content -Path (Join-Path $metadataDocs "BundledThemes.txt") -Value @(
  "Bundled GNUstep themes for ObjcMarkdown MSI:"
  "WinUXTheme (staged from the CLANG64 GNUstep runtime)"
  ("Win11Theme (staged from {0})" -f [string](($themeInputs.themes | Where-Object { $_.name -eq "Win11Theme" } | Select-Object -First 1).repo))
  ("WinUITheme (runtime default; staged from {0})" -f [string](($themeInputs.themes | Where-Object { $_.name -eq "WinUITheme" } | Select-Object -First 1).repo))
)
Set-Content -Path (Join-Path $metadataDocs "BundledLaTeXRuntime.txt") -Value @(
  "Bundled TinyTeX runtime for ObjcMarkdown MSI:"
  ("ReleaseTag={0}" -f [string]$tinyTeXInputs.releaseTag)
  ("AssetName={0}" -f [string]$tinyTeXInputs.assetName)
  ("DownloadUrl={0}" -f [string]$tinyTeXInputs.downloadUrl)
  "Bundled binaries verified during staging:"
  "clang64/texlive/TinyTeX/bin/windows/latex.exe"
  "clang64/texlive/TinyTeX/bin/windows/dvisvgm.exe"
  "clang64/texlive/TinyTeX/bin/windows/dvipng.exe"
  "Math rendering default: External Tools (LaTeX) when the bundled toolchain is present."
)
Set-Content -Path (Join-Path $resolvedStageRoot "metadata\\README.txt") -Value "gnustep-packager metadata for ObjcMarkdown"
