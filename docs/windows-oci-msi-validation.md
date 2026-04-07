# Windows MSI Validation On OCI

## Purpose

This document is the handoff/runbook for the Windows MSI validation workflow
using Oracle Cloud Infrastructure (OCI). It is intended to let a new Codex
session resume exactly where the previous session left off.

The goal is:

1. Build and package the Windows MSI locally through the sibling `gnustep-packager` repo.
2. Launch a fresh Windows VM in OCI from a prepared "golden" image.
3. Copy the MSI to that VM over `scp`.
4. Install and smoke-test the MSI over `ssh`.
5. Use RDP only for visual/manual checks.
6. Terminate the disposable VM when the run is done.

Do not rely on one long-lived mutable test VM for iterative validation.
Prefer fresh VMs from the golden image.

## Current OCI State

As of `2026-03-24`, the OCI setup is:

- Region: `us-phoenix-1`
- Tenancy OCID:
  `ocid1.tenancy.oc1..aaaaaaaa5dvvl3wfab3mrwynbmzo2phelufhur62pp23cywsvbxy3a3kdd2q`
- Primary VCN:
  `ocid1.vcn.oc1.phx.amaaaaaaofscz7qanip2l5vnuxtoh3cdckpch3ar73dsg4z2fiwwjqn2mcyq`
  (`iep-oracle-cloud-network`)
- Primary subnet:
  `ocid1.subnet.oc1.phx.aaaaaaaaimvrd2faa744cu34ucvq2vpftgcnuhe7taaqhunvszhn64fzon4a`
  (`iep-oracle-subnet (regional)`)

### Golden Image

The reusable Windows image created from the prepared VM is:

- Name: `objcmarkdown-msi-golden-20260324`
- Image OCID:
  `ocid1.image.oc1.phx.aaaaaaaa6253prkupypnde7blkcsojo66njxkyquiimmkdy7foiu4ywxyiva`
- Base image: Windows Server 2022 Standard
- Lifecycle state at handoff: `AVAILABLE`

This image should be treated as the launch source for future disposable MSI
validation VMs.

### Source VM Used To Create The Image

The image was created from:

- Instance name: `instance-20260324-1645`
- Instance OCID:
  `ocid1.instance.oc1.phx.anyhqljsofscz7qcvn6w3topji4sreldd3dzckdrr5ajh5ca6kpxg4edlyyq`
- Public IP at creation time: `129.153.68.87`
- Shape actually chosen in the OCI UI:
  `VM.Standard.E5.Flex`
- Shape config:
  `1 OCPU`, `12 GB RAM`

This instance was mainly used to prepare the baseline environment and create the
golden image. It is not the preferred long-term test loop.

## Why This Approach

The previous investigation established:

- Local PowerShell Codex and OCI Cloud Shell both authenticated successfully.
- Both environments failed with the same `LaunchInstance` 404 for one guessed
  CLI launch request.
- A manual launch from the OCI web console succeeded.
- Once the baseline VM existed, SSH-based automation was straightforward.

The result is a pragmatic workflow:

- use the OCI web console once to establish a valid Windows baseline
- capture a custom image
- drive all repeated MSI validation from that image, over SSH/RDP

This is more reliable than trying to infer every OCI launch input from scratch.

## What Is Installed In The Golden VM

These tools were confirmed on the prepared VM before the image was taken:

- `git 2.53.0.windows.2`
- `gh 2.88.1`
- `oci 3.76.1`
- `node v24.14.0`
- `npm 11.9.0`
- `codex-cli 0.116.0`
- `WiX 6.0.2+b3f3403`
- OpenSSH Server enabled and reachable

Important authentication note:

- `codex` was confirmed usable in the VM via `codex login status`
- `gh` was usable interactively in RDP, but Windows keyring-backed `gh auth`
  did not behave reliably from non-interactive SSH sessions

For the MSI validation workflow, do **not** depend on `gh` inside the guest.
Use `scp`/`ssh` from the local machine instead.

