param(
  [Parameter(Mandatory=$true)]
  [string]$StagingDir,
  [Parameter(Mandatory=$true)]
  [string]$Version,
  [Parameter(Mandatory=$true)]
  [string]$OutDir
)

$ErrorActionPreference = "Stop"

$StagingDir = (Resolve-Path $StagingDir).Path
$OutDir = (Resolve-Path $OutDir).Path
$RepoRoot = (Resolve-Path "$PSScriptRoot/../.." ).Path

$installerDir = Join-Path $RepoRoot "installer"
$appFilesWxs = Join-Path $installerDir "ObjcMarkdownAppFiles.wxs"
$runtimeFilesWxs = Join-Path $installerDir "ObjcMarkdownRuntimeFiles.wxs"
$productWxs = Join-Path $installerDir "ObjcMarkdown.wxs"

$wixRoot = Join-Path $RepoRoot "tools/wix"
$heat = (Get-Command heat.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source
$candle = (Get-Command candle.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source
$light = (Get-Command light.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source

if (-not $heat -and (Test-Path (Join-Path $wixRoot "heat.exe"))) {
  $heat = Join-Path $wixRoot "heat.exe"
}
if (-not $candle -and (Test-Path (Join-Path $wixRoot "candle.exe"))) {
  $candle = Join-Path $wixRoot "candle.exe"
}
if (-not $light -and (Test-Path (Join-Path $wixRoot "light.exe"))) {
  $light = Join-Path $wixRoot "light.exe"
}

if (-not $heat -or -not $candle -or -not $light) {
  throw "WiX tools not found. Install WiX or place binaries under $wixRoot."
}

function Normalize-Version([string]$inputVersion) {
  $parts = $inputVersion.Split(".") | Where-Object { $_ -ne "" }
  if ($parts.Count -lt 3) {
    while ($parts.Count -lt 3) { $parts += "0" }
  }
  if ($parts.Count -eq 3) { $parts += "0" }
  if ($parts.Count -gt 4) { $parts = $parts[0..3] }
  return ($parts -join ".")
}

$normalizedVersion = Normalize-Version $Version

if (-not (Test-Path $StagingDir)) {
  throw "Staging directory not found: $StagingDir"
}

if (-not (Test-Path $productWxs)) {
  throw "Missing WiX template: $productWxs"
}

$appStage = Join-Path $StagingDir "_app_stage"
$runtimeStage = Join-Path $StagingDir "clang64"

if (-not (Test-Path $runtimeStage)) {
  throw "Runtime staging directory not found: $runtimeStage"
}

Remove-Item -Recurse -Force $appStage -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $appStage | Out-Null
Copy-Item -Force (Join-Path $StagingDir "MarkdownViewer.cmd") $appStage
Copy-Item -Recurse -Force (Join-Path $StagingDir "app") $appStage

Write-Host "Harvesting files from $StagingDir"
& $heat dir $appStage -cg AppFiles -dr INSTALLDIR -srd -sreg -sfrag -gg -g1 -var var.AppSourceDir -out $appFilesWxs
& $heat dir $runtimeStage -cg RuntimeFiles -dr CLANG64DIR -srd -sreg -sfrag -gg -g1 -var var.RuntimeSourceDir -out $runtimeFilesWxs

Write-Host "Compiling WiX sources"
& $candle @("-dAppSourceDir=$appStage", "-dRuntimeSourceDir=$runtimeStage", "-dProductVersion=$normalizedVersion", "-out", (Join-Path $installerDir ""), $productWxs, $appFilesWxs, $runtimeFilesWxs)

Write-Host "Linking MSI"
$msiName = "ObjcMarkdown-$normalizedVersion-win64.msi"
& $light @("-ext", "WixUIExtension", "-out", (Join-Path $OutDir $msiName), (Join-Path $installerDir "ObjcMarkdown.wixobj"), (Join-Path $installerDir "ObjcMarkdownAppFiles.wixobj"), (Join-Path $installerDir "ObjcMarkdownRuntimeFiles.wixobj"))

Write-Host "MSI created at $OutDir\$msiName"
