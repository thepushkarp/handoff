#!/usr/bin/env bash
set -euo pipefail

INPUT_JSON_FILE="$(mktemp)"
cat >"$INPUT_JSON_FILE"

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

json_get() {
  local jq_filter="$1"
  if has_cmd jq; then
    jq -r "$jq_filter // empty" "$INPUT_JSON_FILE" 2>/dev/null || true
    return 0
  fi
  if has_cmd python3; then
    python3 - "$jq_filter" <"$INPUT_JSON_FILE" <<'PY' 2>/dev/null || true
import json
import sys

data = json.load(sys.stdin)
f = sys.argv[1]
mapping = {
    ".session_id": ("session_id",),
}
path = mapping.get(f)
if not path:
    sys.exit(0)
cur = data
for key in path:
    if not isinstance(cur, dict) or key not in cur:
        sys.exit(0)
    cur = cur[key]
if cur is None:
    sys.exit(0)
sys.stdout.write(str(cur))
PY
    return 0
  fi
  return 0
}

extract_latest_entry() {
  local handoff_path="$1"
  if [[ ! -r "$handoff_path" ]]; then
    return 0
  fi

  awk '
    { lines[NR] = $0 }
    /^---$/ { sep = NR }
    /^## Handoff:/ { start = (sep ? sep : NR) }
    END {
      if (!start) exit 0
      for (i = start; i <= NR; i++) print lines[i]
    }
  ' "$handoff_path"
}

set_marker_field() {
  local marker_path="$1"
  local field="$2"
  local value_json="$3"

  if [[ ! -r "$marker_path" ]]; then
    return 0
  fi

  if has_cmd jq; then
    jq --arg field "$field" --argjson value "$value_json" '
      .[$field] = $value
    ' "$marker_path" >"${marker_path}.tmp"
    mv "${marker_path}.tmp" "$marker_path"
    return 0
  fi

  if has_cmd python3; then
    python3 - "$marker_path" "$field" "$value_json" <<'PY' >/dev/null 2>&1 || true
import json
import sys

marker_path, field, value_json = sys.argv[1], sys.argv[2], sys.argv[3]
with open(marker_path, "r", encoding="utf-8") as f:
    data = json.load(f)
data[field] = json.loads(value_json)
tmp = marker_path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f)
PY
    mv "${marker_path}.tmp" "$marker_path"
  fi
}

session_id="$(json_get '.session_id')"
if [[ -z "${session_id:-}" ]]; then
  exit 0
fi

marker_path="/tmp/claude-handoff-marker-${session_id}.json"
if [[ ! -r "$marker_path" ]]; then
  exit 0
fi

needs_inject="false"
handoff_path=""
if has_cmd jq; then
  needs_inject="$(jq -r '.needs_inject // false' "$marker_path" 2>/dev/null || echo "false")"
  handoff_path="$(jq -r '.handoff_path // empty' "$marker_path" 2>/dev/null || true)"
elif has_cmd python3; then
  needs_inject="$(python3 - "$marker_path" <<'PY' 2>/dev/null || echo "false"
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)
sys.stdout.write("true" if data.get("needs_inject") else "false")
PY
)"
  handoff_path="$(python3 - "$marker_path" <<'PY' 2>/dev/null || true
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)
v = data.get("handoff_path")
if isinstance(v, str):
    sys.stdout.write(v)
PY
)"
fi

if [[ "$needs_inject" != "true" ]]; then
  exit 0
fi

if [[ -z "${handoff_path:-}" ]]; then
  project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  handoff_path="${project_dir}/docs/handoff/HANDOFF.md"
fi

if [[ ! -r "$handoff_path" ]]; then
  exit 0
fi

printf '%s\n' '## Auto-injected handoff (after compaction)'
printf '%s\n\n' 'Use the following as the source of truth for resuming work.'
extract_latest_entry "$handoff_path"

set_marker_field "$marker_path" "needs_inject" "false"
