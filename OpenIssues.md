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

## 8) Investigate Sombre theme failure on Windows (feasibility + fix path)

- **Status**: Open
- **Opened On**: 2026-02-19
- **Area**: Windows runtime / GNUstep theming / Compatibility
- **Description**: Determine why `GSTheme=Sombre` does not produce a usable window on Windows and assess whether a practical fix is feasible.
- **Current State**:
  - Under Windows GNUstep + MSYS2, launching with Sombre can start the process but fail to present a normal main window.
  - Observed runtime exception during launch path under Sombre:
    - `NSInvalidArgumentException` with `NSConstantString ... forwardInvocation: ... hash`.
  - App remains usable under `WinUXTheme`, so issue appears theme/runtime specific rather than core app startup.
- **Investigation Goals**:
  - Reproduce in a minimal GNUstep app with and without Sombre to isolate theme plugin vs app interaction.
  - Identify whether failure is caused by Sombre plugin code, GNUstep backend incompatibility on Windows, or app-side assumptions.
  - Establish workaround options (theme fallback, selective feature disable) if full Sombre support is not feasible.
- **Notes**:
  - Outcome should include a go/no-go feasibility decision and recommended implementation path.

## 9) Automated Linux Flatpak packaging pipeline (GNUstep runtime included)

- **Status**: Open
- **Opened On**: 2026-02-19
- **Area**: Release engineering / Linux packaging / CI-CD
- **Description**: Build automated GitHub pipelines that produce a Flatpak for `MarkdownViewer` that runs on a stock Linux desktop without requiring users to manually install GNUstep or related runtime dependencies.
- **Current State**:
  - Linux builds run from source in a configured GNUstep development environment.
  - No Flatpak manifest or CI pipeline currently publishes installable Linux bundles.
  - Runtime tools/features that depend on external binaries (for example `pandoc`) are not bundled for end users.
- **Requirements**:
  - Create a Flatpak manifest and builder flow for `MarkdownViewer`.
  - Include all required runtime components for app startup and core features (GNUstep libs, Objective-C runtime, cmark, OpenSave/TextViewVimKit dependencies, and other required shared libraries).
  - Include `pandoc` (or an equivalent clearly documented strategy) so import/export features work on stock systems.
  - Add GitHub Actions workflow(s) to build, validate, and publish Flatpak artifacts (nightly and/or tagged releases).
  - Validate installation and launch on a clean Linux box with no preinstalled GNUstep toolchain.
- **Notes**:
  - Target reproducible builds with pinned versions and explicit dependency provenance.

## 10A) Adopt the `gnustep-cli-new` runner/toolchain contract in ObjcMarkdown packaging

