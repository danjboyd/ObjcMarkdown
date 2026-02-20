# Open Issues

## 2) Feasibility: Full WYSIWYG Markdown editor

- **Status**: Open
- **Opened On**: 2026-02-13
- **Area**: Viewer / Editor architecture / Markdown round-trip
- **Description**: Evaluate and plan implementation of a full WYSIWYG Markdown editor where visual edits reliably serialize back to Markdown without destructive rewrites.
- **Current State**:
  - Viewer text surface is read-only.
  - Rendering pipeline remains one-way (`markdown -> NSAttributedString`) with no general attributed-edit-to-Markdown serializer.
- **Feasibility Assessment**:
  - Estimated difficulty: high (roughly 8/10).
  - Expected effort: multi-month for robust full-fidelity WYSIWYG.
- **Notes**:
  - Keep this as a subsequent phase after hybrid editor hardening.

## 4) Phase-2 renderer syntax-highlighting architecture (language breadth)

- **Status**: Open
- **Opened On**: 2026-02-16
- **Area**: Renderer / Syntax highlighting / Dependency strategy
- **Description**: Decide long-term architecture for multi-language renderer highlighting beyond phase-1 heuristics.
- **Current State**:
  - Phase-1 renderer syntax highlighting is shipped with Tree-sitter availability gating.
- **Open Questions**:
  - Bespoke tokenizer expansion vs deeper Tree-sitter parser integration per language.
  - Packaging/runtime behavior when Tree-sitter libraries or grammars are unavailable.
  - Performance and fallback UX expectations at large document sizes.
- **Notes**:
  - Treat as post-phase-1 follow-on work, not a blocker for current stabilization.

## 5) Inline HTML rendering support (deferred to Phase 2)

- **Status**: Open
- **Opened On**: 2026-02-18
- **Area**: Renderer / HTML policy / Preview fidelity
- **Description**: Inline and block HTML are currently handled as literal text (or dropped via policy), not rendered as rich HTML in preview.
- **Current State**:
  - Default parsing policy is `RenderAsText` for inline and block HTML.
  - HTML import/export is supported through Pandoc when available.
- **Planned Work**:
  - Design a safe rendering strategy for inline/block HTML (likely constrained subset + sanitization).
  - Define fallback behavior when markup is unsupported.
  - Add dedicated renderer tests for allowed/blocked HTML rendering paths.
- **Notes**:
  - Explicitly scheduled for Phase 2 work in `Roadmap.md`.

## 7) Automated Windows MSI packaging pipeline (GNUstep runtime included)

- **Status**: Open
- **Opened On**: 2026-02-19
- **Area**: Release engineering / Windows packaging / CI-CD
- **Description**: Build automated GitHub pipelines that produce a usable Windows MSI for the MSYS2/clang GNUstep build, including all required runtime components.
- **Current State**:
  - Windows builds run locally in MSYS2 `clang64`.
  - MSI/ZIP packaging scripts and GitHub Actions workflow are implemented.
  - MSI bundles the app plus GNUstep runtime under `C:\clang64` and ships a launcher that sets `PATH`.
  - Local MSI build validated; CI run + clean VM install validation pending.
- **Requirements**:
  - Generate MSI artifacts from GitHub Actions on tagged releases (and optionally on `main` as pre-release builds).
  - Bundle app binaries plus required runtime libraries (including GNUstep base/gui/back and dependent DLLs such as cmark, dispatch, OpenSave, TextViewVimKit, and Objective-C runtime dependencies).
  - Install/start menu shortcuts and uninstall entry should be included.
  - Validate clean-install launch on a fresh Windows environment (no preinstalled GNUstep/MSYS2).
- **Notes**:
  - Prefer reproducible packaging with explicit dependency manifests and versioned artifacts.
  - **Pending (post-reboot)**:
    - Enable Windows Sandbox (requires admin + reboot): `Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All -NoRestart`
    - Reboot Windows.
    - Confirm feature state: `Get-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM | Select-Object State`
    - Create/run a Sandbox config for MSI testing (map `dist/`).
    - Validate clean install + launch inside Sandbox; record any missing dependencies.

### 2026-02-20 Sandbox Test Result

- **Installer**: `ObjcMarkdown-0.0.0.0-win64.msi`
- **Environment**: Windows Sandbox (clean VM)
- **Result**: App failed to launch due to missing runtime DLL.
- **Error**: `MarkdownViewer.exe - System Error` → `The code execution cannot proceed because ucrtbased.dll was not found. Reinstalling the program may fix this problem.`
- **Implication**: MSI appears to be packaging a debug CRT dependency (`ucrtbased.dll`). Switch to release CRT, or bundle required runtime / installer prerequisites.

### 2026-02-20 Rebuild Status

- **Rebuilt Installer**: `dist/buildout/ObjcMarkdown-0.0.0.2-win64.msi`
- **Build Path**: MSYS2 via `C:\msys64\usr\bin\bash.exe` from WSL
- **Result**: Runtime staging now includes release `libffi-8.dll` (no `ucrtbased.dll` / `VCRUNTIME140D.dll` imports detected).
- **Follow-up**: Re-run clean Windows Sandbox install/launch validation against `0.0.0.2` MSI and confirm issue closure.

### 2026-02-20 End-of-Day Status

- **Status**: Still in progress.
- **Installer State**: MSI install/reconfigure completes successfully in Windows Sandbox (`MainEngineThread` returned `0`).
- **Launch State**:
  - Initial missing-DLL popup (`ObjcMarkdown-0.dll`) no longer blocks when using the packaged launcher path.
  - App launch from `MarkdownViewer.cmd` is currently exiting silently (no UI shown, no nonzero exit code surfaced in `cmd.exe`).
  - Forcing `GSTheme=WinUXTheme` did not change behavior.
- **Next Session Focus**:
  - Add explicit launcher/runtime diagnostics (stdout/stderr + GNUstep env dump).
  - Verify GNUstep backend/theme initialization in plain Windows `cmd.exe` context.
  - Re-test in Sandbox after launcher/environment fixes.
