#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: sync-noxtls.sh [--skip-pdsc-update]

Sync curated NoxTLS files from third_party/noxtls into NoxTLS/Files:
- copies headers and sources into Include/ and Source/
- excludes test_*.c
- copies upstream licensing docs into ThirdParty/noxtls
- updates file entries in both PDSC files between SYNC_NOXTLS markers
EOF
}

skip_pdsc_update=0
if [[ "${1-}" == "--skip-pdsc-update" ]]; then
  skip_pdsc_update=1
  shift
fi

if [[ "$#" -ne 0 ]]; then
  usage
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
upstream_root="$repo_root/third_party/noxtls"
upstream_lib_root="$upstream_root/noxtls-lib"
upstream_utility_root="$upstream_root/utility"
pack_root="$repo_root/NoxTLS/Files"
include_root="$pack_root/Include"
source_root="$pack_root/Source"
third_party_root="$pack_root/ThirdParty/noxtls"
original_pack_root="$repo_root/NoxTLS/.project/OriginalPack"
pdsc_paths=(
  "$repo_root/NoxTLS/Files/Argenox.NoxTLS.pdsc"
  "$repo_root/NoxTLS/.project/Argenox.NoxTLS.pdsc"
)
project_file_xml_path="$repo_root/NoxTLS/.project/projectFile.xml"

begin_marker="<!-- SYNC_NOXTLS_BEGIN -->"
end_marker="<!-- SYNC_NOXTLS_END -->"

assert_exists() {
  local path="$1"
  local message="$2"
  [[ -e "$path" ]] || { echo "Error: $message" >&2; exit 1; }
}

clear_directory() {
  local path="$1"
  mkdir -p "$path"
  find "$path" -mindepth 1 -exec rm -rf {} +
}

mirror_directory() {
  local source_path="$1"
  local destination_path="$2"
  mkdir -p "$destination_path"
  find "$destination_path" -mindepth 1 -exec rm -rf {} +
  cp -a "$source_path/." "$destination_path/"
}

copy_with_relative_path() {
  local file="$1"
  local base="$2"
  local dest_root="$3"
  local rel dest

  rel="${file#"$base"/}"
  dest="$dest_root/$rel"
  mkdir -p "$(dirname "$dest")"
  cp -f "$file" "$dest"
}

to_pack_relative() {
  local path="$1"
  local rel="${path#"$pack_root"/}"
  rel="${rel#/}"
  printf '%s' "${rel//\\//}"
}

update_pdsc_file_list() {
  local pdsc_path="$1"
  local generated_lines_file="$2"
  local tmp_file

  if ! grep -q "$begin_marker" "$pdsc_path" || ! grep -q "$end_marker" "$pdsc_path"; then
    echo "Warning: Skipping PDSC auto-update for $pdsc_path because SYNC_NOXTLS markers are missing." >&2
    return 1
  fi

  tmp_file="$(mktemp)"

  awk -v begin="$begin_marker" -v end="$end_marker" -v lines_file="$generated_lines_file" '
    BEGIN { in_sync_block = 0; inserted = 0 }
    {
      if (index($0, begin)) {
        print $0
        while ((getline line < lines_file) > 0) {
          print line
        }
        close(lines_file)
        in_sync_block = 1
        inserted = 1
        next
      }
      if (index($0, end)) {
        in_sync_block = 0
        print $0
        next
      }
      if (!in_sync_block) {
        print $0
      }
    }
    END {
      if (!inserted) {
        exit 2
      }
    }
  ' "$pdsc_path" > "$tmp_file" || {
    rm -f "$tmp_file"
    echo "Warning: failed to update sync block in $pdsc_path; leaving file unchanged." >&2
    return 1
  }

  mv "$tmp_file" "$pdsc_path"
  return 0
}

assert_exists "$upstream_root" "Missing third_party/noxtls. Add/update the submodule first."
assert_exists "$upstream_lib_root" "Missing third_party/noxtls/noxtls-lib."
assert_exists "$upstream_utility_root" "Missing third_party/noxtls/utility."

clear_directory "$include_root"
clear_directory "$source_root"
rm -rf "$third_party_root"
mkdir -p "$third_party_root"

root_headers=(
  "noxtls_common.h"
  "noxtls_config.h"
  "noxtls_check_config.h"
  "noxtls_version.h"
)

for header_name in "${root_headers[@]}"; do
  header_path="$upstream_root/$header_name"
  assert_exists "$header_path" "Missing required header: $header_name"
  cp -f "$header_path" "$include_root/$header_name"