- **Status**: Open
- **Opened On**: 2026-04-15
- **Area**: Release engineering / runner infrastructure / toolchain provisioning
- **Description**: The MSI/AppImage/GitHub runner process depends on having a reliable way to provision or validate the required GNUstep libraries and the correct clang-oriented toolchain flavor on disposable runners. `gnustep-packager` now uses `gnustep-cli-new` as the hosted runner bootstrap and smoke-validation path, so ObjcMarkdown needs to consume that contract instead of carrying ad hoc runner preparation.
- **Current State**:
  - `gnustep-packager` is the packaging boundary and owns the reusable MSI/AppImage workflows.
  - `gnustep-cli-new` now publishes the Linux and Windows artifacts consumed by the packager bootstrap path.
  - The ObjcMarkdown packaging workflows are pinned to the current packager integration commit, pass explicit packager checkout inputs, and use the hosted default bootstrap path.
  - Repo-local build/stage scripts now prefer `GNUSTEP_MAKEFILES`, `GP_GNUSTEP_CLI_ROOT`, `MSYS2_LOCATION`, and the active managed clang64 prefix before falling back to legacy local paths.
  - Hosted Linux AppImage packaging passed in GitHub Actions run `24743212445` on `2026-04-21`.
  - Hosted Windows MSI packaging is not yet proven because run `24743299242` remained in `Bootstrap And Smoke Test gnustep-cli-new For MSI` until canceled, with no live logs exposed by GitHub for that step.
  - Upstream `gnustep-packager` commit `3c10f1a2c8f976cc30aaaa4f85f6a14b74ebb562` now bounds the Windows bootstrap step, records stdout/stderr into diagnostics, terminates the bootstrap process tree on timeout, and smokes the generated Windows `HelloPackager.exe` directly until the public `gnustep-cli-new` Windows CLI artifact is refreshed.
  - Hosted Windows run `24746538617` proved the diagnostics path and isolated the stale published CLI artifact issue: setup/build succeeded, but the older `gnustep run` looked for `./obj/HelloPackager` instead of the built `HelloPackager.exe`.
  - Hosted Windows run `24747049925` passed the `gnustep-cli-new` MSI bootstrap and failed later in app packaging because `plugins-themes-winuitheme` was not present in the hosted workspace.
  - `ensure-windows-theme-inputs.ps1` now consumes `packaging/inputs.json` and fetches declared Windows git theme inputs into `.omd-theme-inputs` when hosted CI does not already have sibling theme checkouts.
  - Hosted Windows run `24747383333` passed bootstrap and fetched the required `plugins-themes-winuitheme` input, then failed inside app packaging while theme command output was still hidden by the repo-local build wrapper.
  - The Windows theme prep wrapper now leaves theme build output visible, skips optional theme fetches unless `OMD_FETCH_OPTIONAL_WINDOWS_THEME_INPUTS=1`, and exports the prepared GNUstep user theme root into both build and stage steps.
  - Hosted Windows run `24747752773` passed bootstrap and exposed the next app-side failure: the repo-local MSYS bridge converted `D:\...` paths to `/d/...` while running the managed `gnustep-cli-new` shell, so GNUstep makefiles and cloned theme paths were not found.
  - The Windows MSYS bridge now separates the GNUstep install root from the setup-msys2 shell root and asks the active shell's `cygpath` to translate Windows paths before invoking theme builds or app build/stage commands.
  - Hosted Windows run `24748075413` proved the converted `/d/...` workspace paths were now visible from setup-msys2, but GNUstep itself still expected an active `/clang64` root and the shell did not have `make` on `PATH`.
  - Hosted Windows run `24748308894` showed setup-msys2 already has its own `/clang64`, so the app bridge cannot treat `/clang64` as the managed payload path.
  - The Windows MSYS bridge now exports `GNUSTEP_MAKEFILES` to the managed `gnustep-cli-new` makefile path and prepends the managed `usr/bin` tools before invoking theme builds or app build/stage commands.
  - Hosted Windows run `24748570291` reached actual WinUITheme compilation and then failed because GNUstep make invoked its baked `/clang64/bin/clang` path instead of the managed compiler location.
  - The Windows MSYS bridge now exports `CC`, `OBJC_CC`, `CXX`, and `OBJCXX` to the managed clang/clang++ binaries before invoking theme builds or app build/stage commands.
- **Impact**:
  - Linux is aligned with the hosted packager/CLI boundary.
  - Windows now has a diagnosable hosted bootstrap path, and the next hosted run should expose any remaining app-side theme/build/stage failure directly in the uploaded build log.
- **Next Step**:
  - rerun hosted Windows MSI packaging through the normal reusable workflow path and review uploaded diagnostics or package artifacts

## 11) Windows MSI rebuild handoff after WinUITheme/default-theme work