## Local Build And Packaging Flow

The supported Windows build entry point is still:

```powershell
.\scripts\windows\build-from-powershell.ps1 -Task build
.\scripts\windows\build-from-powershell.ps1 -Task test
.\scripts\windows\build-from-powershell.ps1 -Task stage -StageDir dist/ObjcMarkdown
```

MSI validation script already in repo:

- [scripts/windows/validate-msi.ps1](/C:/Users/Support/git/ObjcMarkdown/scripts/windows/validate-msi.ps1)

Canonical packager-backed local packaging flow:

```powershell
.\scripts\windows\build-from-powershell.ps1 -Task test
C:\Users\Support\git\gnustep-packager\scripts\run-packaging-pipeline.ps1 `
  -Manifest C:\Users\Support\git\ObjcMarkdown\packaging\package.manifest.json `
  -Backend msi `
  -RunSmoke
```

Expected output:

- `dist\gnustep-packager\packages\ObjcMarkdown-<manifest-version>-win64.msi`
- `dist\gnustep-packager\packages\ObjcMarkdown-<manifest-version>-win64-portable.zip`
- the staged runtime now includes `WinUXTheme`, `Win11Theme`, and `WinUITheme`
- the staged runtime now also includes a private TinyTeX toolchain at `clang64\texlive\TinyTeX`

Legacy in-repo WiX packaging still exists only as a fallback path while the
retirement work finishes:

- [scripts/windows/build-msi.ps1](/C:/Users/Support/git/ObjcMarkdown/scripts/windows/build-msi.ps1)

## Preferred Day-Two Validation Loop

### 1) Launch A Fresh VM From The Golden Image

Preferred guest characteristics:

- Windows Server 2022 Standard
- public IP enabled
- OpenSSH Server available
- RDP enabled only when needed

The current recommendation is to launch these VMs as disposable test machines.
Do not preserve state across MSI validation runs.

### 2) Push MSI Over SSH/SCP

Once the new VM is reachable over SSH:

```powershell
scp -i C:\Users\Support\.ssh\id_rsa `
  dist\installer\ObjcMarkdown-0.1.0.0-win64.msi `
  opc@<vm-ip>:C:/Users/opc/Downloads/ObjcMarkdown.msi
```

Because SCP path handling on Windows/OpenSSH can be awkward, a more robust
fallback is to copy to the default home directory target:

```powershell
scp -i C:\Users\Support\.ssh\id_rsa `
  dist\installer\ObjcMarkdown-0.1.0.0-win64.msi `
  opc@<vm-ip>:ObjcMarkdown.msi
```

If you are working from home and OCI only allows traffic from the office IP,
reach the guest through the office jump host with `ssh -J` / `scp -J`:

```powershell
scp -J iep-vm2 -i C:\Users\Support\.ssh\id_rsa `
  dist\installer\ObjcMarkdown-0.1.0.0-win64.msi `
  opc@<vm-ip>:ObjcMarkdown.msi
```

### 3) Install And Validate Over SSH

Preferred remote validation path:

- Copy the MSI.
- Copy the validation script from the repo.
- Run the script over SSH.

Copy the validation script:

```powershell
scp -i C:\Users\Support\.ssh\id_rsa `
  scripts\windows\validate-msi.ps1 `
  opc@<vm-ip>:validate-msi.ps1
```

If you are routing through the office jump host:

```powershell
scp -J iep-vm2 -i C:\Users\Support\.ssh\id_rsa `
  scripts\windows\validate-msi.ps1 `
  opc@<vm-ip>:validate-msi.ps1
```

Run validation:

```powershell
ssh -i C:\Users\Support\.ssh\id_rsa opc@<vm-ip> `
  "powershell -ExecutionPolicy Bypass -File C:\Users\opc\validate-msi.ps1 -MsiPath C:\Users\opc\ObjcMarkdown.msi -RunSmoke"
```

If you are routing through the office jump host:

