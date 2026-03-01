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
    ".transcript_path": ("transcript_path",),
    ".trigger": ("trigger",),
    ".custom_instructions": ("custom_instructions",),
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

extract_last_text_message() {
  local transcript_path="$1"
  local message_type="$2"

  if [[ -z "$transcript_path" || ! -r "$transcript_path" ]]; then
    printf '%s' "(unavailable - transcript missing)"
    return 0
  fi

  if ! has_cmd jq; then
    printf '%s' "(unavailable - jq not installed)"
    return 0
  fi

  tail -n 2000 "$transcript_path" 2>/dev/null \
    | jq -r --arg t "$message_type" '
        select(.type == $t)
        | (.message.content // [])
        | map(select(.type == "text") | .text)
        | join("")
      ' 2>/dev/null \
    | tail -n 1
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
      }' >"${marker_path}.tmp"
    mv "${marker_path}.tmp" "$marker_path"
    return 0
  fi

  cat >"${marker_path}.tmp" <<EOF
{"version":1,"session_id":"$session_id","project_dir":"$project_dir","handoff_path":"$handoff_path","needs_inject":$needs_inject,"needs_model_sections":true,"attempts":0,"origin":"$origin","created_at":"$timestamp"}
EOF
  mv "${marker_path}.tmp" "$marker_path"
}

session_id="$(json_get '.session_id')"
transcript_path="$(json_get '.transcript_path')"
trigger="$(json_get '.trigger')"
custom_instructions="$(json_get '.custom_instructions')"
cwd_from_input="$(json_get '.cwd')"

project_dir="${CLAUDE_PROJECT_DIR:-${cwd_from_input:-$(pwd)}}"
handoff_dir="${project_dir}/docs/handoff"
handoff_path="${handoff_dir}/HANDOFF.md"

mkdir -p "$handoff_dir"

last_user_message="$(extract_last_text_message "$transcript_path" "user")"
last_assistant_message="$(extract_last_text_message "$transcript_path" "assistant")"

timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

{
  printf '%s\n\n' '---'
  printf '## Handoff: %s (auto-saved before compaction)\n\n' "$timestamp"

  printf '%s\n' '### Compaction Metadata'
  printf -- '- Trigger: %s\n' "${trigger:-"(unknown)"}"
  if [[ -n "${custom_instructions:-}" ]]; then
    printf -- '- Custom instructions: %s\n' "$custom_instructions"
  else
    printf -- '- Custom instructions: %s\n' "(none)"
  fi
  printf -- '- Transcript: %s\n' "${transcript_path:-"(unknown)"}"
  printf -- '- CWD: %s\n\n' "${cwd_from_input:-"(unknown)"}"

  printf '%s\n' '### Last User Message (transcript tail)'
  printf '%s\n\n' "${last_user_message:-"(unavailable)"}"

  printf '%s\n' '### Last Assistant Message (transcript tail)'
  printf '%s\n\n' "${last_assistant_message:-"(unavailable)"}"

  printf '%s\n' '### Git Snapshot'
  if git -C "$project_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf -- '- Branch: %s\n' "$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(unknown)")"
    printf '%s\n' '- Status:'
    git -C "$project_dir" status --porcelain=v1 2>/dev/null || true
    printf '%s\n' '- Recent commits:'
    git -C "$project_dir" log -5 --oneline 2>/dev/null || true
  else
    printf '%s\n' '- (not a git repo)'
  fi
  printf '\n'

  printf '%s\n' '### Model Summary'
  printf '%s\n\n' '(TODO: fill after compaction — 8–12 bullets)'

  printf '%s\n' '### Handoff Context (paste into next session)'
  printf '%s\n\n' '(TODO: fill after compaction — 10–20 lines of concrete resume instructions)'

  printf '%s\n' '---'
} >>"$handoff_path"

if [[ -n "${session_id:-}" ]]; then
  marker_path="/tmp/claude-handoff-marker-${session_id}.json"
  write_marker "$marker_path" "$session_id" "$project_dir" "$handoff_path" "true" "precompact"
fi

