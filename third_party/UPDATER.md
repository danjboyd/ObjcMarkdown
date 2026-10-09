# The updater (GPUpdaterCore, GPUpdaterUI, gp-update-helper)

`GPUpdaterCore/`, `GPUpdaterUI/` and `gp-update-helper/` are copies of
`updater/objc/` in [danjboyd/gnustep-packager](https://github.com/danjboyd/gnustep-packager),
the Linux and Windows updater (macOS uses Sparkle).

- Source: gnustep-packager `updater/objc` at `142d46a` (danjboyd/gnustep-packager#9,
  downloads that follow redirects, through WinHTTP on Windows), merged to its
  main as `a251f2e`; the same on `84694a3`, which the packaging pins.
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