```powershell
ssh -J iep-vm2 -i C:\Users\Support\.ssh\id_rsa opc@<vm-ip> `
  "powershell -ExecutionPolicy Bypass -File C:\Users\opc\validate-msi.ps1 -MsiPath C:\Users\opc\ObjcMarkdown.msi -RunSmoke"
```

Do not assume a fresh disposable guest contains a repo checkout at
`C:\Users\opc\ObjcMarkdown`. Unless the image was prepared with that path on
purpose, copy `validate-msi.ps1` explicitly as part of the run.

If you prefer not to copy the script, use an inline PowerShell command that runs
`msiexec` directly.

Minimal direct install example:

```powershell
ssh -i C:\Users\Support\.ssh\id_rsa opc@<vm-ip> `
  "powershell -Command `"Start-Process msiexec.exe -Wait -ArgumentList '/i','C:\Users\opc\ObjcMarkdown.msi','/qn','/norestart','/l*v','C:\temp\omd-install.log'`""
```

The validation script now verifies more than install/uninstall and process launch:

- bundled Windows themes are present
- bundled `latex.exe` and `dvisvgm.exe` are present under `clang64\texlive\TinyTeX\bin\windows`
- the installed TinyTeX bundle can compile and convert a real formula on the guest

### 4) Manual Visual Checks Over RDP

Use RDP only if the automated checks pass but visual/UI checks are still needed,
for example:

- Start Menu icon
- taskbar/titlebar icon
- app launch from installed shortcut
- file association behavior
- import/export dialog behavior
- PDF export/print behavior

### 5) Destroy The Disposable VM

After the run:

- collect logs from `C:\temp\omd-logs`
- preserve screenshots if needed
- terminate the VM

This keeps the environment clean and avoids cost drift.

Example log retrieval:

```powershell
scp -i C:\Users\Support\.ssh\id_rsa `
  opc@<vm-ip>:C:/temp/omd-logs/* `
  dist\oci-logs\
```

If you are routing through the office jump host:

```powershell
scp -J iep-vm2 -i C:\Users\Support\.ssh\id_rsa `
  opc@<vm-ip>:C:/temp/omd-logs/* `
  dist\oci-logs\
```

The current validation script writes:

- `C:\temp\omd-logs\install.log`
- `C:\temp\omd-logs\uninstall.log`

## First End-To-End OCI Result

The first full disposable-VM OCI validation pass was completed on `2026-03-26`.

Observed result:

- local Windows build succeeded
- Windows tests succeeded
- runtime staging succeeded
- MSI packaging succeeded
- fresh OCI VM launch from the golden image succeeded
- MSI install succeeded
- smoke launch succeeded
- uninstall succeeded
- local logs were collected under `dist/oci-logs/20260326-132324`

Operational wrinkle discovered during that run:

- the subnet's broad SSH ingress rule on port `22` allowed enough unauthenticated traffic to trigger `Exceeded MaxStartups` on the Windows guest before the validation login completed
- validation succeeded only after port `22` was temporarily narrowed to the current public IP
- the original broad `22` rule was restored after the run

That means the OCI path is now validated, but repeatability still depends on
codifying SSH-ingress narrowing/restoration or otherwise tightening guest SSH
exposure during validation.

## Tagged CI Artifact OCI Result

The first full CI-artifact OCI validation pass was completed later on
`2026-03-26` against the tagged MSI from GitHub Actions run `23612901170`
(`v0.1.1-rc2`).

Observed result:

- CI artifact download succeeded (`objcmarkdown-windows-0.1.1`)
- fresh OCI VM launch from the golden image succeeded
- temporary narrow SSH ingress was added automatically for the current public IP
- the original broad SSH rule was removed during validation and restored after teardown
- CI-produced MSI install succeeded
- smoke launch succeeded
- uninstall succeeded
- local logs were collected under `dist/oci-logs/ci-23612901170`
- disposable VM termination succeeded

The validation used:

- artifact MSI:
  `dist/ci-artifacts/23612901170/ObjcMarkdown-0.1.1.0-win64.msi`
- log directory:
  `dist/oci-logs/ci-23612901170`
- instance OCID:
  `ocid1.instance.oc1.phx.anyhqljsofscz7qc7ywd257ztyz7g7dcieffmu2gr5pqav5x6e3feou5756a`

One follow-up bug was found in the orchestrator after the successful remote run:

- `oci-run-msi-validation.ps1` assumed `oci-push-and-test-msi.ps1` returned only
  one object
- native `ssh`/`scp` output meant the final result could be an array
- this was fixed by selecting the structured result object explicitly

## Packager-Backed OCI Result

The first full OCI validation pass using the sibling `gnustep-packager` repo
completed on `2026-03-27`.

Observed result:

- local GNUstep tests succeeded before packaging
- `gnustep-packager` build succeeded
- `gnustep-packager` stage succeeded
- `gnustep-packager` MSI packaging succeeded
- fresh OCI VM launch from the golden image succeeded
- temporary narrow SSH ingress was added automatically for the current public IP
- the original broad SSH rule was removed during validation and restored after teardown
- remote MSI install succeeded
- remote smoke launch succeeded
- remote uninstall succeeded
- local OCI logs were collected under `dist/oci-logs/20260327-165910`
- disposable VM termination succeeded

The successful command was:

```powershell
.\scripts\windows\oci-run-msi-validation.ps1 `
  -PackagingMode packager `
  -PackagerManifest packaging\package.manifest.json `
  -IdentityFile C:\Users\Support\.ssh\id_rsa `
  -TemporarilyRestrictSshIngress `
  -RunSmoke
```

