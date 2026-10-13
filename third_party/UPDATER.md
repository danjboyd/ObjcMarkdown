# The updater (GPUpdaterCore, GPUpdaterUI, gp-update-helper)

`GPUpdaterCore/`, `GPUpdaterUI/` and `gp-update-helper/` are copies of
`updater/objc/` in [danjboyd/gnustep-packager](https://github.com/danjboyd/gnustep-packager),
the Linux and Windows updater (macOS uses Sparkle).

- Source: gnustep-packager `updater/objc` at `7aaf72d` (its main). On Windows
  that brings #20 (the helper takes certutil and msiexec from the system
  directory and finds `Path` regardless of case; every updater alert runs
  from a fresh run-loop pass, since `runModal` entered from a
  `performSelectorOnMainThread:` callback never paints on the win32 backend)
  and #21 (the helper hands the install to an `apply-msi.cmd` run by the
  system `cmd.exe`, which runs msiexec with backslash paths, records the
  result and relaunches the app, so msiexec's Restart Manager has no helper
  to stop). Before that, `142d46a` (#9, downloads that follow redirects,
  through WinHTTP on Windows). The packaging pins `84694a3`, which builds the
  packages but not this copy.
- Copied: `Headers/` and `Source/` of each, unchanged. The helper's
  `Source/monocypher/` is Monocypher 4.0.2 (CC0), which checks the update
  payloads' Ed25519 signatures; its README there gives the tarball's hash.
- Ours: the `GNUmakefile`s, which build them with gnustep-make as part of this
  tree (the packager's own `Makefile`s are not copied). The helper builds
  `GPUpdaterCore/Source/GPUpdaterDownload.m` and `GPUpdaterWinHTTP.c` itself,
  and both link `-lwinhttp` on Windows.
- Signing: `packaging/ci/sign-update-feed.py` adds each payload's
  `edSignature` to the feed in the release jobs, with the key Sparkle signs the
  macOS updates with (`SPARKLE_ED_PRIVATE_KEY`); the public key is
  `SUPublicEDKey` in `macos/Info.plist`.

Change the updater in gnustep-packager first, then copy the files here and
update the source commit above.
