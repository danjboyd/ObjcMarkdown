# Update tests on a test machine (#114)

Private update feeds for checking the Linux updater on an installed AppImage,
without touching the published feed. Run on a throwaway VM only: the 0.2.0
case points `danjboyd.github.io` at the VM itself.

## Make the feeds

From the rc's GitHub release, download the AppImage and
`ObjcMarkdown-<rc>-linux-x86_64.update-feed.json` (signed by the release
job), then:

```sh
tools/dev/update-test/make-feeds.py ObjcMarkdown-<rc>-linux-x86_64.AppImage \
    ObjcMarkdown-<rc>-linux-x86_64.update-feed.json ~/uat
sudo tools/dev/update-test/serve.py ~/uat     # --http-only: only port 8765, no root
```

`make-feeds.py` checks the AppImage against the feed's sha256 and says so if
the feed has no signature. Its feeds carry no zsync or update information,
so the updater downloads the payload itself.

| Feed | Offers | Expected with `updates.publicEDKey` |
|---|---|---|
| `ObjcMarkdown/updates/linux/stable.json` | the rc, to 0.2.0 | applies (0.2.0 checks sha256 only) |
| `feeds/signed.json` | the rc's bytes as `<rc>.uat`, real signature | applies, relaunches |
| `feeds/unsigned.json` | the same, no `edSignature` | refused |
| `feeds/wrong-key.json` | the same, signed with a throwaway key | refused |
| `feeds/tampered.json` | the AppImage plus one byte, its own sha256, real signature | refused |

The signature is over the payload's bytes, not its version, so the release
job's signature still holds for the `.uat` version.

## The rc (feed override)

```sh
GP_UPDATER_FEED_URL=http://127.0.0.1:8765/feeds/signed.json ./ObjcMarkdown-<rc>-linux-x86_64.AppImage
```

or, to launch from the desktop as a user would,
`defaults write MarkdownViewer GPUpdaterFeedURL http://127.0.0.1:8765/feeds/signed.json`.
Then: Check for Updates, install, quit, and see whether it relaunches. The
read-only folder and cancelled-Quit (2-minute wait) cases use `signed.json`.

## The released 0.2.0 (no feed override)

0.2.0 reads only `https://danjboyd.github.io/ObjcMarkdown/updates/linux/stable.json`,
so on the VM:

```sh
echo '127.0.0.1 danjboyd.github.io' | sudo tee -a /etc/hosts
defaults write NSGlobalDomain GSTLSCAFile ~/uat/tls/ca.pem
```

If the AppImage's GNUstep doesn't read that default, launch it with
`GS_TLS_CA_FILE=~/uat/tls/ca.pem` instead. Install no `appimageupdatetool` or
`AppImageUpdate`: 0.2.0 prefers them, and they follow the real GitHub
releases. Undo both afterwards.
