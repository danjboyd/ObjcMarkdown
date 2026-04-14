# Windows MSYS2 clang64 `mode_t` Header Bug

## Summary

A clean `windows-msys2-clang64` environment currently fails to compile even a
minimal GNUstep AppKit source file because `dispatch`'s Windows support header
redefines `mode_t` after the MinGW CRT already defined it.

This is reproducible on a fresh OracleTestVMs Windows 2022 lease after a clean
managed `gnustep-cli` bootstrap and a full MSYS2 package install.

## Minimal Reproduction

Source file:

```objc
#import <AppKit/AppKit.h>
int main(void) { return 0; }
```

Compile command inside the clean `clang64` GNUstep shell:

```sh
source /clang64/share/GNUstep/Makefiles/GNUstep.sh
clang -fsyntax-only $(gnustep-config --objc-flags) /c/Users/otvmbootstrap/appkit-probe.m
```

Observed failure:

```text
In file included from C:/msys64/clang64/include/AppKit/AppKit.h:40:
In file included from C:/msys64/clang64/include/Foundation/Foundation.h:199:
In file included from C:/msys64/clang64/include/dispatch/dispatch.h:30:
C:/msys64/clang64/include/os/generic_win_base.h:28:13: error:
typedef redefinition with different types ('int' vs '_mode_t'
(aka 'unsigned short'))
typedef int mode_t;
            ^
C:/msys64/clang64/include/sys/types.h:77:17: note: previous definition is here
typedef _mode_t mode_t;
                ^
```

## Header Interaction

On the failing clean VM:

- `C:/msys64/clang64/include/GNUstepBase/GSConfig.h` includes `sys/types.h`
  early.
- `C:/msys64/clang64/include/sys/types.h` defines `mode_t` as `_mode_t`.
- `C:/msys64/clang64/include/Foundation/Foundation.h` later includes
  `dispatch/dispatch.h`.
- `C:/msys64/clang64/include/os/generic_win_base.h` still contains:

```c
#ifndef HAVE_MODE_T
typedef int mode_t;
#endif
```

`HAVE_MODE_T` is not defined in this header path, so the second typedef fires
and clang correctly rejects the conflicting definition.

## Why This Matters

This is not just a theme-repo problem. It breaks any downstream source path
that imports AppKit/Foundation and reaches `dispatch/dispatch.h` in the current
Windows `clang64` GNUstep stack.

For `ObjcMarkdown`, it blocked:

- `plugins-themes-win11theme`
- `plugins-themes-winuitheme`
- `plugins-themes-WinUXTheme`

and therefore blocked shipping the intended Windows themes in the MSI.

## Temporary Workaround

Passing `-DHAVE_MODE_T=1` avoids the bad typedef and allows the same clean VM to
compile successfully.

The same AppKit probe succeeds with:

```sh
clang -fsyntax-only -DHAVE_MODE_T=1 $(gnustep-config --objc-flags) /c/Users/otvmbootstrap/appkit-probe.m
```

`plugins-themes-win11theme` also builds successfully on the same clean managed
VM when `-DHAVE_MODE_T=1` is injected into the build flags.

## Requested Fix

One of these layers needs to be corrected upstream:

1. `os/generic_win_base.h` should not typedef `mode_t` when the active CRT
   headers already provide it.
2. The Windows header path should define `HAVE_MODE_T` consistently before
   `dispatch/dispatch.h` reaches `generic_win_base.h`.
3. If there is an intended include-order contract, it should be made robust
   enough that a normal GNUstep AppKit compile on `clang64` does not depend on
   fragile ordering assumptions.

## Acceptance Test

On a fresh Windows 2022 VM with the managed `windows-msys2-clang64` toolchain:

1. Bootstrap the toolchain from scratch.
2. Run the AppKit probe above without any local patches or extra defines.
3. Confirm the compile succeeds without needing `-DHAVE_MODE_T=1`.
