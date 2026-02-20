#!/usr/bin/env bash
set -euo pipefail

OUT_PATH="${1:-/tmp/open-icon.png}"
PROMPT="Simple open-folder toolbar icon, flat monochrome, dark-theme friendly, high contrast, no text, transparent background."

if [ -z "${OPENAI_API_KEY:-}" ]; then
  echo "OPENAI_API_KEY is not set" >&2
  exit 1
fi

TMP_JSON="$(mktemp)"
cleanup() {
  rm -f "$TMP_JSON"
}
trap cleanup EXIT

curl -sS https://api.openai.com/v1/images/generations \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"gpt-image-1\",
    \"prompt\": \"${PROMPT}\",
    \"size\": \"1024x1024\",
    \"background\": \"transparent\"
  }" \
  -o "$TMP_JSON"

python3 - <<'PY' "$TMP_JSON" "$OUT_PATH"
import base64
import json
import sys

src = sys.argv[1]
out_path = sys.argv[2]

with open(src, "r", encoding="utf-8") as fh:
    data = json.load(fh)

if "data" not in data or not data["data"]:
    raise SystemExit("No image data returned. Response was: %r" % data)

b64 = data["data"][0].get("b64_json")
if not b64:
    raise SystemExit("Missing b64_json in response. Response was: %r" % data)

with open(out_path, "wb") as out:
    out.write(base64.b64decode(b64))

print("Wrote %s" % out_path)
PY
