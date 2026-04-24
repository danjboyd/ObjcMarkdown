[CmdletBinding()]
param(
  [string]$StageRoot = "dist/packaging/windows/stage"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

& .\scripts\windows\build-from-powershell.ps1 -Task stage -StageDir $StageRoot
if ($LASTEXITCODE -ne 0) {
  throw "ObjcMarkdown Windows staging failed."
}

$tinyTeXInputs = & .\packaging\scripts\ensure-tinytex-runtime.ps1
if (-not $tinyTeXInputs -or -not $tinyTeXInputs.root -or -not $tinyTeXInputs.bin) {
  throw "TinyTeX preparation did not return a structured runtime payload."
}

$resolvedStageRoot = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $StageRoot))
$runtimeRoot = Join-Path $resolvedStageRoot "runtime"
$tinyTeXStageRoot = Join-Path $runtimeRoot "texlive\TinyTeX"
$metadataDocs = Join-Path $resolvedStageRoot "metadata\docs"

foreach ($dir in @($metadataDocs)) {
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

if (Test-Path $tinyTeXStageRoot) {
  Remove-Item -LiteralPath $tinyTeXStageRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path ([System.IO.Path]::GetDirectoryName($tinyTeXStageRoot)) | Out-Null
Copy-Item -LiteralPath ([string]$tinyTeXInputs.root) -Destination ([System.IO.Path]::GetDirectoryName($tinyTeXStageRoot)) -Recurse -Force

$requiredTinyTeXPaths = @(
  (Join-Path $tinyTeXStageRoot "bin\windows\latex.exe"),
  (Join-Path $tinyTeXStageRoot "bin\windows\dvisvgm.exe"),
  (Join-Path $tinyTeXStageRoot "bin\windows\dvipng.exe")
)
$missingTinyTeXPaths = @($requiredTinyTeXPaths | Where-Object { -not (Test-Path $_) })
if ($missingTinyTeXPaths.Count -gt 0) {
  throw "Required TinyTeX runtime files were not staged: $($missingTinyTeXPaths -join ', ')"
}

$bundledThemeNames = @()
$themeRoot = Join-Path $runtimeRoot "lib\GNUstep\Themes"
if (Test-Path $themeRoot) {
  $bundledThemeNames = @(
    Get-ChildItem -Path $themeRoot -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -like "*.theme" } |
      ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) } |
      Sort-Object -Unique
  )
}
$bundledThemeSummary = if ($bundledThemeNames.Count -gt 0) {
  "Bundled themes include {0}." -f ($bundledThemeNames -join ", ")
} else {
  "No additional GNUstep themes were bundled by the ObjcMarkdown stage step."
}
Set-Content -Path (Join-Path $metadataDocs "BundledThemes.txt") -Value @(
  "Bundled GNUstep themes for ObjcMarkdown MSI:"
  $bundledThemeSummary
  "Windows GNUstep theme inputs are provisioned by gnustep-packager after app staging."
  "Packaged Windows launches default to GSTheme=WinUITheme when the user has not already chosen a theme."
)
Set-Content -Path (Join-Path $metadataDocs "BundledLaTeXRuntime.txt") -Value @(
  "Bundled TinyTeX runtime for ObjcMarkdown MSI:"
  ("ReleaseTag={0}" -f [string]$tinyTeXInputs.releaseTag)
  ("AssetName={0}" -f [string]$tinyTeXInputs.assetName)
  ("DownloadUrl={0}" -f [string]$tinyTeXInputs.downloadUrl)
  "Bundled binaries verified during staging:"
  "runtime/texlive/TinyTeX/bin/windows/latex.exe"
  "runtime/texlive/TinyTeX/bin/windows/dvisvgm.exe"
  "runtime/texlive/TinyTeX/bin/windows/dvipng.exe"
)
