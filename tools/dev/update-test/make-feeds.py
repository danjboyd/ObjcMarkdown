#!/usr/bin/env python3
"""Builds private update feeds for testing the Linux updater (#114).

Usage: make-feeds.py <rc.AppImage> <rc.update-feed.json> <out-dir>

<rc.update-feed.json> is the feed the release job attached to the rc's
GitHub release, signed with the real key. Nothing here touches the published
feed: everything goes in <out-dir>, served on the test machine by serve.py.

<out-dir>/www holds:
  ObjcMarkdown/updates/linux/stable.json
      For the released 0.2.0 AppImage, which has no feed override: served as
      https://danjboyd.github.io (an /etc/hosts entry and the throwaway CA in
      <out-dir>/tls), offering the rc as it is.
  feeds/signed.json      the rc AppImage as version <rc>.uat, with the
                         release job's signature (the payload's bytes are
                         what is signed, not the version)
  feeds/unsigned.json    the same, without edSignature
  feeds/wrong-key.json   the same, signed with a throwaway key
  feeds/tampered.json    a changed copy of the AppImage, with its own sha256
                         and size but the real signature, so only the
                         signature check can refuse it
For the rc: GP_UPDATER_FEED_URL=http://127.0.0.1:8765/feeds/<name>.json
"""

import base64
import copy
import hashlib
import json
import os
import shutil
import subprocess
import sys

HTTP_BASE = "http://127.0.0.1:8765"
PAGES_BASE = "https://danjboyd.github.io"
HERE = os.path.dirname(os.path.abspath(__file__))
SIGNER = os.path.join(HERE, "..", "..", "..", "packaging", "ci", "sign-update-feed.py")
PKCS8_SEED_OFFSET = 16


def run(arguments, **kwargs):
    subprocess.run(arguments, check=True, **kwargs)


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def write_json(path, value):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(value, handle, indent=2)
        handle.write("\n")


def place(source, destination):
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    if os.path.exists(destination):
        os.remove(destination)
    try:
        os.link(source, destination)
    except OSError:
        shutil.copyfile(source, destination)


def appimage_asset(feed):
    for release in feed.get("releases", []):
        for asset in release.get("assets", []):
            if asset.get("kind") == "appimage":
                return release, asset
    sys.exit("make-feeds: the feed has no AppImage asset.")


def test_version(version):
    if "-" in version:
        return version + ".uat"
    major, minor, patch = (version.split(".") + ["0", "0"])[:3]
    return "%s.%s.%d-uat" % (major, minor, int(patch) + 1)


def one_release_feed(feed, release, asset):
    result = copy.deepcopy(feed)
    release = copy.deepcopy(release)
    release["assets"] = [asset]
    result["releases"] = [release]
    return result


def plain_asset(asset, url, path):
    asset = copy.deepcopy(asset)
    # No zsync or update information, so the download path is the one tested.
    for key in ("zsync", "updateInformation"):
        asset.pop(key, None)
    asset["url"] = url
    asset["sha256"] = sha256(path)
    asset["sizeBytes"] = os.path.getsize(path)
    return asset


def make_tls(tls_dir):
    os.makedirs(tls_dir, exist_ok=True)
    ca_key, ca = os.path.join(tls_dir, "ca.key"), os.path.join(tls_dir, "ca.pem")
    key, csr, cert = (os.path.join(tls_dir, n) for n in ("server.key", "server.csr", "server.pem"))
    ext = os.path.join(tls_dir, "server.ext")
    if os.path.exists(cert):
        return
    run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "30",
         "-subj", "/CN=ObjcMarkdown update test CA", "-keyout", ca_key, "-out", ca],
        stderr=subprocess.DEVNULL)
    run(["openssl", "req", "-newkey", "rsa:2048", "-nodes", "-subj", "/CN=danjboyd.github.io",
         "-keyout", key, "-out", csr], stderr=subprocess.DEVNULL)
    with open(ext, "w") as handle:
        handle.write("subjectAltName=DNS:danjboyd.github.io\nextendedKeyUsage=serverAuth\n")
    run(["openssl", "x509", "-req", "-in", csr, "-CA", ca, "-CAkey", ca_key, "-CAcreateserial",
         "-days", "30", "-extfile", ext, "-out", cert], stderr=subprocess.DEVNULL)


