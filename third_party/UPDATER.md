# The updater (GPUpdaterCore, GPUpdaterUI, gp-update-helper)

`GPUpdaterCore/`, `GPUpdaterUI/` and `gp-update-helper/` are copies of
`updater/objc/` in [danjboyd/gnustep-packager](https://github.com/danjboyd/gnustep-packager),
the Linux and Windows updater (macOS uses Sparkle).

- Source: gnustep-packager `updater/objc` at `7d7edc0` (branch
  `updater-helper-temp-copy`; update this line to the commit on its main once
  that is merged).
- Copied: `Headers/` and `Source/` of each, unchanged.
- Ours: the `GNUmakefile`s, which build them with gnustep-make as part of this
  tree (the packager's own `Makefile`s are not copied).

Change the updater in gnustep-packager first, then copy the files here and
update the source commit above.
