# Windows OracleTestVMs MSI Validation

Phase `9D` and `9E` use two separate `OracleTestVMs` Windows leases:

- a dedicated build VM for MSI reproduction work in an `msys2/clang64` environment
- a separate clean test VM for first-install, launch, and manual GUI validation

Going forward, the expected backend for these leases is libvirt. If a session uses
OCI as a temporary fallback, it should document that explicitly rather than
treating OCI as the default path.

The helper script is:

- [scripts/windows/otvm-msi-validation.sh](/home/danboyd/git/ObjcMarkdown/scripts/windows/otvm-msi-validation.sh)

## Preferred Flow

From the repo root on the Linux operator machine:

```bash
./scripts/windows/otvm-msi-validation.sh create \
  --msi dist/github-run-23612901170/objcmarkdown-windows-0.1.1/ObjcMarkdown-0.1.1.0-win64.msi \
  --portable-zip dist/github-run-23612901170/objcmarkdown-windows-0.1.1/ObjcMarkdown-0.1.1-win64-portable.zip
```

The helper will:

- create a Windows build lease
- create a separate Windows clean-test lease
- upload a source snapshot plus build instructions to `C:\Users\Public\Desktop\ObjcMarkdownBuild`
- upload the MSI, optional portable ZIP, sample Markdown files, and `validate-msi.ps1` to `C:\Users\Public\Desktop\ObjcMarkdownValidation`
- run unattended `validate-msi.ps1 -RunSmoke` once on the clean test VM
- save lease JSON, copied logs, and a combined handoff file under `dist/otvm/windows/`

## Status Snapshot

As of `2026-04-07`:

- the OracleTestVMs Windows build VM was repaired enough to rebuild the MSI from the current repo state
- `Win11Theme` and `WinUITheme` build there when the theme build is given `-DHAVE_MODE_T=1`
- the upstream header mismatch behind that workaround is documented in:
  - [windows-msys2-clang64-mode-t-header-bug.md](/home/danboyd/git/ObjcMarkdown/docs/upstream/windows-msys2-clang64-mode-t-header-bug.md)
  - [gnustep-cli-windows-toolchain-gap-report.md](/home/danboyd/git/ObjcMarkdown/docs/upstream/gnustep-cli-windows-toolchain-gap-report.md)
- the rebuilt MSI was successfully staged onto a fresh clean Windows VM
- unattended smoke validation on a brand-new Windows guest can still fail transiently with installer contention (`1618`) during first-boot servicing

Next session:

- create a fresh clean Windows test VM
- sign in over RDP as the test user
- run the staged MSI interactively
- confirm Start Menu launch, `WinUITheme` availability/defaulting, and external LaTeX rendering

## Operator Handoff

After `create`, read:

- `dist/otvm/windows/handoff.txt`

That file contains:

- SSH and RDP details for the build VM
- SSH and RDP details for the clean test VM
- the build-VM environment probe result
- the exact desktop folders prepared on each machine

## Manual Test Flow

Build VM:

- connect over RDP
- open `C:\Users\Public\Desktop\ObjcMarkdownBuild`
- use the source snapshot and `build-from-powershell.ps1`
- keep the expected toolchain at `C:\msys64` in the `CLANG64` environment

Clean test VM:

- connect over RDP
- open `C:\Users\Public\Desktop\ObjcMarkdownValidation`
- run the staged MSI manually
- launch the installed app
- open the files under `sample-markdown`
- confirm first-install behavior, launch behavior, theme/runtime correctness, and document rendering

Upgrade behavior:

- keep the clean test VM untouched after first-install validation
- when a second MSI is available, install the older one first and then the newer one on the same clean test VM

## Cleanup

Destroy the leases when validation is complete:

```bash
./scripts/windows/otvm-msi-validation.sh destroy \
  --build-lease-id <build-lease-id> \
  --test-lease-id <test-lease-id>
```
