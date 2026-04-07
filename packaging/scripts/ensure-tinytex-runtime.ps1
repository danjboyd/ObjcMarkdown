[CmdletBinding()]
param(
  [string]$CacheRoot = "dist/vendor-cache",
  [string]$ReleaseTag = $(if (-not [string]::IsNullOrWhiteSpace($env:OMD_TINYTEX_RELEASE_TAG)) {
      $env:OMD_TINYTEX_RELEASE_TAG
    } else {
      "v2026.04"
    }),
  [string]$AssetName = $(if (-not [string]::IsNullOrWhiteSpace($env:OMD_TINYTEX_ASSET_NAME)) {
      $env:OMD_TINYTEX_ASSET_NAME
    } else {
      ""
    }),
  [string]$DownloadUrl = $(if (-not [string]::IsNullOrWhiteSpace($env:OMD_TINYTEX_DOWNLOAD_URL)) {
      $env:OMD_TINYTEX_DOWNLOAD_URL
    } else {
      $null
    }),
  [switch]$ForceRefresh
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-OmdFullPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }

  return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Path))
}

function Invoke-OmdTinyTeXFormulaSmoke {
  param(
    [Parameter(Mandatory = $true)]
    [string]$TinyTeXRoot,
    [Parameter(Mandatory = $true)]
    [string]$BinRoot,
    [Parameter(Mandatory = $true)]
    [string]$LatexPath,
    [Parameter(Mandatory = $true)]
    [string]$DvisvgmPath,
    [Parameter(Mandatory = $true)]
    [string]$DvipngPath
  )

  $smokeDir = Join-Path $TinyTeXRoot ".omd-smoke"
  if (Test-Path $smokeDir) {
    Remove-Item -LiteralPath $smokeDir -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $smokeDir | Out-Null

  $formulaPath = Join-Path $smokeDir "formula.tex"
  $dviPath = Join-Path $smokeDir "formula.dvi"
  $svgPath = Join-Path $smokeDir "formula.svg"
  $pngPath = Join-Path $smokeDir "formula.png"
  Set-Content -Path $formulaPath -Encoding Ascii -Value @'
\documentclass{article}
\usepackage{amsmath}
\pagestyle{empty}
\begin{document}
\[
\int_0^1 x^2\,dx
\]
\end{document}
'@

  $originalPath = $env:PATH
  try {
    $env:PATH = "$BinRoot;$originalPath"

    Push-Location $smokeDir
    try {
      & $LatexPath "-interaction=nonstopmode" "-halt-on-error" "formula.tex" | Out-Null
      if ($LASTEXITCODE -ne 0) {
        throw "TinyTeX latex smoke compile failed with exit code $LASTEXITCODE."
      }

      if (-not (Test-Path $dviPath)) {
        throw "TinyTeX latex smoke compile did not produce formula.dvi."
      }

      & $DvisvgmPath "--no-fonts" "--exact-bbox" "--stdout" "formula.dvi" > $svgPath
      if ($LASTEXITCODE -ne 0) {
        throw "TinyTeX dvisvgm smoke conversion failed with exit code $LASTEXITCODE."
      }

      & $DvipngPath "-T" "tight" "-bg" "Transparent" "-D" "180" "-o" "formula.png" "formula.dvi" | Out-Null
      if ($LASTEXITCODE -ne 0) {
        throw "TinyTeX dvipng smoke conversion failed with exit code $LASTEXITCODE."
      }
    } finally {
      Pop-Location
    }
  } finally {
    $env:PATH = $originalPath
  }

  if (-not (Test-Path $svgPath)) {
    throw "TinyTeX dvisvgm smoke conversion did not produce formula.svg."
  }

  $svgInfo = Get-Item -LiteralPath $svgPath
  if ($svgInfo.Length -le 0) {
    throw "TinyTeX dvisvgm smoke conversion produced an empty formula.svg."
  }

  if (-not (Test-Path $pngPath)) {
    throw "TinyTeX dvipng smoke conversion did not produce formula.png."
  }

  $pngInfo = Get-Item -LiteralPath $pngPath
  if ($pngInfo.Length -le 0) {
    throw "TinyTeX dvipng smoke conversion produced an empty formula.png."
  }

  Remove-Item -LiteralPath $smokeDir -Recurse -Force
}

$resolvedCacheRoot = Resolve-OmdFullPath -Path $CacheRoot
New-Item -ItemType Directory -Force -Path $resolvedCacheRoot | Out-Null

if ([string]::IsNullOrWhiteSpace($AssetName)) {
  $AssetName = "TinyTeX-1-windows-$ReleaseTag.exe"
}

if ([string]::IsNullOrWhiteSpace($DownloadUrl)) {
  $DownloadUrl = "https://github.com/rstudio/tinytex-releases/releases/download/$ReleaseTag/$AssetName"
}

$installerPath = Join-Path $resolvedCacheRoot $AssetName
$extractRoot = Join-Path $resolvedCacheRoot ([System.IO.Path]::GetFileNameWithoutExtension($AssetName))
$tinyTeXRoot = Join-Path $extractRoot "TinyTeX"
$tinyTeXBin = Join-Path $tinyTeXRoot "bin\\windows"
$latexPath = Join-Path $tinyTeXBin "latex.exe"
$dvisvgmPath = Join-Path $tinyTeXBin "dvisvgm.exe"
$dvipngPath = Join-Path $tinyTeXBin "dvipng.exe"
$tlmgrPath = Join-Path $tinyTeXBin "tlmgr.bat"
$validationStamp = Join-Path $extractRoot ".omd-tinytex-validated"

if ($ForceRefresh) {
  if (Test-Path $extractRoot) {
    Remove-Item -LiteralPath $extractRoot -Recurse -Force
  }
  if (Test-Path $installerPath) {
    Remove-Item -LiteralPath $installerPath -Force
  }
}

if (-not (Test-Path $installerPath)) {
  Invoke-WebRequest -Uri $DownloadUrl -OutFile $installerPath
}

if (-not (Test-Path $tinyTeXRoot)) {
  if (Test-Path $extractRoot) {
    Remove-Item -LiteralPath $extractRoot -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null

  & $installerPath "-o$extractRoot" "-y" | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "TinyTeX extraction failed with exit code $LASTEXITCODE."
  }
}

if (-not (Test-Path $latexPath)) {
  throw "TinyTeX latex executable not found after extraction: $latexPath"
}

if (-not (Test-Path $dvisvgmPath)) {
  if (-not (Test-Path $tlmgrPath)) {
    throw "TinyTeX tlmgr not found and dvisvgm.exe is missing: $tlmgrPath"
  }

  Push-Location $tinyTeXRoot
  try {
    & $tlmgrPath "install" "dvisvgm.windows" | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw "TinyTeX tlmgr install dvisvgm.windows failed with exit code $LASTEXITCODE."
    }
  } finally {
    Pop-Location
  }
}

