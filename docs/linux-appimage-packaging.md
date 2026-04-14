# Linux AppImage Packaging

Linux release packaging now goes through the reusable
`gnustep-packager` workflow and the downstream manifest at
[packaging/manifests/linux-appimage.manifest.json](../packaging/manifests/linux-appimage.manifest.json).

## Current Flow

The GitHub Actions entry point is
[linux-appimage.yml](../.github/workflows/linux-appimage.yml).

That workflow now:

1. Resolves the release version from the dispatch input or pushed tag.
2. Calls the reusable `gnustep-packager` workflow pinned to commit
   `fb29ee4ef61ecfcc8e7e0c8ee0b690883351324c`.
3. Runs repo-owned Linux preflight from
   [packaging/ci/preflight-appimage.sh](../packaging/ci/preflight-appimage.sh)
   on the self-hosted GNUstep runner.
4. Builds with
   [packaging/scripts/build-linux.sh](../packaging/scripts/build-linux.sh).
5. Stages the normalized `app/`, `runtime/`, and `metadata/` payload with
   [packaging/scripts/stage-linux-runtime.sh](../packaging/scripts/stage-linux-runtime.sh).
6. Lets `gnustep-packager` render the AppDir, generate `AppRun`, package the
   AppImage, run strict runtime-closure validation, and execute smoke launch.
7. On pushed tags, downloads the uploaded `objcmarkdown-linux-packages`
   artifact and publishes the `.AppImage`, `.AppImage.zsync`, and generated
   sidecars to the matching GitHub Release.

## Staged Layout

The repo-owned Linux stage root is:

- `app/`
  `MarkdownViewer.app` plus app-private project libraries under `app/lib`
- `runtime/`
  GNUstep libraries, bundles, tools, Adwaita theme payload, fontconfig data,
  glib schemas, bundled `pandoc`, and native dependency closure
- `metadata/`
  icon assets, packaging docs, and the sample smoke document

The launch policy is now manifest-driven instead of relying on a repo-local
`AppRun` wrapper:

- `GSTheme=Adwaita` with `ifUnset`
- GNUstep roots pointed at the packaged `runtime/`
- `LD_LIBRARY_PATH` seeded from packaged app/runtime library roots
- `PANDOC_DATA_DIR` and related app variables pointed at the bundled payload

## Theme Input

The Linux preflight keeps the packaged Adwaita theme pinned to:

- repository: `danjboyd/plugins-themes-Adwaita`
- commit: `9d455f67587242400f6620a0e8884084850d1204`

The stage script also supports a local fallback checkout at
`../gnustep/plugins-themes-adwaita` when working outside CI.

## Local Commands

Build and test the repo first:

```bash
scripts/ci/run-linux-ci.sh
```

Then run the packager pipeline locally:

```bash
pwsh ../gnustep/gnustep-packager/scripts/run-packaging-pipeline.ps1 \
  -Manifest packaging/manifests/linux-appimage.manifest.json \
  -Backend appimage \
  -RunSmoke
```

For an extra repo-side inspection pass on the produced artifact:

```bash
./scripts/linux/validate-appimage.sh \
  dist/packaging/linux/packages/ObjcMarkdown-0.1.1-rc2-linux-x86_64.AppImage
```

For clean-machine checks on Debian, use
[linux-debian-vm-validation.md](linux-debian-vm-validation.md).
