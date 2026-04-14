# Windows OCI MSI Validation

This document is retained only as a retirement note for the older direct-OCI
Windows validation helper.

The canonical Windows clean-machine validation workflow is now:

- [docs/windows-otvm-msi-validation.md](/home/danboyd/git/ObjcMarkdown/docs/windows-otvm-msi-validation.md)

That `OracleTestVMs` flow is the only supported path because it separates:

- a Windows build VM for `msys2/clang64` packaging work
- a separate clean Windows VM for first-install and manual validation

## Current Status

As of `2026-04-14`:

- the Windows build VM was repaired enough to rebuild the MSI from the current repo state
- `Win11Theme` and `WinUITheme` build successfully there when the theme build is given `-DHAVE_MODE_T=1`
- the root cause is documented in:
  - [windows-msys2-clang64-mode-t-header-bug.md](/home/danboyd/git/ObjcMarkdown/docs/upstream/windows-msys2-clang64-mode-t-header-bug.md)
  - [gnustep-cli-windows-toolchain-gap-report.md](/home/danboyd/git/ObjcMarkdown/docs/upstream/gnustep-cli-windows-toolchain-gap-report.md)
- the rebuilt MSI was staged onto a fresh clean Windows VM
- unattended smoke install on the clean VM still hit transient Windows first-boot installer contention (`1618`)
- a lower-level OCI rerun exposed that this repo's older direct-SSH script had drifted from the `OracleTestVMs` Windows contract by assuming the SSH user was `opc`

Practical implication:

- the packaging pipeline is back to a point where a fresh MSI can be built on a controlled Windows VM
- the next manual validation step is still to sign in over RDP as the test user and run the MSI interactively on a fresh clean VM

## Retired Helper

The old direct-OCI helper:

- [scripts/windows/oci-run-msi-validation.ps1](/home/danboyd/git/ObjcMarkdown/scripts/windows/oci-run-msi-validation.ps1)

has been retired as a supported validation path.

Reason:

- it drifted from the supported Windows bootstrap/access contract
- it encouraged direct-SSH assumptions that are no longer the source of truth
- keeping both models live would keep recreating validation drift

Use instead:

- [scripts/windows/otvm-msi-validation.sh](/home/danboyd/git/ObjcMarkdown/scripts/windows/otvm-msi-validation.sh)
- [docs/windows-otvm-msi-validation.md](/home/danboyd/git/ObjcMarkdown/docs/windows-otvm-msi-validation.md)
