#!/usr/bin/env bash
set -euo pipefail

INPUT_JSON_FILE="$(mktemp)"
trap 'rm -f -- "$INPUT_JSON_FILE"' EXIT
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
    ".prompt": ("prompt",),
    ".cwd": ("cwd",),
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

write_marker() {
  local marker_path="$1"
  local session_id="$2"
  local project_dir="$3"
  local handoff_path="$4"
  local needs_inject="$5"
  local origin="$6"

  local timestamp
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  local tmp_marker
  tmp_marker="$(mktemp "/tmp/.claude-handoff-marker.${session_id}.XXXXXX")"

  if has_cmd jq; then
    jq -n \
      --arg session_id "$session_id" \
      --arg project_dir "$project_dir" \
      --arg handoff_path "$handoff_path" \
      --arg origin "$origin" \
      --arg created_at "$timestamp" \
      --argjson needs_inject "$needs_inject" \
      '{
        version: 1,
        session_id: $session_id,
        project_dir: $project_dir,
        handoff_path: $handoff_path,
        needs_inject: $needs_inject,
        needs_model_sections: true,
        attempts: 0,
        origin: $origin,
        created_at: $created_at
      }' >"$tmp_marker"
    mv "$tmp_marker" "$marker_path"
    return 0
  fi

  if has_cmd python3; then
    python3 - "$tmp_marker" "$session_id" "$project_dir" "$handoff_path" "$needs_inject" "$origin" "$timestamp" <<'PY'
import json
import sys

output_path, session_id, project_dir, handoff_path, needs_inject, origin, created_at = sys.argv[1:8]
data = {
    "version": 1,
    "session_id": session_id,
    "project_dir": project_dir,
    "handoff_path": handoff_path,
    "needs_inject": needs_inject.lower() == "true",
    "needs_model_sections": True,
    "attempts": 0,
    "origin": origin,
    "created_at": created_at,
}
with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle)
PY
    mv "$tmp_marker" "$marker_path"
    return 0
  fi

  rm -f -- "$tmp_marker"
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
  local tmp_marker
  tmp_marker="$(mktemp "/tmp/.claude-handoff-marker-update.${field}.XXXXXX")"

  if has_cmd jq; then
    jq --arg field "$field" --argjson value "$value_json" '
      .[$field] = $value
    ' "$marker_path" >"$tmp_marker"
    mv "$tmp_marker" "$marker_path"
    return 0
  fi

  if has_cmd python3; then
    python3 - "$marker_path" "$field" "$value_json" "$tmp_marker" <<'PY' >/dev/null 2>&1 || true
import json
import sys

marker_path, field, value_json, output_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(marker_path, "r", encoding="utf-8") as f:
    data = json.load(f)
data[field] = json.loads(value_json)
with open(output_path, "w", encoding="utf-8") as f:
    json.dump(data, f)
PY
    mv "$tmp_marker" "$marker_path"
    return 0
  fi

  rm -f -- "$tmp_marker"
}

session_id="$(json_get '.session_id')"
prompt_text="$(json_get '.prompt')"
cwd_from_input="$(json_get '.cwd')"

if [[ -z "${session_id:-}" ]]; then
  exit 0
fi

marker_path="/tmp/claude-handoff-marker-${session_id}.json"

project_dir="${CLAUDE_PROJECT_DIR:-${cwd_from_input:-$(pwd)}}"
handoff_path="${project_dir}/docs/handoff/HANDOFF.md"

if [[ "${prompt_text:-}" =~ ^/handoff:create(\s|$) ]]; then
  write_marker "$marker_path" "$session_id" "$project_dir" "$handoff_path" "false" "handoff_create"
  exit 0
fi

if [[ ! -r "$marker_path" ]]; then
  exit 0
fi

needs_inject="false"
if has_cmd jq; then
  needs_inject="$(jq -r '.needs_inject // false' "$marker_path" 2>/dev/null || echo "false")"
elif has_cmd python3; then
  needs_inject="$(python3 - "$marker_path" <<'PY' 2>/dev/null || echo "false"
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)
sys.stdout.write("true" if data.get("needs_inject") else "false")
PY
)"
fi

if [[ "$needs_inject" != "true" ]]; then
  exit 0
fi

if [[ ! -r "$handoff_path" ]]; then
  exit 0
fi

printf '%s\n' '## Auto-injected handoff (after compaction)'
printf '%s\n\n' 'Use the following as the source of truth for resuming work.'
extract_latest_entry "$handoff_path"

set_marker_field "$marker_path" "needs_inject" "false"
