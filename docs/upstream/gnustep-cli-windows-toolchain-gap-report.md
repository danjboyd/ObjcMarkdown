# gnustep-cli Windows Toolchain Gap Report

## Summary

`gnustep-cli` successfully bootstrapped a managed `windows-msys2-clang64`
toolchain that could:

- build a sample GNUstep project
- build `ObjcMarkdown`
- produce a Windows MSI through `gnustep-packager`

But that environment was still incomplete for the actual downstream packaging
workflow required by `ObjcMarkdown`.

## Concrete Gaps Observed

### 1. Missing downstream package: `cmark`

The managed toolchain came up without `cmark`, and `ObjcMarkdown` could not
build until this was installed manually:

```text
mingw-w64-clang-x86_64-cmark
```

That means the managed Windows toolchain was not sufficient on its own for a
real downstream project that depends on a common GNUstep-adjacent library.

### 2. Theme bundle builds fail in the managed environment

The downstream Windows GNUstep theme repos needed for packaging:

- `plugins-themes-winuitheme`
- `plugins-themes-win11theme`
- `plugins-themes-WinUXTheme`

failed to build in the managed `windows-msys2-clang64` environment with this
compile error:

```text
In file included from C:/msys64/clang64/include/dispatch/dispatch.h:30:
C:/msys64/clang64/include/os/generic_win_base.h:28:13: error:
typedef redefinition with different types ('int' vs '_mode_t')
typedef int mode_t;
```

Fresh-VM repro narrowed this further. On a clean managed Windows 2022 lease:

- `GSConfig.h` includes `sys/types.h` early
- `sys/types.h` defines `mode_t`
- `Foundation.h` later reaches `dispatch/dispatch.h`
- `os/generic_win_base.h` still does:

```c
#ifndef HAVE_MODE_T
typedef int mode_t;
#endif
```

`HAVE_MODE_T` is not defined on this path, so the clean managed toolchain
reliably reproduces the conflict. This is no longer best described as random
package skew on one VM; it is reproducible on a freshly bootstrapped managed
toolchain.

## Why This Matters

From a downstream consumer perspective, the current result is:

- `gnustep-cli` can set up a Windows GNUstep toolchain that looks healthy
- but that same toolchain may still be unable to build representative downstream
  packaging inputs

For `ObjcMarkdown`, that meant:

- core app build succeeded
- MSI packaging succeeded
- but required Windows theme bundling could not be completed

## Recommendations For gnustep-cli

### 1. Support dependency cohorts, not only base toolchain bootstrap

Allow a downstream toolchain/profile to declare extra packages such as:

- `mingw-w64-clang-x86_64-cmark`

so the bootstrap result is actually usable for known project classes.

### 2. Add a package coherence / skew doctor check

`doctor` should validate that the managed package set is internally coherent
across:

- `libdispatch`
- `gnustep-base`
- `gnustep-gui`
- selected MSYS2 runtime family (`clang64`, `mingw64`, `ucrt64`, etc.)

This should catch partial upgrades or mismatched package revisions.

The current case also suggests a stronger requirement: `doctor` should detect
known header-contract failures in the selected managed backend, not only
presence/absence of paths.

### 3. Add downstream sentinel builds

For Windows GNUstep, it is not enough to prove only that a sample app builds.
`gnustep-cli` should be able to run one or more optional sentinel builds such as:

- a minimal `#import <AppKit/AppKit.h>` syntax-only compile
- a theme bundle build
- a package-time launcher/runtime validation build

That would have caught this environment issue immediately.

### 4. Make first-time Windows bootstrap fully noninteractive

The initial Windows setup flow still required a workaround through the generated
setup plan because plain noninteractive bootstrap would not complete cleanly in
automation.

### 5. Emit a machine-readable package/version lock report

A generated report of exact installed MSYS2 package versions would make
working-box vs failing-box comparison much easier for downstream troubleshooting.

## Bottom Line

`gnustep-cli` did not completely fail on Windows. It produced a partially
working environment. But for a real downstream packaging workflow, it did not
yet guarantee a coherent enough toolchain to be trusted as a release-ready
Windows build environment.
