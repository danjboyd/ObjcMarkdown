param(
  [Parameter(Mandatory=$true)]
  [string]$MsiPath,
  [string]$InstallDir = "C:\Program Files\ObjcMarkdown",
  [string]$LogDir = "C:\temp\omd-logs",
  [switch]$RunSmoke
)

$ErrorActionPreference = "Stop"

function Get-OmdProcessesByExecutablePath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ExecutablePath
  )

  $expectedPath = [System.IO.Path]::GetFullPath($ExecutablePath)
  $processName = [System.IO.Path]::GetFileNameWithoutExtension($expectedPath)
  $matches = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()

  foreach ($process in @(Get-Process -Name $processName -ErrorAction SilentlyContinue)) {
    try {
      if ([string]::IsNullOrWhiteSpace([string]$process.Path)) {
        continue
      }

      $actualPath = [System.IO.Path]::GetFullPath([string]$process.Path)
      if ([string]::Equals($actualPath, $expectedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        $matches.Add($process) | Out-Null
      }
    } catch {
      continue
    }
  }

  return @($matches.ToArray())
}

function Test-OmdBundledTinyTeXRuntime {
  param(
    [Parameter(Mandatory = $true)]
    [string]$TeXBinDir
  )

  $latexPath = Join-Path $TeXBinDir "latex.exe"
  $dvisvgmPath = Join-Path $TeXBinDir "dvisvgm.exe"
  $dvipngPath = Join-Path $TeXBinDir "dvipng.exe"
  $smokeDir = Join-Path $env:TEMP "omd-tinytex-smoke"
  $formulaPath = Join-Path $smokeDir "formula.tex"
  $dviPath = Join-Path $smokeDir "formula.dvi"
  $svgPath = Join-Path $smokeDir "formula.svg"
  $pngPath = Join-Path $smokeDir "formula.png"

  if (Test-Path $smokeDir) {
    Remove-Item -LiteralPath $smokeDir -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $smokeDir | Out-Null

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
    $env:PATH = "$TeXBinDir;$originalPath"

    Push-Location $smokeDir
    try {
      & $latexPath "-interaction=nonstopmode" "-halt-on-error" "formula.tex" | Out-Null
      if ($LASTEXITCODE -ne 0) {
        throw "Bundled TinyTeX latex smoke compile failed with exit code $LASTEXITCODE."
      }

      if (-not (Test-Path $dviPath)) {
        throw "Bundled TinyTeX latex smoke compile did not produce formula.dvi."
      }

      & $dvisvgmPath "--no-fonts" "--exact-bbox" "--stdout" "formula.dvi" > $svgPath
      if ($LASTEXITCODE -ne 0) {
        throw "Bundled TinyTeX dvisvgm smoke conversion failed with exit code $LASTEXITCODE."
      }

      & $dvipngPath "-T" "tight" "-bg" "Transparent" "-D" "180" "-o" "formula.png" "formula.dvi" | Out-Null
      if ($LASTEXITCODE -ne 0) {
        throw "Bundled TinyTeX dvipng smoke conversion failed with exit code $LASTEXITCODE."
      }
    } finally {
      Pop-Location
    }
  } finally {
    $env:PATH = $originalPath
  }

  if (-not (Test-Path $svgPath)) {
    throw "Bundled TinyTeX dvisvgm smoke conversion did not produce formula.svg."
  }

  $svgInfo = Get-Item -LiteralPath $svgPath
  if ($svgInfo.Length -le 0) {
    throw "Bundled TinyTeX dvisvgm smoke conversion produced an empty formula.svg."
  }

  if (-not (Test-Path $pngPath)) {
    throw "Bundled TinyTeX dvipng smoke conversion did not produce formula.png."
  }

  $pngInfo = Get-Item -LiteralPath $pngPath
  if ($pngInfo.Length -le 0) {
    throw "Bundled TinyTeX dvipng smoke conversion produced an empty formula.png."
  }

  Remove-Item -LiteralPath $smokeDir -Recurse -Force
}

if (-not (Test-Path $MsiPath)) {
  throw "MSI not found at $MsiPath"
}

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$installLog = Join-Path $LogDir "install.log"
$uninstallLog = Join-Path $LogDir "uninstall.log"
$installCompleted = $false
$validationError = $null
$uninstallError = $null

