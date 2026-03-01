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

latest_sections_filled() {
  local handoff_path="$1"

  if [[ ! -r "$handoff_path" ]]; then
    printf '%s\n' "0 0"
    return 0
  fi

  awk '
    { lines[NR] = $0 }
    /^---$/ { sep = NR }
    /^## Handoff:/ { start = (sep ? sep : NR) }
    END {
      if (!start) { print "0 0"; exit 0 }

      model = 0
      hand = 0
      in_model = 0
      in_hand = 0

      for (i = start; i <= NR; i++) {
        line = lines[i]

        if (line ~ /^### Model Summary$/) { in_model = 1; in_hand = 0; continue }
        if (line ~ /^### Handoff Context \(paste into next session\)$/) { in_hand = 1; in_model = 0; continue }
        if (line ~ /^### /) { in_model = 0; in_hand = 0; continue }

        if (in_model) {
          placeholder = (line ~ /^\(TODO:/ || line ~ /^\[[^][]*:[^][]*\]$/ || line ~ /^- \[[^][]*:[^][]*\]$/)
          if (line !~ /^[[:space:]]*$/ && !placeholder) model = 1
        }
        if (in_hand) {
          placeholder = (line ~ /^\(TODO:/ || line ~ /^\[[^][]*:[^][]*\]$/ || line ~ /^- \[[^][]*:[^][]*\]$/)
          if (line !~ /^[[:space:]]*$/ && !placeholder) hand = 1
        }
      }

      printf "%d %d\n", model, hand
    }
  ' "$handoff_path"
}

increment_attempts() {
  local marker_path="$1"
  if [[ ! -r "$marker_path" ]]; then
    printf '%s' "0"
    return 0
  fi

  if has_cmd jq; then
    local tmp_marker
    tmp_marker="$(mktemp "/tmp/.claude-handoff-marker-attempts.XXXXXX")"
    jq '.attempts = ((.attempts // 0) + 1)' "$marker_path" >"$tmp_marker"
    mv "$tmp_marker" "$marker_path"
    jq -r '.attempts // 0' "$marker_path" 2>/dev/null || echo "0"
    return 0
  fi

  if has_cmd python3; then
    local tmp_marker
    tmp_marker="$(mktemp "/tmp/.claude-handoff-marker-attempts.XXXXXX")"
    python3 - "$marker_path" "$tmp_marker" <<'PY' 2>/dev/null || echo "0"
import json
import sys

path = sys.argv[1]
output_path = sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
attempts = int(data.get("attempts", 0)) + 1
data["attempts"] = attempts
with open(output_path, "w", encoding="utf-8") as f:
    json.dump(data, f)
print(attempts)
PY
    mv "$tmp_marker" "$marker_path"
    return 0
  fi

  printf '%s' "0"
}

get_marker_field_raw() {
  local marker_path="$1"
  local jq_filter="$2"
  if [[ ! -r "$marker_path" ]]; then
    return 0
  fi

  if has_cmd jq; then
    jq -r "$jq_filter // empty" "$marker_path" 2>/dev/null || true
    return 0
  fi

  if has_cmd python3; then
    local field
    field="${jq_filter#.}"
    python3 - "$marker_path" "$field" <<'PY' 2>/dev/null || true
import json
import sys

path, field = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
v = data.get(field)
if v is None:
    sys.exit(0)
if isinstance(v, bool):
    sys.stdout.write("true" if v else "false")
elif isinstance(v, (int, float)):
    sys.stdout.write(str(v))
elif isinstance(v, str):
    sys.stdout.write(v)
else:
    sys.stdout.write(str(v))
PY
  fi
}

delete_marker() {
  local marker_path="$1"
  if [[ -e "$marker_path" ]]; then
    rm -f "$marker_path"
  fi
}

stamp_fallback_in_latest_entry() {
  local handoff_path="$1"

  if [[ ! -r "$handoff_path" ]]; then
    return 0
  fi

  local tmp_path
  tmp_path="$(mktemp)"

  awk '
    {
      lines[NR] = $0
    }
    /^---$/ { sep = NR }
    /^## Handoff:/ { start = (sep ? sep : NR) }
    END {
      if (!start) {
        for (i = 1; i <= NR; i++) print lines[i]
        exit 0
      }

      saw_model_heading = 0
      saw_hand_heading = 0
      model_has_content = 0
      hand_has_content = 0
      in_model = 0
      in_hand = 0

      for (i = 1; i < start; i++) print lines[i]

      for (i = start; i <= NR; i++) {
        line = lines[i]

        if (line ~ /^### Model Summary$/) {
          saw_model_heading = 1
          in_model = 1
          in_hand = 0
          model_has_content = 0
          print line
          continue
        }

        if (line ~ /^### Handoff Context \(paste into next session\)$/) {
          saw_hand_heading = 1
          if (in_model && model_has_content == 0) {
            print "AUTO: failed to generate after 3 attempts; run /handoff:create or summarize manually."
          }
          in_hand = 1
          in_model = 0
          hand_has_content = 0
          print line
          continue
        }

        if (line ~ /^### /) {
          if (in_model && model_has_content == 0) {
            print "AUTO: failed to generate after 3 attempts; run /handoff:create or summarize manually."
          }
          if (in_hand && hand_has_content == 0) {
            print "AUTO: failed to generate after 3 attempts."
            print "1. Read the latest entry above as the source of truth."
            print "2. Follow any listed Next Steps / Blockers."
            print "3. Use the Git Snapshot section to re-orient."
          }
          in_model = 0
          in_hand = 0
          print line
          continue
        }

        if (in_model) {
          if (line ~ /^\(TODO:/ || line ~ /^\[[^][]*:[^][]*\]$/ || line ~ /^- \[[^][]*:[^][]*\]$/) next
          if (line !~ /^[[:space:]]*$/) model_has_content = 1
          print line
          continue
        }

        if (in_hand) {
          if (line ~ /^\(TODO:/ || line ~ /^\[[^][]*:[^][]*\]$/ || line ~ /^- \[[^][]*:[^][]*\]$/) next
          if (line !~ /^[[:space:]]*$/) hand_has_content = 1
          print line
          continue
        }

        print line
      }

      if (in_model && model_has_content == 0) {
        print "AUTO: failed to generate after 3 attempts; run /handoff:create or summarize manually."
      }

      if (in_hand && hand_has_content == 0) {
        print "AUTO: failed to generate after 3 attempts."
        print "1. Read the latest entry above as the source of truth."
        print "2. Follow any listed Next Steps / Blockers."
        print "3. Use the Git Snapshot section to re-orient."
      }

      if (saw_model_heading == 0) {
        print ""
        print "### Model Summary"
        print "AUTO: failed to generate after 3 attempts; run /handoff:create or summarize manually."
      }
      if (saw_hand_heading == 0) {
        print ""
        print "### Handoff Context (paste into next session)"
        print "AUTO: failed to generate after 3 attempts."
        print "1. Read the latest entry above as the source of truth."
        print "2. Follow any listed Next Steps / Blockers."
        print "3. Use the Git Snapshot section to re-orient."
      }
    }
  ' "$handoff_path" >"$tmp_path"

  mv "$tmp_path" "$handoff_path"
}

session_id="$(json_get '.session_id')"
if [[ -z "${session_id:-}" ]]; then
  exit 0
fi

marker_path="/tmp/claude-handoff-marker-${session_id}.json"
if [[ ! -r "$marker_path" ]]; then
  exit 0
fi

needs_model_sections="$(get_marker_field_raw "$marker_path" '.needs_model_sections')"
if [[ "${needs_model_sections:-}" != "true" ]]; then
  delete_marker "$marker_path"
  exit 0
fi

handoff_path="$(get_marker_field_raw "$marker_path" '.handoff_path')"
if [[ -z "${handoff_path:-}" ]]; then
  project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  handoff_path="${project_dir}/docs/handoff/HANDOFF.md"
fi

read -r model_ok hand_ok < <(latest_sections_filled "$handoff_path")

if [[ "${model_ok:-0}" == "1" && "${hand_ok:-0}" == "1" ]]; then
  delete_marker "$marker_path"
  exit 0
fi

attempts="$(get_marker_field_raw "$marker_path" '.attempts')"
attempts="${attempts:-0}"

if [[ "$attempts" =~ ^[0-9]+$ ]] && [[ "$attempts" -lt 3 ]]; then
  new_attempts="$(increment_attempts "$marker_path")"
  cat <<EOF
{"decision":"block","reason":"Edit docs/handoff/HANDOFF.md in the most recent entry: replace the (TODO) placeholders under '### Model Summary' and '### Handoff Context (paste into next session)' with real content. Do not append a new entry; edit the latest entry in-place. (attempt ${new_attempts}/3)"}
EOF
  exit 0
fi

stamp_fallback_in_latest_entry "$handoff_path"
delete_marker "$marker_path"
exit 0