if (-not (Test-Path $dvisvgmPath)) {
  throw "TinyTeX dvisvgm executable not found after extraction: $dvisvgmPath"
}

if (-not (Test-Path $dvipngPath)) {
  if (-not (Test-Path $tlmgrPath)) {
    throw "TinyTeX tlmgr not found and dvipng.exe is missing: $tlmgrPath"
  }

  Push-Location $tinyTeXRoot
  try {
    & $tlmgrPath "install" "dvipng" | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw "TinyTeX tlmgr install dvipng failed with exit code $LASTEXITCODE."
    }
  } finally {
    Pop-Location
  }
}

if (-not (Test-Path $dvipngPath)) {
  throw "TinyTeX dvipng executable not found after extraction: $dvipngPath"
}

if ($ForceRefresh -or -not (Test-Path $validationStamp)) {
  Invoke-OmdTinyTeXFormulaSmoke `
    -TinyTeXRoot $tinyTeXRoot `
    -BinRoot $tinyTeXBin `
    -LatexPath $latexPath `
    -DvisvgmPath $dvisvgmPath `
    -DvipngPath $dvipngPath
  Set-Content -Path $validationStamp -Encoding Ascii -Value @(
    "ReleaseTag=$ReleaseTag"
    "AssetName=$AssetName"
    "DownloadUrl=$DownloadUrl"
    ("ValidatedAt={0:o}" -f (Get-Date))
  )
}

[pscustomobject]@{
  releaseTag = $ReleaseTag
  assetName = $AssetName
  downloadUrl = $DownloadUrl
  installerPath = $installerPath
  root = $tinyTeXRoot
  bin = $tinyTeXBin
  latexPath = $latexPath
  dvisvgmPath = $dvisvgmPath
  dvipngPath = $dvipngPath
  validationStamp = $validationStamp
}
