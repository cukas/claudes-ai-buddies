#!/usr/bin/env bash
# claudes-ai-buddies — fitness scorer for /forge
# Runs a fitness command in a directory and outputs JSON results.
# Usage: forge-fitness.sh --dir DIR --cmd "test command" [--label NAME]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../hooks/lib.sh
source "${PLUGIN_ROOT}/hooks/lib.sh"

# ── Defaults ─────────────────────────────────────────────────────────────────
DIR=""
CMD=""
LABEL="unknown"

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)   DIR="$2";   shift 2 ;;
    --cmd)   CMD="$2";   shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

[[ -z "$DIR" ]] && { echo "ERROR: --dir is required" >&2; exit 1; }
[[ -z "$CMD" ]] && { echo "ERROR: --cmd is required" >&2; exit 1; }

ai_buddies_debug "forge-fitness: label=$LABEL, cmd=$CMD, dir=$DIR"

# ── Run fitness ──────────────────────────────────────────────────────────────
START_SEC=$(date +%s)
EXIT_CODE=0
cd "$DIR"
OUTPUT=$(eval "$CMD" 2>&1) || EXIT_CODE=$?
DURATION=$(( $(date +%s) - START_SEC ))

# ── Gather stats ─────────────────────────────────────────────────────────────
FILES_CHANGED=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
DIFF_LINES=$(git diff 2>/dev/null | wc -l | tr -d ' ')

# ── Write result ─────────────────────────────────────────────────────────────
PASS=$( [[ $EXIT_CODE -eq 0 ]] && echo true || echo false )

SESSION_DIR="$(ai_buddies_session_dir)"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
RESULT_FILE="${SESSION_DIR}/forge-fitness-${LABEL}-${TIMESTAMP}.json"

if command -v jq &>/dev/null; then
  jq -n \
    --arg label "$LABEL" \
    --argjson pass "$PASS" \
    --argjson exit_code "$EXIT_CODE" \
    --argjson duration "$DURATION" \
    --argjson files "$FILES_CHANGED" \
    --argjson diff_lines "$DIFF_LINES" \
    --arg output "$OUTPUT" \
    '{label:$label, pass:$pass, exit_code:$exit_code, duration_sec:$duration, files_changed:$files, diff_lines:$diff_lines, output:$output}' \
    > "$RESULT_FILE"
else
  cat > "$RESULT_FILE" <<EOF
{"label":"$LABEL","pass":$PASS,"exit_code":$EXIT_CODE,"duration_sec":$DURATION,"files_changed":$FILES_CHANGED,"diff_lines":$DIFF_LINES}
EOF
fi

# ── Output file path for Claude to read ──────────────────────────────────────
echo "$RESULT_FILE"
ai_buddies_debug "forge-fitness: $LABEL done (pass=$PASS, ${DURATION}s, ${FILES_CHANGED} files, ${DIFF_LINES} diff lines)"
