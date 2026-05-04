#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSET_DIR="$ROOT_DIR/Assets/AppIcon"
SOURCE_PNG="$ASSET_DIR/AppIcon.png"
ICONSET_DIR="$ASSET_DIR/AppIcon.iconset"
ICNS_PATH="$ASSET_DIR/AppIcon.icns"

if [[ ! -f "$SOURCE_PNG" ]]; then
  echo "Missing source icon: $SOURCE_PNG" >&2
  exit 1
fi

width="$(sips -g pixelWidth "$SOURCE_PNG" | awk '/pixelWidth/ {print $2}')"
height="$(sips -g pixelHeight "$SOURCE_PNG" | awk '/pixelHeight/ {print $2}')"

if [[ "$width" != "$height" ]]; then
  echo "App icon source must be square: $SOURCE_PNG is ${width}x${height}" >&2
  exit 1
fi

if [[ "$width" != "1024" ]]; then
  sips -z 1024 1024 "$SOURCE_PNG" --out "$SOURCE_PNG" >/dev/null
fi

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

sips -z 16 16 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

python3 - "$ICONSET_DIR" "$ICNS_PATH" <<'PY'
from pathlib import Path
import struct
import sys

iconset = Path(sys.argv[1])
icns_path = Path(sys.argv[2])
temporary_path = icns_path.with_name(f".{icns_path.name}.tmp")

entries = [
    ("icp4", "icon_16x16.png"),
    ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"),
    ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"),
    ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"),
]

chunks = []
for icon_type, filename in entries:
    data = (iconset / filename).read_bytes()
    chunks.append(icon_type.encode("ascii") + struct.pack(">I", len(data) + 8) + data)

body = b"".join(chunks)
temporary_path.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)
temporary_path.replace(icns_path)
PY

echo "$SOURCE_PNG"
echo "$ICNS_PATH"
