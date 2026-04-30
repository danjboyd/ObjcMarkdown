# Windows Phase 10 MSI Recovery Evidence

Date: 2026-04-30

## VM Access

Known-good VM:

- hypervisor: `iep-vm2`
- libvirt domain: `oracletestvms-windows-2022-lease-20260427155635-05sphs`
- guest IP: `172.17.2.148`
- SSH user used for build evidence: `Administrator`
- hostname: `OTVM-WIN-05SPHS`

## Phase 10A Snapshot

Evidence bundle:

- `dist/phase10-msi/OMDPhase10Evidence.zip`
- extracted summary under `dist/phase10-msi/evidence/OMDPhase10Evidence/`

Important findings:

- `ObjcMarkdown` commit: `87ea70ed2df2bac8c634b6b82471339ce5dc8e6d`
- `plugins-themes-WinUITheme` commit: `48d21f0a2ae97ca70a03197d93a305144635517f`
- no `plugins-themes-win11theme` checkout was present under `C:\Users\Administrator\git`
- no `gnustep-packager` checkout was present under `C:\Users\Administrator\git`
- the working GNUstep toolchain lives under `C:\Users\Administrator\AppData\Local\gnustep-cli`
- the working app binary is `C:\Users\Administrator\git\ObjcMarkdown\ObjcMarkdownViewer\MarkdownViewer.app\MarkdownViewer.exe`
- no existing `C:\Users\Administrator\git\ObjcMarkdown\dist\packaging\windows\stage` payload was present

The source checkout on the VM had local modifications in several packaging and Windows docs files. Treat the captured bundle as environment evidence, not a clean source revision.

## Phase 10B Imported-Payload MSI

Imported stage:

- VM path: `C:\Users\Administrator\git\ObjcMarkdown\dist\phase10-import\windows\stage`
- local manifest copy: `dist/phase10-msi/phase10-imported-stage-manifest.csv`
- file count: `39281`

Local artifacts copied back:

- `dist/phase10-msi/ObjcMarkdown-0.1.1-phase10-phase10-import-win64.msi`
- `dist/phase10-msi/ObjcMarkdown-0.1.1-phase10-phase10-import-win64-portable.zip`
- `dist/phase10-msi/windows-msi.imported.manifest.json`

Temporary packager workarounds required on the VM:

- copied local `../gnustep/gnustep-packager` working tree to `C:\Users\Administrator\git\gnustep\gnustep-packager`
- ran Windows PowerShell 5.1 with `$IsWindows`, `$IsLinux`, and `$IsMacOS` compatibility variables
- patched the copied MSI backend to avoid `[System.IO.Path]::GetRelativePath`, which is unavailable there
- added `DNSAPI.dll` and `IPHLPAPI.DLL` to the temporary manifest's ignored MSI runtime dependencies

Result:

- MSI generation succeeded
- clean Windows MSI install succeeded on `lease-20260430191436-puvq0c`
- automated validation failed after install because the imported known-good payload did not include TinyTeX

Validation evidence:

- handoff: `dist/otvm/windows/handoff.txt`
- test lease: `lease-20260430191436-puvq0c`
- logs: `dist/otvm/windows/test/lease-20260430191436-puvq0c/logs/`
- failure: `Expected bundled TinyTeX runtime root not found`

## Phase 10C Payload Comparison

Comparison report:

- `dist/phase10-msi/phase10-payload-comparison.md`

Manifest inputs:

- imported known-good stage: `dist/phase10-msi/phase10-imported-stage-manifest.csv`
- normal source stage: `dist/phase10-msi/phase10-source-stage-manifest.csv`
- MSI install tree: `dist/phase10-msi/phase10-msi-install-tree-manifest.csv`

Summary:

- imported stage: `39281` files, `1,554,463,776` bytes
- source stage: `10088` files, `391,566,844` bytes
- MSI install tree: `39285` files, `1,554,650,418` bytes

Critical differences:

- the imported stage and installed tree include project DLLs inside `app/MarkdownViewer.app`
- the normal source stage places project DLLs under `runtime/bin`
- the normal source stage includes TinyTeX; the imported stage does not
- the imported stage is effectively the full `gnustep-cli` `clang64` runtime and is much larger than the normal source stage
- the installed tree matches the imported stage plus generated launcher/config/update metadata

Normal source staging printed these gnustep-cli path warnings before completing:

```text
/usr/bin/bash: line 1: /etc/profile: No such file or directory
/usr/bin/bash: line 1: cd: /c/Users/Administrator/git/ObjcMarkdown: No such file or directory
```

This confirms that `build-from-powershell.ps1` still assumes the MSYS2 `/c/...` mount convention, while `gnustep-cli-new` uses `/cygdrive/c/...`.

## Follow-Up

- rebuild through the normal source-built staging path after the Phase 10D-G repo fixes
- decide whether project DLLs belong in `app/MarkdownViewer.app` or `runtime/bin`, then make the package contract assert that choice
- keep TinyTeX in the release stage; the imported known-good runtime alone is not release-complete
- validate the new source-built MSI on a clean `OracleTestVMs` Windows VM

## Phase 10D-G Repo Recovery

Date: 2026-04-30

Phase 10D moved VM-derived requirements into repo-owned packaging inputs:

- `packaging/manifests/windows-msi.manifest.json` declares `mingw-w64-clang-x86_64-cmark` in `hostDependencies.windows.msys2Packages`
- the manifest declares required Windows theme inputs for `WinUITheme` and `Win11Theme`
- the manifest sets `packagedDefaults.defaultTheme` to `WinUITheme`
- `DNSAPI.dll` and `IPHLPAPI.DLL` are listed in the MSI ignored system-DLL set

Phase 10E repinned the Windows workflow to `gnustep-packager` commit
`4fc362a68b3e55191942c01a92cf2f8da82031bb`, the baseline used for the next
normal MSI recovery build.

Phase 10F hardened the repo's Windows scripts for the managed `gnustep-cli-new`
runtime:

- `scripts/windows/build-from-powershell.ps1` now detects `/c` versus `/cygdrive/c`
- `packaging/scripts/ensure-windows-theme-inputs.ps1` uses the same mount probe
- both scripts treat `/etc/profile` as optional before sourcing GNUstep
- validation on `OTVM-WIN-05SPHS` with
  `MSYS2_LOCATION=C:\Users\Administrator\AppData\Local\gnustep-cli` confirmed
  `-Task command -Command pwd` resolves to
  `/cygdrive/c/Users/Administrator/git/ObjcMarkdown`
- validation on the same VM confirmed `-Task stage -StageDir dist/phase10-source-stage-fixed/windows/stage`
  completes without the previous `/etc/profile` or `/c/...` warnings

Phase 10G retirement status:

- the imported-payload MSI remains only as ignored recovery evidence under `dist/phase10-msi/`
- it is not a release candidate because it lacks TinyTeX and imports a full mutable `gnustep-cli` runtime payload
- the release path is back to source build, normalized staging, `gnustep-packager` MSI/portable ZIP generation, and clean `OracleTestVMs` validation
