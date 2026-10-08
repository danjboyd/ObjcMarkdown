#!/usr/bin/env python3
"""Signs each asset of a gnustep-packager update feed with Ed25519.

Usage: sign-update-feed.py <feed.json> <asset-directory>

Adds "edSignature" (base64, over the asset file's bytes, as Sparkle's
sign_update makes) to every asset in the feed whose file is in
<asset-directory>; an asset without its file is an error. The private key is
Sparkle's, from UPDATE_ED_PRIVATE_KEY: base64 of the 32-byte seed (or of
seed + public key, 64 bytes). When UPDATE_ED_PUBLIC_KEY is set (base64), the
key's public half must match it, so a wrong secret fails here rather than in
every installed copy. Signs with the openssl command (3.0 or later).
"""

import base64
import json
import os
import subprocess
import sys
import tempfile

# PKCS#8 for an Ed25519 private key, before the 32-byte seed (RFC 8410).
PKCS8_ED25519_PREFIX = bytes.fromhex("302e020100300506032b657004220420")


def fail(message):
    sys.stderr.write("sign-update-feed: " + message + "\n")
    sys.exit(1)


def private_key_pem(seed):
    der = PKCS8_ED25519_PREFIX + seed
    body = base64.encodebytes(der).decode("ascii")
    return "-----BEGIN PRIVATE KEY-----\n" + body + "-----END PRIVATE KEY-----\n"


def openssl(arguments, data=None):
    result = subprocess.run(["openssl"] + arguments, input=data, capture_output=True)
    if result.returncode != 0:
        fail("openssl " + arguments[0] + " failed: " + result.stderr.decode("utf-8", "replace").strip())
    return result.stdout


def main():
    if len(sys.argv) != 3:
        sys.stderr.write(__doc__)
        sys.exit(2)
    feed_path, asset_dir = sys.argv[1], sys.argv[2]

    encoded = os.environ.get("UPDATE_ED_PRIVATE_KEY", "").strip()
    if not encoded:
        fail("UPDATE_ED_PRIVATE_KEY is not set.")
    try:
        key = base64.b64decode(encoded, validate=True)
    except ValueError:
        fail("UPDATE_ED_PRIVATE_KEY is not base64.")
    if len(key) not in (32, 64):
        fail("UPDATE_ED_PRIVATE_KEY must be a 32-byte Ed25519 seed (or seed + public key), not %d bytes." % len(key))
    seed = key[:32]

    with tempfile.TemporaryDirectory() as work:
        key_path = os.path.join(work, "key.pem")
        descriptor = os.open(key_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as handle:
            handle.write(private_key_pem(seed))

        # The public key is the last 32 bytes of its SubjectPublicKeyInfo.
        public_key = openssl(["pkey", "-in", key_path, "-pubout", "-outform", "DER"])[-32:]
        expected = os.environ.get("UPDATE_ED_PUBLIC_KEY", "").strip()
        if expected and base64.b64decode(expected) != public_key:
            fail("the private key's public key is %s, not UPDATE_ED_PUBLIC_KEY." % base64.b64encode(public_key).decode("ascii"))

        with open(feed_path, "r", encoding="utf-8-sig") as handle:
            feed = json.load(handle)

        signed = 0
        for release in feed.get("releases", []):
            for asset in release.get("assets", []):
                name = asset.get("name", "")
                path = os.path.join(asset_dir, os.path.basename(name))
                if not name or not os.path.isfile(path):
                    fail("no file for the feed's asset %r in %s." % (name, asset_dir))
                signature = openssl(["pkeyutl", "-sign", "-inkey", key_path, "-rawin", "-in", path])
                if len(signature) != 64:
                    fail("openssl made a %d-byte signature for %s." % (len(signature), name))
                asset["edSignature"] = base64.b64encode(signature).decode("ascii")
                signed += 1

    if signed == 0:
        fail("the feed has no assets to sign.")

    with open(feed_path, "w", encoding="utf-8") as handle:
        json.dump(feed, handle, indent=2)
        handle.write("\n")
    print("Signed %d asset(s) in %s with public key %s" % (signed, feed_path, base64.b64encode(public_key).decode("ascii")))


if __name__ == "__main__":
    main()
