#!/usr/bin/env bash
# claudes-ai-buddies — fitness scorer for /forge
# Runs a fitness command in a directory and outputs JSON results.
# Usage: forge-fitness.sh --dir DIR --cmd "test command" [--label NAME] [--timeout SECS]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../hooks/lib.sh
source "${PLUGIN_ROOT}/hooks/lib.sh"

# ── Defaults ─────────────────────────────────────────────────────────────────
DIR=""
CMD=""
LABEL="unknown"
TIMEOUT="120"

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)     DIR="$2";     shift 2 ;;
    --cmd)     CMD="$2";     shift 2 ;;
    --label)   LABEL="$2";   shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

[[ -z "$DIR" ]] && { echo "ERROR: --dir is required" >&2; exit 1; }
[[ -z "$CMD" ]] && { echo "ERROR: --cmd is required" >&2; exit 1; }
[[ -d "$DIR" ]] || { echo "ERROR: --dir '$DIR' does not exist" >&2; exit 1; }

ai_buddies_debug "forge-fitness: label=$LABEL, cmd=$CMD, dir=$DIR, timeout=$TIMEOUT"

# ── Stage new files so git diff sees them ────────────────────────────────────
cd "$DIR"
git add -A 2>/dev/null || true

# ── Run fitness with timeout ─────────────────────────────────────────────────
START_SEC=$(date +%s)
EXIT_CODE=0
TIMED_OUT=false
OUTPUT=$(ai_buddies_run_with_timeout "$TIMEOUT" bash -lc "$CMD" 2>&1) || EXIT_CODE=$?
DURATION=$(( $(date +%s) - START_SEC ))

if [[ $EXIT_CODE -eq 124 ]]; then
  TIMED_OUT=true
  OUTPUT="TIMEOUT: fitness command did not complete within ${TIMEOUT}s"
  ai_buddies_debug "forge-fitness: $LABEL timed out after ${TIMEOUT}s"
fi

# ── Gather stats (includes new/untracked files via git add -A above) ────────
FILES_CHANGED=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
DIFF_LINES=$(git diff --cached 2>/dev/null | wc -l | tr -d ' ')

# ── Write result ─────────────────────────────────────────────────────────────
PASS=false
[[ $EXIT_CODE -eq 0 ]] && PASS=true

# ── Run quality scoring if forge-score.sh is available (F5) ──────────────────
LINT_WARNINGS=0
STYLE_SCORE=100
SCORE_JSON=""
FORGE_SCORE_SCRIPT="${SCRIPT_DIR}/forge-score.sh"
if [[ -x "$FORGE_SCORE_SCRIPT" ]]; then
  DIFF_FILE="${DIR}/.forge-fitness-diff-${LABEL}.tmp"
  git diff --cached > "$DIFF_FILE" 2>/dev/null || true
  SCORE_JSON=$(bash "$FORGE_SCORE_SCRIPT" --dir "$DIR" --diff "$DIFF_FILE" --label "$LABEL" 2>/dev/null) || SCORE_JSON=""
  rm -f "$DIFF_FILE"

  if [[ -n "$SCORE_JSON" ]] && command -v jq &>/dev/null; then
    LINT_WARNINGS=$(echo "$SCORE_JSON" | jq -r '.lint_warnings // 0' 2>/dev/null || echo 0)
    STYLE_SCORE=$(echo "$SCORE_JSON" | jq -r '.style_score // 100' 2>/dev/null || echo 100)
  fi
  ai_buddies_debug "forge-fitness: quality score lint=$LINT_WARNINGS style=$STYLE_SCORE"
fi

# ── Compute composite score ──────────────────────────────────────────────────
COMPOSITE=$(ai_buddies_compute_forge_score "$PASS" "$DIFF_LINES" "$FILES_CHANGED" "$DURATION" "$LINT_WARNINGS" "$STYLE_SCORE")

SESSION_DIR="$(ai_buddies_session_dir)"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
RESULT_FILE="${SESSION_DIR}/forge-fitness-${LABEL}-${TIMESTAMP}.json"

if command -v jq &>/dev/null; then
  jq -n \
    --arg label "$LABEL" \
    --argjson pass "$PASS" \
    --argjson timed_out "$TIMED_OUT" \
    --argjson exit_code "$EXIT_CODE" \
    --argjson duration "$DURATION" \
    --argjson files "$FILES_CHANGED" \
    --argjson diff_lines "$DIFF_LINES" \
    --argjson lint_warnings "$LINT_WARNINGS" \
    --argjson style_score "$STYLE_SCORE" \
    --argjson composite_score "$COMPOSITE" \
    --arg output "$OUTPUT" \
    '{label:$label, pass:$pass, timed_out:$timed_out, exit_code:$exit_code, duration_sec:$duration, files_changed:$files, diff_lines:$diff_lines, lint_warnings:$lint_warnings, style_score:$style_score, composite_score:$composite_score, output:$output}' \
    > "$RESULT_FILE"
else
  SAFE_LABEL=$(printf '%s' "$LABEL" | tr -cd 'a-zA-Z0-9_-')
  SAFE_OUTPUT=$(ai_buddies_escape_json "$OUTPUT")
  cat > "$RESULT_FILE" <<EOF
{"label":"$SAFE_LABEL","pass":$PASS,"timed_out":$TIMED_OUT,"exit_code":$EXIT_CODE,"duration_sec":$DURATION,"files_changed":$FILES_CHANGED,"diff_lines":$DIFF_LINES,"lint_warnings":$LINT_WARNINGS,"style_score":$STYLE_SCORE,"composite_score":$COMPOSITE,"output":$SAFE_OUTPUT}
EOF
fi

# ── Output file path for Claude to read ──────────────────────────────────────
echo "$RESULT_FILE"
ai_buddies_debug "forge-fitness: $LABEL done (pass=$PASS, timed_out=$TIMED_OUT, ${DURATION}s, ${FILES_CHANGED} files, ${DIFF_LINES} diff lines)"