try {
  Write-Host "Installing MSI: $MsiPath"
  $installProcess = Start-Process msiexec.exe -Wait -PassThru -ArgumentList "/i", $MsiPath, "/qn", "/norestart", "/l*v", $installLog
  if ($installProcess.ExitCode -ne 0) {
    throw "MSI install failed with exit code $($installProcess.ExitCode)"
  }

  $installCompleted = $true

  $installCandidates = @(
    $InstallDir,
    (Join-Path $env:LOCALAPPDATA "ObjcMarkdown"),
    "C:\Program Files\ObjcMarkdown",
    "C:\Program Files (x86)\ObjcMarkdown"
  ) | Select-Object -Unique

  $resolvedInstallDir = $installCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $resolvedInstallDir) {
    throw "Expected install root not found in any of: $($installCandidates -join ', ')"
  }
  $InstallDir = $resolvedInstallDir
  Write-Host "Resolved install root: $InstallDir"

  $launcherPath = Join-Path $InstallDir "MarkdownViewer.exe"
  if (-not (Test-Path $launcherPath)) {
    throw "Expected app launcher not found: $launcherPath"
  }

  $appPath = Join-Path $InstallDir "app\MarkdownViewer.app\MarkdownViewer.exe"
  if (-not (Test-Path $appPath)) {
    throw "Expected packaged app executable not found: $appPath"
  }

  $runtimeCandidates = @(
    (Join-Path $InstallDir "clang64\\bin"),
    "C:\clang64\bin"
  )
  $runtimeBin = $runtimeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $runtimeBin) {
    throw "Expected runtime not found in any of: $($runtimeCandidates -join ', ')"
  }

  $requiredThemePaths = @(
    (Join-Path $InstallDir "clang64\\lib\\GNUstep\\Themes\\WinUXTheme.theme\\WinUXTheme.dll"),
    (Join-Path $InstallDir "clang64\\lib\\GNUstep\\Themes\\Win11Theme.theme\\Win11Theme.dll"),
    (Join-Path $InstallDir "clang64\\lib\\GNUstep\\Themes\\WinUITheme.theme\\WinUITheme.dll")
  )
  $missingThemePaths = @($requiredThemePaths | Where-Object { -not (Test-Path $_) })
  if ($missingThemePaths.Count -gt 0) {
    throw "Expected bundled themes were not found: $($missingThemePaths -join ', ')"
  }

  $bundledTeXBin = Join-Path $InstallDir "clang64\\texlive\\TinyTeX\\bin\\windows"
  $requiredTeXPaths = @(
    (Join-Path $bundledTeXBin "latex.exe"),
    (Join-Path $bundledTeXBin "dvisvgm.exe"),
    (Join-Path $bundledTeXBin "dvipng.exe")
  )
  $missingTeXPaths = @($requiredTeXPaths | Where-Object { -not (Test-Path $_) })
  if ($missingTeXPaths.Count -gt 0) {
    throw "Expected bundled TinyTeX runtime files were not found: $($missingTeXPaths -join ', ')"
  }

  Test-OmdBundledTinyTeXRuntime -TeXBinDir $bundledTeXBin

  if ($RunSmoke) {
    Write-Host "Running smoke test"
    $smokeFile = Join-Path $env:TEMP "omd-smoke.md"
    $probeDeadline = (Get-Date).AddSeconds(10)
    $childProcesses = @()

    Set-Content -Path $smokeFile -Value "# Smoke Test`n`nOK"
    $proc = Start-Process $launcherPath -ArgumentList $smokeFile -PassThru -WorkingDirectory $InstallDir

    do {
      Start-Sleep -Milliseconds 500
      $proc.Refresh()
      $childProcesses = @(Get-OmdProcessesByExecutablePath -ExecutablePath $appPath)
    } while (((-not $proc.HasExited) -or $childProcesses.Count -eq 0) -and (Get-Date) -lt $probeDeadline)

    $proc.Refresh()
    if (-not $proc.HasExited) {
      try {
        $proc | Stop-Process -Force
      } catch {
      }
      throw "Smoke launcher did not exit within the probe window: $launcherPath"
    }

    if ($proc.ExitCode -ne 0) {
      throw "Smoke launcher exited with code $($proc.ExitCode): $launcherPath"
    }

    $childProcesses = @(Get-OmdProcessesByExecutablePath -ExecutablePath $appPath)
    if ($childProcesses.Count -eq 0) {
      throw "Smoke launch did not leave the packaged app running: $appPath"
    }

    foreach ($child in $childProcesses) {
      try {
        $child | Stop-Process -Force
      } catch {
      }
    }
  }
} catch {
  $validationError = $_
} finally {
  if ($installCompleted) {
    try {
      Write-Host "Uninstalling MSI: $MsiPath"
      $uninstallProcess = Start-Process msiexec.exe -Wait -PassThru -ArgumentList "/x", $MsiPath, "/qn", "/norestart", "/l*v", $uninstallLog
      if ($uninstallProcess.ExitCode -ne 0) {
        throw "MSI uninstall failed with exit code $($uninstallProcess.ExitCode)"
      }
    } catch {
      $uninstallError = $_
    }
  }
}

if ($validationError -and $uninstallError) {
  throw "Remote MSI validation failed: $($validationError.Exception.Message) Additionally, uninstall failed: $($uninstallError.Exception.Message)"
}
if ($validationError) {
  throw $validationError
}
if ($uninstallError) {
  throw $uninstallError
}
