# Linux GNUstep Clang Toolchain

`ObjcMarkdown` is developed and validated against a clang-based GNUstep environment with `libobjc2`, `libdispatch`, and `tools-xctest`.

## Why This Matters

The stock GNUstep packages in many Debian/Ubuntu repositories are built around the GCC Objective-C runtime. That is not the environment this project targets, and it is not a reliable match for the app's `libdispatch`/`libobjc2` usage.

For this repo, the canonical Linux environment is:

- `clang`
- `libobjc2`
- `libdispatch`
- GNUstep built against that clang/runtime stack
- `tools-xctest`

## Reference Setup Path

On the authoring machine, the reference setup comes from GNUstep's `tools-scripts` clang flow.

Relevant scripts in a sibling GNUstep checkout:

- `tools-scripts/install-gnustep-llvm18-debian`
- `tools-scripts/clang-setup`
- `tools-scripts/clang-build`

Those scripts install LLVM/clang, build `libobjc2`, build `libdispatch`, and then build the GNUstep stack with clang.

## Minimum Checks

After setup, these should succeed:

```bash
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
which clang
which xctest
gmake --version
```

## CI Image

Linux CI runs on GitHub-hosted runners inside a container image with exactly this toolchain, so it tests the real supported environment rather than a stock-package approximation, without depending on a self-hosted machine (#58).

- `ci/linux/Dockerfile` builds it on Debian 13 with clang the way the `tools-scripts` clang flow does (gnustep-make with `ng-gnu-gnu`, ARC and native exceptions; libobjc2; libdispatch; gnustep-base, -gui, -back into `/usr/GNUstep`; tools-xctest), plus Xvfb, fonts and pandoc for the tests. Every source is pinned by commit; the image lists them in `/usr/GNUstep/ci-toolchain.txt`.
- `.github/workflows/ci-image.yml` builds and pushes it to `ghcr.io/danjboyd/objcmarkdown-ci` when `ci/linux` changes, and reports the digest.
- `.github/workflows/linux-gnustep-clang.yml` runs in it, pinned by that digest. To move the toolchain: change the pins in the Dockerfile, let the image build, then update the digest in the CI workflow.

The pins are upstream commits, not the authoring machine's exact checkouts (some of which are local branches with uncommitted changes), so a failure that only CI shows can mean the code relies on a local GNUstep change.
