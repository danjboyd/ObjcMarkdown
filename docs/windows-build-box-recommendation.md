# Windows Build Box Recommendation

## Short Answer

You do not need GitHub Actions to publish Windows artifacts for `ObjcMarkdown`.
A local or self-managed Windows build box is acceptable, provided it is:

- reproducible
- not a general-purpose daily driver
- validated against the same packaging and clean-machine test workflow

## Recommended Release Shape

Prefer one of these:

1. A dedicated Windows release box with a pinned, validated MSYS2/GNUstep
   package set.
2. A GitHub Actions Windows workflow with the same pinned package set and the
   same clean-machine validation loop.

Avoid using a personal dev machine as the canonical release box because it is
too easy for local experiments, upgrades, and unrelated tooling drift to change
the packaging result.

## Current Project Implication

Right now the OracleTestVMs Windows build VM is good enough to:

- build the app
- package an MSI
- rebuild the Windows themes with the local `-DHAVE_MODE_T=1` workaround

It is still not the ideal final release environment because that theme build
success currently depends on a local workaround for the upstream
`windows-msys2-clang64` header mismatch rather than on a clean locked package
set.

Until that environment gap is closed, the project should treat the Windows
release path as:

- build on a controlled Windows box
- validate on a separate clean Windows VM
- publish from that controlled box or via CI

## Practical Guidance

If you want to publish from a non-GitHub local build box, make sure it has:

- a pinned MSYS2/GNUstep package set
- a repeatable bootstrap script
- no ad hoc dev-only package drift
- clean-machine validation before release

GitHub Actions is still a strong option because it is easier to make auditable
and repeatable, but it is not strictly required.