The validation used:

- artifact MSI:
  `dist/gnustep-packager/packages/ObjcMarkdown-0.1.1-rc2-win64.msi`
- log directory:
  `dist/oci-logs/20260327-165910`
- instance OCID:
  `ocid1.instance.oc1.phx.anyhqljsofscz7qcom7kjv7yzedly7iu6xlufg7tzlvij3aqkwcaon5ipgia`

Required follow-up fixes that were made during this session:

- `scripts/windows/validate-msi.ps1` was updated to handle per-user installs
  under `%LOCALAPPDATA%\ObjcMarkdown`, not only `C:\Program Files\ObjcMarkdown`
- `scripts/windows/validate-msi.ps1` now always attempts uninstall in a
  `finally` path so a failed smoke check does not strand the guest in a dirty
  state
- `scripts/windows/oci-run-msi-validation.ps1` now supports
  `-PackagingMode packager`
- `scripts/windows/oci-run-msi-validation.ps1` now cleans up a still-live prior
  validation VM recorded in the state file before launching a new one
- `scripts/windows/oci-launch-validation-vm.ps1` now tags validation VMs as
  disposable MSI-validation machines
- `scripts/windows/oci-cleanup-validation-vms.ps1` was added as a manual sweep
  command for leftover validation VMs

Leave-off state for the next session:

- the packager-backed OCI path is now validated end to end
- `dist/oci/last-validation-vm.json` for this run records `terminated: true`
- the current known-good OCI log directory is `dist/oci-logs/20260327-165910`
- no further OCI work is required to prove the packager MSI path itself

## SSH Notes

The previous session verified SSH from the local machine into the prepared VM
using:

```powershell
ssh -i C:\Users\Support\.ssh\id_rsa -o StrictHostKeyChecking=no opc@<vm-ip> hostname
```

If you are not on the office network and OCI ingress is still restricted to the
office IP, use the office host `iep-vm2` as the jump host:

```powershell
ssh -J iep-vm2 -i C:\Users\Support\.ssh\id_rsa -o StrictHostKeyChecking=no opc@<vm-ip> hostname
```

The public key offered by the local machine was:

