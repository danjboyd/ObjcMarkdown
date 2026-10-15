[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$TinyTeXRoot
)

# Trims a staged TinyTeX to what math rendering runs: latex (pdfTeX, DVI),
# dvisvgm and dvipng, with the article class, amsmath and the Computer Modern
# and AMS fonts (#127). The full tree stays in the vendor cache, where
# ensure-tinytex-runtime.ps1 uses tlmgr; only the staged copy is trimmed.
# A formula smoke on the trimmed tree checks that nothing it needs went.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = [System.IO.Path]::GetFullPath($TinyTeXRoot)
$bin = Join-Path $root "bin\windows"

function Get-OmdTreeBytes([string]$Path) {
  $sum = (Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
  if ($sum) { [long]$sum } else { [long]0 }
}

function Remove-OmdTinyTeXPath([string]$RelativePath) {
  $path = Join-Path $root $RelativePath
  if (Test-Path -LiteralPath $path) {
    Remove-Item -LiteralPath $path -Recurse -Force
  }
}

$before = Get-OmdTreeBytes $root

# bin/windows: the three tools the renderer runs, plain tex (its fallback),
# kpsewhich, and the DLLs they import (llvm-objdump -p closure of these
# executables in TinyTeX 2026.04). The smoke below fails the build if a
# newer TinyTeX needs another one.
$keepBin = @(
  "latex.exe", "pdftex.exe", "pdftex.dll",
  "tex.exe", "tex.dll",
  "dvisvgm.exe", "dvipng.exe",
  "kpsewhich.exe", "kpathsealibw64.dll",
  "msvcr100.dll"
)
Get-ChildItem -LiteralPath $bin -File -Force | Where-Object { $keepBin -notcontains $_.Name.ToLowerInvariant() } | Remove-Item -Force

# tlmgr's Perl, Ghostscript (dvisvgm --no-fonts reads Type 1 fonts; it needs
# Ghostscript only for PostScript specials, which our formulas don't have),
# the package database and the installer: build time only.
Remove-OmdTinyTeXPath "tlpkg"
Remove-OmdTinyTeXPath "tl-tray-menu.exe"

# Formats and macros of the engines we don't run.
foreach ($engine in @("luatex", "luahbtex", "xetex", "metafont")) {
  Remove-OmdTinyTeXPath "texmf-var\web2c\$engine"
}
Remove-OmdTinyTeXPath "texmf-var\fonts\cache"
foreach ($dir in @("luatex", "lualatex", "xetex", "xelatex")) {
  Remove-OmdTinyTeXPath "texmf-dist\tex\$dir"
}
foreach ($dir in @("scripts", "bibtex", "doc", "source", "texconfig", "mft")) {
  Remove-OmdTinyTeXPath "texmf-dist\$dir"
}

# Fonts: pdfTeX's DVI output with OT1 Computer Modern and the AMS fonts.
# AFM and OpenType files are never read by latex, dvisvgm or dvipng; Latin
# Modern, TIPA and the URW/Adobe text fonts aren't used by the preamble.
foreach ($dir in @("afm", "opentype", "truetype", "source")) {
  Remove-OmdTinyTeXPath "texmf-dist\fonts\$dir"
}
foreach ($family in @("public\lm", "public\tipa", "public\inconsolata", "urw")) {
  Remove-OmdTinyTeXPath "texmf-dist\fonts\type1\$family"
}
foreach ($family in @("public\lm", "public\tipa", "public\inconsolata", "urw35vf", "adobe", "monotype")) {
  Remove-OmdTinyTeXPath "texmf-dist\fonts\tfm\$family"
  Remove-OmdTinyTeXPath "texmf-dist\fonts\vf\$family"
}

$after = Get-OmdTreeBytes $root
Write-Host ("TinyTeX trimmed: {0:N1} MB -> {1:N1} MB" -f ($before / 1MB), ($after / 1MB))

# Smoke: inline, display, matrix, text, bold and calligraphic math through
# each tool, as the renderer runs them.
$smokeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("omd-tinytex-trim-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $smokeDir | Out-Null
$formulas = @(
  '$e^{i\pi} + 1 = 0$ and $\sqrt{a^2+b^2}$',
  '\[ \int_0^1 x^2\,dx = \frac{1}{3}, \quad \sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6} \]',
  '\[ \begin{pmatrix} a & b \\ c & d \end{pmatrix} \begin{bmatrix} 1 \\ 0 \end{bmatrix} \]',
  '\[ f(x) = \begin{cases} 0 & \text{if } x < 0 \\ \boldsymbol{x} & \text{otherwise} \end{cases} \]',
  '\[ \mathcal{L}\{f\}(s) = \int_0^\infty e^{-st} f(t)\,dt, \quad \mathbf{A}\vec{v} = \lambda \vec{v}, \quad \mathrm{d}\Gamma \le \aleph_0 \]',
  '\begin{align} a &= b + c \\ \nabla \cdot \mathbf{E} &= \frac{\rho}{\varepsilon_0} \end{align}'
)
$originalPath = $env:PATH
$env:PATH = "$bin;$originalPath"
Push-Location $smokeDir
try {
  for ($i = 0; $i -lt $formulas.Count; $i++) {
    $name = "f$i"
    Set-Content -Path "$name.tex" -Encoding Ascii -Value @(
      '\documentclass{article}', '\usepackage{amsmath}', '\pagestyle{empty}', '\begin{document}',
      $formulas[$i], '\end{document}')
    & (Join-Path $bin "latex.exe") "-interaction=nonstopmode" "-halt-on-error" "$name.tex" | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path "$name.dvi")) {
      $log = if (Test-Path "$name.log") { (Get-Content "$name.log" | Select-Object -Last 15) -join [Environment]::NewLine } else { "" }
      throw "Trimmed TinyTeX: latex failed on formula $i (exit $LASTEXITCODE).$([Environment]::NewLine)$log"
    }
    $svg = @(& (Join-Path $bin "dvisvgm.exe") "--no-fonts" "--exact-bbox" "--stdout" "$name.dvi" 2>&1)
    if ($LASTEXITCODE -ne 0 -or -not (($svg -join "`n") -match '<path')) {
      throw "Trimmed TinyTeX: dvisvgm failed on formula $i (exit $LASTEXITCODE).$([Environment]::NewLine)$(($svg | Select-Object -Last 10) -join [Environment]::NewLine)"
    }
    # LaTeX's dvips backend writes a PostScript special that dvisvgm ignores
    # without Ghostscript; the SVG is byte-identical to the full TinyTeX's.
    $warnings = @($svg | Where-Object { $_ -match 'font file .* not found|mktexpk|can.t find|WARNING' -and $_ -notmatch 'PostScript special.? ignored|might\s*$|look wrong' })
    if ($warnings.Count -gt 0) {
      throw "Trimmed TinyTeX: dvisvgm warned on formula $i.$([Environment]::NewLine)$($warnings -join [Environment]::NewLine)"
    }
    $png = @(& (Join-Path $bin "dvipng.exe") "-T" "tight" "-bg" "Transparent" "-D" "180" "-o" "$name.png" "$name.dvi" 2>&1)
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path "$name.png") -or (Get-Item "$name.png").Length -le 0) {
      throw "Trimmed TinyTeX: dvipng failed on formula $i (exit $LASTEXITCODE).$([Environment]::NewLine)$($png -join [Environment]::NewLine)"
    }
    $warnings = @($png | Where-Object { $_ -match 'warning|not found|mktexpk' })
    if ($warnings.Count -gt 0) {
      throw "Trimmed TinyTeX: dvipng warned on formula $i.$([Environment]::NewLine)$($warnings -join [Environment]::NewLine)"
    }
  }
} finally {
  Pop-Location
  $env:PATH = $originalPath
  Remove-Item -LiteralPath $smokeDir -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "Trimmed TinyTeX smoke passed ($($formulas.Count) formulas)."
