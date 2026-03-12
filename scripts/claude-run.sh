#!/usr/bin/env bash
# claudes-ai-buddies — core wrapper for claude CLI (Claude Code)
# Usage: claude-run.sh --prompt "..." [--cwd DIR] [--mode exec|review]
#        [--review-target uncommitted|branch:NAME|commit:SHA]
#        [--timeout SECS] [--model MODEL]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../hooks/lib.sh
source "${PLUGIN_ROOT}/hooks/lib.sh"

# ── Defaults ─────────────────────────────────────────────────────────────────
PROMPT=""
CWD="$(pwd)"
MODE="exec"
REVIEW_TARGET="uncommitted"
TIMEOUT="$(ai_buddies_timeout)"
MODEL="$(ai_buddies_claude_model)"

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt)     PROMPT="$2";        shift 2 ;;
    --cwd)        CWD="$2";           shift 2 ;;
    --mode)       MODE="$2";          shift 2 ;;
    --review-target) REVIEW_TARGET="$2"; shift 2 ;;
    --timeout)    TIMEOUT="$2";       shift 2 ;;
    --model)      MODEL="$2";         shift 2 ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$PROMPT" ]]; then
  echo "ERROR: --prompt is required" >&2
  exit 1
fi

# ── Find claude ──────────────────────────────────────────────────────────────
CLAUDE_BIN="$(ai_buddies_find_claude 2>/dev/null)" || {
  echo "ERROR: claude CLI not found. Install: npm install -g @anthropic-ai/claude-code" >&2
  exit 1
}

ai_buddies_debug "claude-run: mode=$MODE, model=$MODEL, timeout=$TIMEOUT, cwd=$CWD"

# ── Prepare output ───────────────────────────────────────────────────────────
SESSION_DIR="$(ai_buddies_session_dir)"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
OUTPUT_FILE="${SESSION_DIR}/claude-output-${TIMESTAMP}.md"
ERROR_FILE="${SESSION_DIR}/claude-error-${TIMESTAMP}.log"

# ── Build the prompt ─────────────────────────────────────────────────────────
FINAL_PROMPT="$PROMPT"
if [[ "$MODE" == "review" ]]; then
  FINAL_PROMPT="$(ai_buddies_build_review_prompt "$PROMPT" "$CWD" "$REVIEW_TARGET")"
fi

# ── Run claude ───────────────────────────────────────────────────────────────
ai_buddies_debug "claude-run: executing claude --print -p"

CLAUDE_ARGS=(
  --print
  -p "$FINAL_PROMPT"
  --allowedTools "Edit,Write,Read,Bash,Glob,Grep"
  --max-turns 50
)
[[ -n "$MODEL" ]] && CLAUDE_ARGS+=(--model "$MODEL")

EXIT_CODE=0
cd "$CWD"
# Unset CLAUDECODE so the subprocess doesn't think it's nested inside a parent session
unset CLAUDECODE 2>/dev/null || true
ai_buddies_run_with_timeout "$TIMEOUT" "$CLAUDE_BIN" \
  "${CLAUDE_ARGS[@]}" \
  > "$OUTPUT_FILE" 2>"$ERROR_FILE" || EXIT_CODE=$?

# ── Handle result ────────────────────────────────────────────────────────────
if [[ $EXIT_CODE -eq 124 ]]; then
  echo "TIMEOUT: Claude did not respond within ${TIMEOUT}s" > "$OUTPUT_FILE"
  ai_buddies_debug "claude-run: timed out after ${TIMEOUT}s"
elif [[ $EXIT_CODE -ne 0 ]]; then
  {
    echo "ERROR: Claude exited with code ${EXIT_CODE}"
    echo ""
    echo "--- stderr ---"
    cat "$ERROR_FILE" 2>/dev/null || echo "(no stderr captured)"
  } > "$OUTPUT_FILE"
  ai_buddies_debug "claude-run: failed with exit code ${EXIT_CODE}"
fi

# ── Output the file path for orchestrator to read ────────────────────────────
if [[ -f "$OUTPUT_FILE" ]]; then
  echo "$OUTPUT_FILE"
  ai_buddies_debug "claude-run: output at ${OUTPUT_FILE}"
else
  echo "ERROR: No output file generated" >&2
  ai_buddies_debug "claude-run: no output file"
  exit 1
fi
