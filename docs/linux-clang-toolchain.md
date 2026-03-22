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
- `cmark`

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

## CI Runner Contract

The Linux GitHub Actions workflow in this repo assumes a self-hosted runner that already satisfies the toolchain above and has `/usr/GNUstep/System/Library/Makefiles/GNUstep.sh` available.

That is intentional. Until a redistributable hosted-runner/container story exists for this exact toolchain, the CI lane should reflect the real supported environment instead of a weaker stock-package approximation.