```text
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7AYyzKDbb42gYvCquJJUvu8doFFoW3FJaKyh2adM+kODF3ZJgz7g+zN6ynelBf+2XVgHTN6Rj4qm7kcrmcQZmW4gvffKQCUvtyqJtEOVe7QfC0acuKKvEVauXKpM0PNUvj+OQhzv9Hb66V3kEpwS15FEPA1/g+vRCuuXGTUYn3MOX+C9Vu+VExcKt7AoDaoi4O1YmWnU1I1lCcWGAHF/qWSTX1fAmd2VfckYLK9cCcVnqxKiXfYJB6MHY26bfMQP6tZ3G5RZlPoUoBvwoUuuTTIuv8jWJWGWFmlTBPQlSCFQYz67wgl9Po3PrgPsKiWP2oDupAEcCiq4BUZzbWIckgmC1h21IzqeyuT5bsUED3F6Kk9KCt+JUT4hgxcWr+0d2xuHJld4y9GHsxpUKYdcvXuMoOCi5wGfyQMwpeGEWOGM7JgFj1vC1qowEDCFwVjF70Xfw5rDfgak7atc13R0MZWT8uLkOfBSQBBsikUoElTfku2I7LURKEYFZ4KSZ6Xc= azuread\support@danielt14-winvm
```

Fingerprint:

- `SHA256:M+xdieF5J7kVqCAzTx2ZnOdD+WbPSdH7flyrE0JsX6g`

If SSH breaks on a future guest, first verify:

- `OpenSSH Server` installed
- `sshd` running
- `C:\Users\opc\.ssh\authorized_keys` exists without `.txt`
- ACLs on `.ssh` and `authorized_keys` are not overly broad

## RDP Notes

During the preparation session, RDP was allowed by adding a temporary security
list rule for TCP `3389` restricted to the user's current public IP.

Do not leave a broad `3389` rule open to `0.0.0.0/0`.

Recommended policy:

- add a temporary `3389` rule only for the current public IP
- remove it again after manual testing

The same applies to SSH on port `22` if you decide to narrow guest access later.

## Why Not Depend On GH In The Guest

`gh auth status` in the interactive RDP session showed a valid login, but the
same command from a non-interactive SSH session reported the token as invalid.

That means Windows keyring-backed `gh` auth is not currently trustworthy for
unattended validation runs.

Therefore:

- do not require `gh` inside the guest for MSI validation
- transfer artifacts from the local machine via `scp`
- keep guest automation focused on `ssh`, `msiexec`, log collection, and smoke checks

## Automation Entry Points

The OCI-driven disposable-VM automation entry points now live under
`scripts/windows/`:

1. `scripts/windows/oci-launch-validation-vm.ps1`
Creates a disposable Windows VM from the custom image.

2. `scripts/windows/oci-open-rdp-rule.ps1`
Adds a temporary narrow `3389` rule for the current public IP.

3. `scripts/windows/oci-push-and-test-msi.ps1`
Uses `scp` + `ssh` to copy the MSI, install it, run validation, and collect logs.

4. `scripts/windows/oci-terminate-validation-vm.ps1`
Destroys the disposable VM after results are collected.

5. `scripts/windows/oci-run-msi-validation.ps1`
One-shot orchestrator:
build -> test -> stage -> package -> launch VM -> push MSI -> validate -> collect logs -> terminate VM

The script supports both:

- `-PackagingMode packager`
  Use the sibling `..\gnustep-packager` repo and
  `packaging/package.manifest.json` to produce the MSI before the OCI steps.
- `-PackagingMode legacy`
  Use the in-repo `scripts/windows/build-msi.ps1` flow only as a fallback while the repo-local MSI path is being retired.

Recommended packager-backed run:

```powershell
.\scripts\windows\oci-run-msi-validation.ps1 `
  -PackagerManifest packaging\package.manifest.json `
  -IdentityFile C:\Users\Support\.ssh\id_rsa `
  -TemporarilyRestrictSshIngress `
  -RunSmoke
```

Shutdown/cost-control behavior:

- VM termination is the default at the end of the run.
- Passing `-KeepVm` is the only normal way to keep a validation VM alive.
- Before launching a new validation VM, the script now checks the state file and
  terminates any still-live prior validation VM recorded there unless you pass
  `-SkipCleanupExistingVm`.