- **Status**: Open
- **Opened On**: 2026-04-14
- **Area**: Release engineering / Windows packaging / `gnustep-packager` integration
- **Description**: Repo-local packaging changes now require the Windows MSI to bundle `WinUITheme` and default to `WinUITheme`, but the ad hoc OCI remote rebuild path has not yet produced a fresh validated MSI carrying those changes.
- **Current State**:
  - Hosted Windows packaging succeeded at tag `v0.1.1-rc29`, producing `ObjcMarkdown-0.1.1-rc29-win64.msi` and the matching portable zip from GitHub Actions run `24852317387`.
  - The `rc29` MSI was installed, smoke-launched, and uninstalled successfully on a fresh OracleTestVM libvirt Windows lease during direct validation; the packaged installer is now provably buildable and installable on a clean Windows VM.
  - `ObjcMarkdown` repo changes are in place to require `WinUITheme` in the staged payload and set `GSTheme=WinUITheme` with `policy: ifUnset` in [packaging/manifests/windows-msi.manifest.json](/home/danboyd/git/ObjcMarkdown/packaging/manifests/windows-msi.manifest.json).
  - Repo-local Windows theme input prep was updated to work with the managed MSYS2 `clang64` toolchain in [packaging/scripts/ensure-windows-theme-inputs.ps1](/home/danboyd/git/ObjcMarkdown/packaging/scripts/ensure-windows-theme-inputs.ps1).
  - Local Linux/dev launch regressions caused by the new updater libraries are fixed in [GNUmakefile](/home/danboyd/git/ObjcMarkdown/GNUmakefile) and [scripts/omd-viewer.sh](/home/danboyd/git/ObjcMarkdown/scripts/omd-viewer.sh).
  - The packaging workflows are now pinned to the current `gnustep-packager` integration commit and should use the normal reusable path instead of the ad hoc OCI remote rebuild bundle.
  - The current packager pin includes bounded hosted Windows bootstrap diagnostics and a direct generated-`.exe` smoke for the stale published CLI artifact.
  - ObjcMarkdown now fetches declared Windows theme inputs from `packaging/inputs.json` during hosted packaging when they are absent from the workspace.
  - Hosted Windows run `24747383333` confirmed bootstrap and required theme fetch success, but failed before MSI output while repo-local theme build output was still suppressed.
  - The repo-local Windows build/stage wrappers now preserve theme build logs and pass `OMD_GNUSTEP_USER_THEME_ROOT` through the build and stage steps.
  - Hosted Windows run `24747752773` exposed the managed-toolchain path translation problem; the repo-local MSYS bridge now uses the selected MSYS2 shell root for `cygpath` conversion while sourcing GNUstep from the managed `gnustep-cli-new` root.
  - Hosted Windows runs `24748075413` and `24748308894` then exposed GNUstep makefile-root assumptions under the setup-msys2 shell; the repo-local bridge now exports `GNUSTEP_MAKEFILES` to the managed makefiles directory and prepends the managed tools directory.
  - Hosted Windows run `24748570291` reached WinUITheme compilation and exposed the baked compiler path; the repo-local bridge now overrides compiler variables to the managed clang toolchain.
  - The successful MSI path also required mirroring `cmark` into the managed Windows runtime search layout, adding source-side `cmark` include compatibility in [ObjcMarkdown/GNUmakefile](/home/danboyd/git/ObjcMarkdown/ObjcMarkdown/GNUmakefile), and making Windows staging tolerate an unset `USER`.
  - Fresh UAT on a new OracleTestVM lease after install showed two remaining product issues: first launch still came up in the stock GNUstep theme instead of `WinUITheme`, and forcing `WinUITheme` exposed malformed menu/controls rendering in the viewer and Preferences UI.
- **Current Analysis**:
  - The first-launch default-theme miss appears primarily upstream at the `gnustep-packager` launcher/defaults-contract layer, with a secondary repo-local fallback bug in [ObjcMarkdownViewer/main.m](/home/danboyd/git/ObjcMarkdown/ObjcMarkdownViewer/main.m) because the Windows bundled-theme probe still assumes a `clang64\\lib\\GNUstep\\Themes` install layout instead of the packaged `runtime\\lib\\GNUstep\\Themes` layout.
  - The WinUITheme rendering corruption does not currently look like a packager orchestration failure; it is either incomplete WinUITheme runtime payload composition or a runtime/theme implementation issue exposed by this app on Windows.
  - Upstream `gnustep-packager` commit `e17683e27748484999c74a8b95f00163d4e97dc1` added `packagedDefaults.appDomain` seeding for MSI/AppImage, but code and tests still keep `GSTheme` on the old semantic `packagedDefaults.defaultTheme -> launch.env.GSTheme (ifUnset)` path. That commit substantially addresses the generalized app-domain `NSUserDefaults` request, but it does not yet prove or implement a fix for the first-launch `defaultTheme` bug.
- **External Findings**:
  - `gnustep-packager` now provides manifest-driven host dependency provisioning, reusable dependency profiles such as `gnustep-cmark`, declarative packaged defaults, semantic package/install assertions, and the hosted `gnustep-cli-new` bootstrap gate.
  - `gnustep-cli-new` now publishes the Windows MSYS2 clang64 artifacts that the packager bootstrap path is expected to consume.
- **Next Step**:
  - Carry the first-launch default-theme bug upstream in `gnustep-packager` until the packaged `defaultTheme` contract is actually honored on first launch, or until upstream broadens packaged defaults to cover the needed GNUstep domain behavior cleanly.
  - Audit the installed `WinUITheme.theme` payload against the built theme output before blaming theme code, then decide whether the malformed Windows widgets are a packaging omission or an upstream theme/runtime rendering defect.
  - After upstream/default-theme work lands, rebuild the MSI through the normal reusable packaging path and re-run OracleTestVM manual/UAT verification against the corrected installer.
