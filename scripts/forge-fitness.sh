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

# ── Timeout wrapper (same as codex-run.sh / gemini-run.sh) ──────────────────
run_with_timeout() {
  local timeout_secs="$1"
  shift

  if command -v gtimeout &>/dev/null; then
    gtimeout "${timeout_secs}s" "$@"
  elif command -v timeout &>/dev/null; then
    timeout "${timeout_secs}s" "$@"
  else
    # Perl-based fallback for macOS without coreutils
    perl -e '
      alarm shift @ARGV;
      $SIG{ALRM} = sub { kill 9, $pid; exit 124 };
      $pid = fork;
      if ($pid == 0) { exec @ARGV; die "exec failed: $!" }
      waitpid $pid, 0;
      exit ($? >> 8);
    ' "$timeout_secs" "$@"
  fi
}

# ── Stage new files so git diff sees them ────────────────────────────────────
cd "$DIR"
git add -A 2>/dev/null || true

# ── Run fitness with timeout ─────────────────────────────────────────────────
START_SEC=$(date +%s)
EXIT_CODE=0
TIMED_OUT=false
OUTPUT=$(run_with_timeout "$TIMEOUT" bash -lc "$CMD" 2>&1) || EXIT_CODE=$?
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
    --arg output "$OUTPUT" \
    '{label:$label, pass:$pass, timed_out:$timed_out, exit_code:$exit_code, duration_sec:$duration, files_changed:$files, diff_lines:$diff_lines, output:$output}' \
    > "$RESULT_FILE"
else
  # Fallback: use jq-safe values only (label is sanitized via --label flag)
  SAFE_LABEL=$(printf '%s' "$LABEL" | tr -cd 'a-zA-Z0-9_-')
  cat > "$RESULT_FILE" <<EOF
{"label":"$SAFE_LABEL","pass":$PASS,"timed_out":$TIMED_OUT,"exit_code":$EXIT_CODE,"duration_sec":$DURATION,"files_changed":$FILES_CHANGED,"diff_lines":$DIFF_LINES}
EOF
fi

# ── Output file path for Claude to read ──────────────────────────────────────
echo "$RESULT_FILE"
ai_buddies_debug "forge-fitness: $LABEL done (pass=$PASS, timed_out=$TIMED_OUT, ${DURATION}s, ${FILES_CHANGED} files, ${DIFF_LINES} diff lines)"
