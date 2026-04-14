#!/usr/bin/env bash
# claudes-ai-buddies — generic wrapper for non-builtin (user-registered) buddies
# Reads buddy JSON, constructs CLI call, captures output.
# Usage: buddy-run.sh --id BUDDY_ID --prompt "..." [--cwd DIR] [--mode exec|review]
#        [--timeout SECS]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../hooks/lib.sh
source "${PLUGIN_ROOT}/hooks/lib.sh"

# ── Defaults ─────────────────────────────────────────────────────────────────
BUDDY_ID=""
PROMPT=""
CWD="$(pwd)"
MODE="exec"
REVIEW_TARGET="uncommitted"
TIMEOUT=""

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --id)            BUDDY_ID="$2";      shift 2 ;;
    --prompt)        PROMPT="$2";        shift 2 ;;
    --cwd)           CWD="$2";           shift 2 ;;
    --mode)          MODE="$2";          shift 2 ;;
    --review-target) REVIEW_TARGET="$2"; shift 2 ;;
    --timeout)       TIMEOUT="$2";       shift 2 ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

[[ -z "$BUDDY_ID" ]] && { echo "ERROR: --id is required" >&2; exit 1; }
[[ -z "$PROMPT" ]]   && { echo "ERROR: --prompt is required" >&2; exit 1; }

# ── Load buddy config ───────────────────────────────────────────────────────
BUDDY_BIN=$(ai_buddies_find_buddy "$BUDDY_ID" 2>/dev/null) || {
  hint=$(ai_buddies_buddy_config "$BUDDY_ID" "install_hint" "")
  echo "ERROR: ${BUDDY_ID} CLI not found.${hint:+ Install: $hint}" >&2
  exit 1
}

BUDDY_DISPLAY=$(ai_buddies_buddy_config "$BUDDY_ID" "display_name" "$BUDDY_ID")
if [[ -z "$TIMEOUT" ]]; then
  TIMEOUT=$(ai_buddies_buddy_config "$BUDDY_ID" "timeout" "$(ai_buddies_timeout)")
fi

ai_buddies_debug "buddy-run: id=$BUDDY_ID, mode=$MODE, timeout=$TIMEOUT, cwd=$CWD"

# ── Prepare output ───────────────────────────────────────────────────────────
SESSION_DIR="$(ai_buddies_session_dir)"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
OUTPUT_FILE="${SESSION_DIR}/${BUDDY_ID}-output-${TIMESTAMP}.md"
ERROR_FILE="${SESSION_DIR}/${BUDDY_ID}-error-${TIMESTAMP}.log"

# ── Build the prompt ─────────────────────────────────────────────────────────
FINAL_PROMPT="$PROMPT"
if [[ "$MODE" == "review" ]]; then
  FINAL_PROMPT="$(ai_buddies_build_review_prompt "$PROMPT" "$CWD" "$REVIEW_TARGET")"
fi

# ── Write prompt to temp file (shell-safe, no interpolation) ─────────────────
# No .txt suffix: macOS BSD mktemp doesn't randomize Xs when a suffix follows,
# creating a literal "XXXXXX.txt" filename that collides on the second tribunal run.
PROMPT_FILE=$(mktemp "${SESSION_DIR}/${BUDDY_ID}-prompt-XXXXXX")
printf '%s' "$FINAL_PROMPT" > "$PROMPT_FILE"

# ── Construct and run CLI call ───────────────────────────────────────────────
# For non-builtin buddies, we pass the prompt via stdin or temp file
# The buddy binary gets: BINARY PROMPT_FILE
EXIT_CODE=0
cd "$CWD"
ai_buddies_run_with_timeout "$TIMEOUT" "$BUDDY_BIN" \
  < "$PROMPT_FILE" \
  > "$OUTPUT_FILE" 2>"$ERROR_FILE" || EXIT_CODE=$?

# ── Handle result ────────────────────────────────────────────────────────────
if [[ $EXIT_CODE -eq 124 ]]; then
  echo "TIMEOUT: ${BUDDY_DISPLAY} did not respond within ${TIMEOUT}s" > "$OUTPUT_FILE"
  ai_buddies_debug "buddy-run: $BUDDY_ID timed out after ${TIMEOUT}s"
elif [[ $EXIT_CODE -ne 0 ]]; then
  {
    echo "ERROR: ${BUDDY_DISPLAY} exited with code ${EXIT_CODE}"
    echo ""
    echo "--- stderr ---"
    cat "$ERROR_FILE" 2>/dev/null || echo "(no stderr captured)"
  } > "$OUTPUT_FILE"
  ai_buddies_debug "buddy-run: $BUDDY_ID failed with exit code ${EXIT_CODE}"
fi

# Cleanup prompt file
rm -f "$PROMPT_FILE"

# ── Output the file path for orchestrator to read ────────────────────────────
if [[ -f "$OUTPUT_FILE" ]]; then
  echo "$OUTPUT_FILE"
  ai_buddies_debug "buddy-run: output at ${OUTPUT_FILE}"
else
  echo "ERROR: No output file generated" >&2
  ai_buddies_debug "buddy-run: no output file"
  exit 1
fi
