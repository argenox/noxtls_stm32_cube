#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-pack.sh [--output-dir <dir>] [--pdsc <path>]

Creates a CMSIS pack archive from the current staged pack content in NoxTLS/Files.
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
pdsc_path="$repo_root/NoxTLS/Files/Argenox.NoxTLS.pdsc"
output_dir="$repo_root/artifacts/pack"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --output-dir)
      [[ "$#" -ge 2 ]] || { echo "Error: --output-dir requires an argument." >&2; exit 1; }
      output_dir="$2"
      shift 2
      ;;
    --pdsc)
      [[ "$#" -ge 2 ]] || { echo "Error: --pdsc requires an argument." >&2; exit 1; }
      pdsc_path="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

[[ -f "$pdsc_path" ]] || { echo "Error: PDSC file not found: $pdsc_path" >&2; exit 1; }

pack_root="$(cd "$(dirname "$pdsc_path")" && pwd)"
pack_meta="$(python3 - "$pdsc_path" <<'PY'
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
tree = ET.parse(path)
root = tree.getroot()
vendor = (root.findtext("vendor") or "").strip()
name = (root.findtext("name") or "").strip()
releases = root.findall("./releases/release")
if not vendor or not name:
    raise SystemExit("Missing <vendor> or <name> in PDSC.")
if not releases:
    raise SystemExit("Missing <release> entry in PDSC.")
version = (releases[0].get("version") or "").strip()
if not version:
    raise SystemExit("Latest <release> entry is missing version attribute.")
print(f"{vendor}|{name}|{version}")
PY
)"

vendor="${pack_meta%%|*}"
rest="${pack_meta#*|}"
name="${rest%%|*}"
version="${rest#*|}"

mkdir -p "$output_dir"

pack_filename="${vendor}.${name}.${version}.pack"
pdsc_filename="${vendor}.${name}.pdsc"
pack_path="$output_dir/$pack_filename"
pdsc_out_path="$output_dir/$pdsc_filename"

rm -f "$pack_path" "$pdsc_out_path"
cp -f "$pdsc_path" "$pdsc_out_path"

python3 - "$pack_root" "$pack_path" <<'PY'
import os
import sys
import zipfile

root = sys.argv[1]
out = sys.argv[2]

with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for dirpath, _, filenames in os.walk(root):
        filenames.sort()
        rel_dir = os.path.relpath(dirpath, root)
        for filename in filenames:
            src = os.path.join(dirpath, filename)
            rel = filename if rel_dir == "." else os.path.join(rel_dir, filename)
            rel = rel.replace("\\", "/")
            zf.write(src, rel)

print(out)
PY

echo "Generated pack: $pack_path"
