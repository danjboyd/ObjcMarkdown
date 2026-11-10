#!/usr/bin/env bash
# Review draft: build/inspect only. Never invoke fixture, AppRun or viewer.
set -euo pipefail
umask 077
unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS XAUTHORITY
ulimit -f 524288
review=$(realpath "$1")
source_root=$(realpath "$2")
test -d /omd389
work=$(mktemp -d /omd389/work-XXXXXX)
trap 'rm -rf -- "$work"' EXIT
mkdir -m 700 "$work/build" "$work/private" "$work/private/tmp" "$work/private/defaults" "$work/private/Library" "$work/meta"
export TMPDIR="$work/private/tmp" TMP="$work/private/tmp" TEMP="$work/private/tmp"
export XDG_RUNTIME_DIR="$work/private/runtime" XDG_CONFIG_HOME="$work/private/config"
export XDG_DATA_HOME="$work/private/data" XDG_CACHE_HOME="$work/private/cache" XDG_STATE_HOME="$work/private/state"
mkdir -m 700 "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
test -f /etc/GNUstep/GNUstep.conf
cp /etc/GNUstep/GNUstep.conf "$work/private/GNUstep.conf"
cat >> "$work/private/GNUstep.conf" <<EOF
GNUSTEP_USER_CONFIG_FILE=""
GNUSTEP_USER_DEFAULTS_DIR="$work/private/defaults"
GNUSTEP_USER_DIR_LIBRARY="$work/private/Library"
EOF
export GNUSTEP_CONFIG_FILE="$work/private/GNUstep.conf"
python3 "$review/verify-notice-fixture.py" inputs "$review" "$source_root"
cp "$review/OMDShareNoticeFixture.m" "$work/build/"
cp "$review/GNUmakefile.notice-fixture" "$work/build/GNUmakefile"
for name in OMDShareNotice OMDShareItem OMDViewerImages; do
  cp "$source_root/ObjcMarkdownViewer/$name.m" "$work/build/"
done
cp "$source_root/Resources/icons/omd-share-file-symbolic.png" "$work/build/"
cp "$review/omd389-fixture-source-manifest.json" "$work/meta/inputs.json"
cat /usr/GNUstep/ci-toolchain.txt > "$work/meta/ci-toolchain.txt"
clang --version > "$work/meta/compiler.txt"
set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u
gnustep-config --objc-flags > "$work/meta/objc-flags.txt"
gnustep-config --gui-libs > "$work/meta/gui-libs.txt"
printf '%s\n' "gmake -j2 OMD_SOURCE=$source_root" > "$work/meta/command.txt"
gmake -C "$work/build" -j2 "OMD_SOURCE=$source_root" > "$work/meta/build.log" 2>&1
test "$(stat -c %s "$work/meta/build.log")" -le 5242880
app="$work/build/OMDShareNoticeFixture.app"
test -f "$app/OMDShareNoticeFixture"
readelf -n -d "$app/OMDShareNoticeFixture" > "$work/meta/fixture-elf.txt"
nm -u "$app/OMDShareNoticeFixture" > "$work/meta/fixture-undefined.txt"
if grep -Eq 'U [^[:space:]]*OMD' "$work/meta/fixture-undefined.txt"; then exit 1; fi
curl --fail --location --connect-timeout 10 --max-time 120 --max-filesize 68405752 \
  --output "$work/runtime.AppImage" \
  https://github.com/danjboyd/ObjcMarkdown/releases/download/v0.2.7/ObjcMarkdown-0.2.7-linux-x86_64.AppImage
test "$(stat -c %s "$work/runtime.AppImage")" -eq 68405752
printf '%s  %s\n' 52e4bb1bf74d91b443947f5bc24109a5396b3b4fd49faac39279e65e5977b4af "$work/runtime.AppImage" | sha256sum -c -
unsquashfs -no-progress -processors 1 -o 944632 -d "$work/payload" "$work/runtime.AppImage" usr/runtime > "$work/meta/extract.log" 2>&1
python3 "$review/verify-notice-fixture.py" cohort "$work" "$app" "$work/meta/cohort.json"
mkdir -m 700 /omd389/export
python3 - "$work" "$app" <<'PY'
import hashlib,json,os,pathlib,subprocess,sys
w=pathlib.Path(sys.argv[1]); app=pathlib.Path(sys.argv[2]); meta=w/'meta'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
record={'production_head':'572df1ad9b6898f606d161c763b607bb5a2d35b7','sdk_index':'sha256:1494c94dc5e4f4a06e15fffcc646c9be33504450c437eb055e72c9b970716819','sdk_amd64_manifest':'sha256:4534f4dd5e97dc3da47649bf02171039f866de88bf9f8743a5bcb7eddd8bbac5','workflow_commit':os.environ['GITHUB_SHA'],'run_id':os.environ['GITHUB_RUN_ID'],'run_attempt':os.environ['GITHUB_RUN_ATTEMPT'],'fixture_executed':False,'display_started':False,'fixture_elf_sha256':sha(app/'OMDShareNoticeFixture'),'resource_sha256':sha(app/'Resources/omd-share-file-symbolic.png')}
assert record['resource_sha256']=='933988113896104077cbc9bf640d2a09d00dfd97d9bd79e7509b8797899223f3'
(meta/'provenance.json').write_text(json.dumps(record,indent=2)+'\n')
subprocess.run(['tar','--sort=name','--mtime=@0','--owner=0','--group=0','--numeric-owner','-czf','/omd389/export/fixture.tar.gz','-C',str(app.parent),app.name,'-C',str(w),'meta'],check=True)
p=pathlib.Path('/omd389/export/fixture.tar.gz'); assert p.stat().st_size<=10485760
(p.parent/'SHA256SUMS').write_text(sha(p)+'  fixture.tar.gz\n')
PY
