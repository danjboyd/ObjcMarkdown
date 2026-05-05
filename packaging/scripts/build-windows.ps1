[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Copy-OmdDependencyFiles {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDirectory,
    [Parameter(Mandatory = $true)]
    [string]$DestinationDirectory,
    [Parameter(Mandatory = $true)]
    [string[]]$Patterns
  )

  if (-not (Test-Path $SourceDirectory)) {
    return
  }

  New-Item -ItemType Directory -Force -Path $DestinationDirectory | Out-Null
  foreach ($pattern in $Patterns) {
    foreach ($file in @(Get-ChildItem -LiteralPath $SourceDirectory -Filter $pattern -File -ErrorAction SilentlyContinue)) {
      Copy-Item -LiteralPath $file.FullName -Destination $DestinationDirectory -Force
    }
  }
}

function Sync-OmdManagedCmarkDependency {
  if ([string]::IsNullOrWhiteSpace($env:MSYS2_LOCATION) -or [string]::IsNullOrWhiteSpace($env:GP_GNUSTEP_CLI_ROOT)) {
    return
  }

  $sourceRoot = [System.IO.Path]::GetFullPath((Join-Path $env:MSYS2_LOCATION "clang64"))
  $destinationRoot = [System.IO.Path]::GetFullPath((Join-Path $env:GP_GNUSTEP_CLI_ROOT "clang64"))
  if ($sourceRoot -eq $destinationRoot -or -not (Test-Path $sourceRoot) -or -not (Test-Path $destinationRoot)) {
    return
  }

  Copy-OmdDependencyFiles `
    -SourceDirectory (Join-Path $sourceRoot "include") `
    -DestinationDirectory (Join-Path $destinationRoot "include") `
    -Patterns @("cmark*.h")
  Copy-OmdDependencyFiles `
    -SourceDirectory (Join-Path $sourceRoot "lib") `
    -DestinationDirectory (Join-Path $destinationRoot "lib") `
    -Patterns @("libcmark*")
  Copy-OmdDependencyFiles `
    -SourceDirectory (Join-Path $sourceRoot "lib\pkgconfig") `
    -DestinationDirectory (Join-Path $destinationRoot "lib\pkgconfig") `
    -Patterns @("libcmark*.pc", "cmark*.pc")
  Copy-OmdDependencyFiles `
    -SourceDirectory (Join-Path $sourceRoot "bin") `
    -DestinationDirectory (Join-Path $destinationRoot "bin") `
    -Patterns @("libcmark*.dll", "cmark*.dll")
}

Sync-OmdManagedCmarkDependency

& .\packaging\scripts\ensure-windows-theme-inputs.ps1 | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "ObjcMarkdown Windows theme preparation failed."
}

& .\scripts\windows\build-from-powershell.ps1 -Task command -Command "make OMD_SKIP_TESTS=1"
if ($LASTEXITCODE -ne 0) {
  throw "ObjcMarkdown Windows build failed."
}
