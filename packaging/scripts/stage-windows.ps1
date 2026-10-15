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

$msysRoot = if (-not [string]::IsNullOrWhiteSpace($env:MSYS2_LOCATION)) {
  $env:MSYS2_LOCATION
} else {
  "C:\msys64"
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
& .\packaging\scripts\trim-tinytex-runtime.ps1 -TinyTeXRoot $tinyTeXStageRoot

$requiredTinyTeXPaths = @(
  (Join-Path $tinyTeXStageRoot "bin\windows\latex.exe"),
  (Join-Path $tinyTeXStageRoot "bin\windows\dvisvgm.exe"),
  (Join-Path $tinyTeXStageRoot "bin\windows\dvipng.exe")
)
$missingTinyTeXPaths = @($requiredTinyTeXPaths | Where-Object { -not (Test-Path $_) })
if ($missingTinyTeXPaths.Count -gt 0) {
  throw "Required TinyTeX runtime files were not staged: $($missingTinyTeXPaths -join ', ')"
}

# List the themes actually staged, with the commit each was built from
# (the manifest's themeInputs), so the file can't drift from the payload.
$manifest = Get-Content -Raw "packaging\manifests\windows-msi.manifest.json" | ConvertFrom-Json
$stagedThemes = @(Get-ChildItem -Path (Join-Path $runtimeRoot "lib\GNUstep\Themes") -Directory -Filter "*.theme" -ErrorAction SilentlyContinue | Sort-Object Name)
if ($stagedThemes.Count -eq 0) {
  throw "No GNUstep theme was staged under runtime\lib\GNUstep\Themes."
}
$themeLines = foreach ($theme in $stagedThemes) {
  $name = [System.IO.Path]::GetFileNameWithoutExtension($theme.Name)
  $themeInput = @($manifest.themeInputs | Where-Object { $_.name -eq $name })[0]
  if ($themeInput) {
    "{0} {1} ({2})" -f $name, $themeInput.ref, $themeInput.repo
  } else {
    "{0} (not in themeInputs)" -f $name
  }
}
Set-Content -Path (Join-Path $metadataDocs "BundledThemes.txt") -Value (@(
  "Bundled GNUstep themes for ObjcMarkdown MSI:"
) + $themeLines + @(
  ("Packaged Windows launches default to GSTheme={0} when the user has not already chosen a theme." -f $manifest.packagedDefaults.defaultTheme)
))
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