def throwaway_seed(key_dir):
    os.makedirs(key_dir, exist_ok=True)
    path = os.path.join(key_dir, "throwaway.pem")
    if not os.path.exists(path):
        run(["openssl", "genpkey", "-algorithm", "ed25519", "-out", path])
    der = subprocess.run(["openssl", "pkey", "-in", path, "-outform", "DER"],
                         check=True, capture_output=True).stdout
    return base64.b64encode(der[PKCS8_SEED_OFFSET:PKCS8_SEED_OFFSET + 32]).decode("ascii")


def main():
    if len(sys.argv) != 4:
        sys.stderr.write(__doc__)
        sys.exit(2)
    rc_appimage, rc_feed_path, out = (os.path.abspath(p) for p in sys.argv[1:])
    with open(rc_feed_path, "r", encoding="utf-8-sig") as handle:
        rc_feed = json.load(handle)
    release, asset = appimage_asset(rc_feed)
    name = asset["name"]
    if asset.get("sha256") != sha256(rc_appimage):
        sys.exit("make-feeds: %s is not the feed's %s (sha256 differs)." % (rc_appimage, name))
    if not asset.get("edSignature"):
        print("make-feeds: warning: the rc feed has no edSignature; signed.json will be unsigned.")
    www = os.path.join(out, "www")

    # 0.2.0 -> rc, as the stable feed would offer it.
    path = os.path.join(www, "ObjcMarkdown", "uat", name)
    place(rc_appimage, path)
    url = PAGES_BASE + "/ObjcMarkdown/uat/" + name
    write_json(os.path.join(www, "ObjcMarkdown", "updates", "linux", "stable.json"),
               one_release_feed(rc_feed, release, plain_asset(asset, url, path)))

    # rc -> <rc>.uat, the same bytes.
    uat_release = dict(release, version=test_version(release["version"]))
    path = os.path.join(www, "payload", "good", name)
    place(rc_appimage, path)
    good = plain_asset(asset, HTTP_BASE + "/payload/good/" + name, path)
    signed = one_release_feed(rc_feed, uat_release, good)
    write_json(os.path.join(www, "feeds", "signed.json"), signed)

    unsigned = copy.deepcopy(signed)
    unsigned["releases"][0]["assets"][0].pop("edSignature", None)
    write_json(os.path.join(www, "feeds", "unsigned.json"), unsigned)

    wrong = os.path.join(www, "feeds", "wrong-key.json")
    write_json(wrong, unsigned)
    environment = dict(os.environ, UPDATE_ED_PRIVATE_KEY=throwaway_seed(os.path.join(out, "key")))
    environment.pop("UPDATE_ED_PUBLIC_KEY", None)
    run([sys.executable, SIGNER, wrong, os.path.dirname(path)], env=environment)

    tampered_path = os.path.join(www, "payload", "tampered", name)
    os.makedirs(os.path.dirname(tampered_path), exist_ok=True)
    if os.path.exists(tampered_path):
        os.remove(tampered_path)
    shutil.copyfile(rc_appimage, tampered_path)
    with open(tampered_path, "ab") as handle:
        handle.write(b"\0")
    tampered = one_release_feed(rc_feed, uat_release,
                                plain_asset(asset, HTTP_BASE + "/payload/tampered/" + name, tampered_path))
    write_json(os.path.join(www, "feeds", "tampered.json"), tampered)

    make_tls(os.path.join(out, "tls"))
    print("Feeds in %s for %s (rc %s, test version %s)" % (www, name, release["version"], uat_release["version"]))


if __name__ == "__main__":
    main()