done

while IFS= read -r -d '' header_file; do
  copy_with_relative_path "$header_file" "$upstream_lib_root" "$include_root/noxtls-lib"
done < <(find "$upstream_lib_root" -type f -name '*.h' -print0 | sort -z)

while IFS= read -r -d '' source_file; do
  copy_with_relative_path "$source_file" "$upstream_lib_root" "$source_root/noxtls-lib"
done < <(find "$upstream_lib_root" -type f -name '*.c' ! -name 'test_*.c' -print0 | sort -z)

while IFS= read -r -d '' include_file; do
  copy_with_relative_path "$include_file" "$upstream_lib_root" "$source_root/noxtls-lib"
done < <(find "$upstream_lib_root" -type f -name '*.inc' -print0 | sort -z)

while IFS= read -r -d '' utility_header; do
  copy_with_relative_path "$utility_header" "$upstream_utility_root" "$include_root/utility"
done < <(find "$upstream_utility_root" -type f -name '*.h' -print0 | sort -z)

while IFS= read -r -d '' utility_source; do
  copy_with_relative_path "$utility_source" "$upstream_utility_root" "$source_root/utility"
done < <(find "$upstream_utility_root" -type f -name '*.c' -print0 | sort -z)

assert_exists "$upstream_root/LICENSE.md" "Missing required upstream file: LICENSE.md"
assert_exists "$upstream_root/COPYING.md" "Missing required upstream file: COPYING.md"
assert_exists "$upstream_root/README.md" "Missing required upstream file: README.md"

cp -f "$upstream_root/LICENSE.md" "$third_party_root/LICENSE.md"
cp -f "$upstream_root/COPYING.md" "$third_party_root/COPYING.md"
cp -f "$upstream_root/README.md" "$third_party_root/README.upstream.md"

if [[ "$skip_pdsc_update" -eq 0 ]]; then
  generated_lines_file="$(mktemp)"
  trap 'rm -f "$generated_lines_file"' EXIT

  while IFS= read -r -d '' include_dir; do
    rel_include_dir="$(to_pack_relative "$include_dir")"
    printf '                    <file category="include" name="%s/"/>\n' "$rel_include_dir" >> "$generated_lines_file"
  done < <(find "$include_root" -type d -mindepth 1 -print0 | sort -z)

  while IFS= read -r -d '' synced_header; do
    rel_header="$(to_pack_relative "$synced_header")"
    printf '                    <file category="header" name="%s"/>\n' "$rel_header" >> "$generated_lines_file"
  done < <(find "$include_root" -type f -name '*.h' -print0 | sort -z)

  while IFS= read -r -d '' synced_source; do
    rel_source="$(to_pack_relative "$synced_source")"
    printf '                    <file category="sourceC" name="%s"/>\n' "$rel_source" >> "$generated_lines_file"
  done < <(find "$source_root" -type f -name '*.c' -print0 | sort -z)

  updated_project_pdsc=0
  for pdsc_path in "${pdsc_paths[@]}"; do
    assert_exists "$pdsc_path" "Missing PDSC file: $pdsc_path"
    if update_pdsc_file_list "$pdsc_path" "$generated_lines_file"; then
      if [[ "$pdsc_path" == "${pdsc_paths[1]}" ]]; then
        updated_project_pdsc=1
      fi
    fi
  done

  # STM32PackCreator reads .project/projectFile.xml as project source.
  # Keep it identical to the .project PDSC so GUI reflects synchronized files/components.
  if [[ "$updated_project_pdsc" -eq 1 ]]; then
    assert_exists "${pdsc_paths[1]}" "Missing project PDSC: ${pdsc_paths[1]}"
    cp -f "${pdsc_paths[1]}" "$project_file_xml_path"
  else
    echo "Warning: Skipping projectFile.xml refresh because .project PDSC was not auto-updated." >&2
  fi
fi

# STM32PackCreator resolves sources from .project/OriginalPack during generation.
# Mirror the pack staging tree there so all referenced files exist for GUI generation.
mirror_directory "$pack_root" "$original_pack_root"

header_count="$(find "$include_root" -type f -name '*.h' | wc -l | tr -d ' ')"
source_count="$(find "$source_root" -type f -name '*.c' | wc -l | tr -d ' ')"
echo "Synced NoxTLS into pack staging: $header_count headers, $source_count sources."
