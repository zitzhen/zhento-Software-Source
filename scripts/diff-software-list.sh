#!/usr/bin/env bash
# Emit a JSON matrix of repositories newly added to Software.list relative to
# a base Git revision. The current list is read from the working tree.
set -euo pipefail

if [[ $# -ne 1 && $# -ne 2 ]]; then
  echo "Usage: diff-software-list.sh <base-ref> [software-list-path]" >&2
  exit 1
fi

base_ref="$1"
list_path="${2:-Software.list}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$list_path" ]]; then
  echo "Error: software list not found: $list_path" >&2
  exit 1
fi

tmp_list="$(mktemp)"
trap 'rm -f "$tmp_list"' EXIT

# A missing or unparseable base list means every current entry is treated as new.
: > "$tmp_list"
if ! git show "${base_ref}:${list_path}" > "$tmp_list" 2>/dev/null; then
  : > "$tmp_list"
fi

head_json="$("$script_dir/parse-software-list.sh" "$list_path")"
base_json='[]'
if [[ -s "$tmp_list" ]]; then
  if ! base_json="$("$script_dir/parse-software-list.sh" "$tmp_list" 2>/dev/null)"; then
    echo "Warning: base $list_path could not be parsed; treating all entries as new" >&2
    base_json='[]'
  fi
fi

python3 - "$base_json" "$head_json" <<'PY'
import json
import sys

base = {item["url"] for item in json.loads(sys.argv[1])}
head = json.loads(sys.argv[2])
added = [item for item in head if item["url"] not in base]
print(json.dumps(added, separators=(",", ":")))
PY
