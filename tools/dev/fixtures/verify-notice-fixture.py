#!/usr/bin/env python3
"""Review draft: source hashes and static ELF inspection; no target execution."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def build_id(path):
    text = subprocess.check_output(['readelf', '-n', str(path)], text=True)
    ids = re.findall(r'Build ID: ([0-9a-f]+)', text)
    if len(ids) != 1:
        raise ValueError('missing/ambiguous BuildID: ' + str(path))
    return ids[0]

def inputs(review, source):
    manifest = review / 'omd389-fixture-source-manifest.json'
    assert sha(manifest) == '63f2af60630343729afc3ccb58bd20e89980f632aa0c27a1ed7b7e9466ed6621'
    data = json.loads(manifest.read_text())
    assert data['target_head'] == '572df1ad9b6898f606d161c763b607bb5a2d35b7'
    assert subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip() == data['target_head']
    for rel, expected in data['production_source_sha256'].items():
        p = source / rel
        assert p.is_file() and not p.is_symlink() and sha(p) == expected, rel
    for rel, expected in data['fixture_sha256'].items():
        p = review / Path(rel).name
        assert p.is_file() and not p.is_symlink() and sha(p) == expected, rel

def cohort(work, app, output):
    runtime = work / 'payload/usr/runtime'
    library = runtime / 'System/Library/Libraries'
    required = ['libgnustep-base.so.1.31.1', 'libgnustep-gui.so.0.32.0', 'libobjc.so.4.6', 'libdispatch.so', 'libBlocksRuntime.so']
    files = []
    for name in required:
        p = library / name
        assert p.exists(), name
        files.append(p.resolve(strict=True))
    backs = list((runtime / 'System/Library/Bundles').glob('libgnustep-back-*.bundle/libgnustep-back-*'))
    backs = [p.resolve() for p in backs if p.is_file() and p.read_bytes()[:4] == b'\x7fELF']
    assert backs, 'no packaged back ELF'
    files += backs
    records = []
    for i, payload in enumerate(sorted(set(files))):
        rel = payload.relative_to(runtime)
        sdk = Path('/usr/GNUstep') / rel
        assert sdk.is_file(), str(sdk)
        temp = work / ('sdk-strip-copy-' + str(i))
        shutil.copyfile(sdk, temp)
        subprocess.run(['strip', '--strip-debug', str(temp)], check=True)
        sdk_id, payload_id = build_id(sdk), build_id(payload)
        assert sdk_id == payload_id, str(rel) + ' BuildID mismatch'
        assert sha(temp) == sha(payload), str(rel) + ' stripped SDK/payload byte mismatch'
        records.append({'relative_path':str(rel),'sdk_sha256':sha(sdk),'payload_sha256':sha(payload),'sdk_strip_debug_sha256':sha(temp),'build_id':sdk_id})
    pinned = {'libgnustep-base.so.1.31.1':'1dcaf2a1c74708c1ce0b6e6cdcdcd5a98572e1b79f46d42d8ebf41855aaec198','libgnustep-gui.so.0.32.0':'0e9348064a103ee65d9de2b60d9eac1334bb1a8825f0b21b83f769d26be4a593'}
    for name, expected in pinned.items():
        assert sha(library / name) == expected, name
    theme = runtime / 'System/Library/Themes/Adwaita.theme/Adwaita'
    assert sha(theme) == '6bb51ff0eaa85c12655f7c4b5ece63c0d429a6c093a26f10f2dd6248a435c2d7'
    headers = Path('/usr/GNUstep/System/Library/Headers')
    header_hashes = {str(p.relative_to(headers)):sha(p) for p in sorted(headers.rglob('*.h')) if p.is_file()}
    assert header_hashes, 'SDK header inventory empty'
    output.write_text(json.dumps({'libraries':records,'sdk_headers':header_hashes,'fixture_build_id':build_id(app/'OMDShareNoticeFixture'),'theme_sha256':sha(theme),'adwaita_commit':'d27427234a861093405715a795a1da51c542a989'},indent=2)+'\n')

if __name__ == '__main__':
    if sys.argv[1] == 'inputs':
        inputs(Path(sys.argv[2]), Path(sys.argv[3]))
    elif sys.argv[1] == 'cohort':
        cohort(Path(sys.argv[2]), Path(sys.argv[3]), Path(sys.argv[4]))
    else:
        raise ValueError('unknown inspection mode')