- Validation VMs are tagged as disposable MSI validation machines at launch.

Emergency cleanup command:

```powershell
.\scripts\windows\oci-cleanup-validation-vms.ps1
```

Recommended first end-to-end run:

```powershell
.\scripts\windows\oci-run-msi-validation.ps1 `
  -IdentityFile C:\Users\Support\.ssh\id_rsa `
  -TemporarilyRestrictSshIngress `
  -RunSmoke
```

If you are routing through the office jump host:

```powershell
.\scripts\windows\oci-run-msi-validation.ps1 `
  -IdentityFile C:\Users\Support\.ssh\id_rsa `
  -JumpHost iep-vm2 `
  -TemporarilyRestrictSshIngress `
  -RunSmoke
```

Tagged CI-artifact example:

```powershell
gh run download 23612901170 -n objcmarkdown-windows-0.1.1 -D dist\ci-artifacts\23612901170

.\scripts\windows\oci-run-msi-validation.ps1 `
  -MsiPath dist\ci-artifacts\23612901170\ObjcMarkdown-0.1.1.0-win64.msi `
  -IdentityFile C:\Users\Support\.ssh\id_rsa `
  -TemporarilyRestrictSshIngress `
  -RunSmoke `
  -LogDir dist\oci-logs\ci-23612901170
```

## Suggested Orchestrated End State

The desired stable process is:

1. Build locally from PowerShell with MSYS2 `clang64`.
2. Stage runtime locally.
3. Package MSI locally with `gnustep-packager`.
4. Launch disposable Windows VM from
   `ocid1.image.oc1.phx.aaaaaaaa6253prkupypnde7blkcsojo66njxkyquiimmkdy7foiu4ywxyiva`.
5. Copy MSI to guest over `scp`.
6. Validate via `ssh` using PowerShell.
7. RDP only if manual investigation is required.
8. Terminate guest.

That is the workflow future Codex sessions should continue using and hardening.

## Immediate Next Step For The Next Session

The next Codex session should:

1. Read this file first.
2. Keep the current golden image OCID as the source of truth.
3. Use `scp`/`ssh`, not `gh`, for the guest-side validation loop inside the guest.
4. Reuse `-TemporarilyRestrictSshIngress` when the subnet still exposes SSH on `0.0.0.0/0`.
5. Collect logs under `dist/oci-logs`, record any installer/runtime defects, and only keep a VM alive when manual RDP investigation is needed.
6. If a session ever dies mid-run, use `scripts/windows/oci-cleanup-validation-vms.ps1` to terminate any leftover disposable validation VMs.
7. Optionally add GitHub Release-page asset publishing or a short kept-VM manual visual pass if those become release gates.
8. Optionally terminate the original source VM if it is no longer needed.

## Related Files

- [WINDOWS_BUILD.md](/C:/Users/Support/git/ObjcMarkdown/WINDOWS_BUILD.md)
- [scripts/windows/build-from-powershell.ps1](/C:/Users/Support/git/ObjcMarkdown/scripts/windows/build-from-powershell.ps1)
- [scripts/windows/build-msi.ps1](/C:/Users/Support/git/ObjcMarkdown/scripts/windows/build-msi.ps1)
- [scripts/windows/validate-msi.ps1](/C:/Users/Support/git/ObjcMarkdown/scripts/windows/validate-msi.ps1)
- [scripts/windows/oci-open-rdp-rule.ps1](/C:/Users/Support/git/ObjcMarkdown/scripts/windows/oci-open-rdp-rule.ps1)
- [scripts/windows/oci-cleanup-validation-vms.ps1](/C:/Users/Support/git/ObjcMarkdown/scripts/windows/oci-cleanup-validation-vms.ps1)
- [scripts/windows/oci-run-msi-validation.ps1](/C:/Users/Support/git/ObjcMarkdown/scripts/windows/oci-run-msi-validation.ps1)
