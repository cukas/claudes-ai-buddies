#!/usr/bin/env bash
# claudes-ai-buddies — core wrapper for gemini CLI
# Usage: gemini-run.sh --prompt "..." [--cwd DIR] [--mode exec|review]
#        [--review-target uncommitted|branch:NAME|commit:SHA]
#        [--timeout SECS] [--model MODEL] [--sandbox MODE]

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
MODEL="$(ai_buddies_gemini_model)"
SANDBOX="$(ai_buddies_sandbox)"

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt)     PROMPT="$2";        shift 2 ;;
    --cwd)        CWD="$2";           shift 2 ;;
    --mode)       MODE="$2";          shift 2 ;;
    --review-target) REVIEW_TARGET="$2"; shift 2 ;;
    --timeout)    TIMEOUT="$2";       shift 2 ;;
    --model)      MODEL="$2";         shift 2 ;;
    --sandbox)    SANDBOX="$2";       shift 2 ;;
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

# ── Find gemini ──────────────────────────────────────────────────────────────
GEMINI_BIN="$(ai_buddies_find_gemini 2>/dev/null)" || {
  echo "ERROR: gemini CLI not found. Install: npm install -g @google/gemini-cli" >&2
  exit 1
}

ai_buddies_debug "gemini-run: mode=$MODE, model=$MODEL, timeout=$TIMEOUT, cwd=$CWD"

# ── Prepare output ───────────────────────────────────────────────────────────
SESSION_DIR="$(ai_buddies_session_dir)"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
OUTPUT_FILE="${SESSION_DIR}/gemini-output-${TIMESTAMP}.md"
ERROR_FILE="${SESSION_DIR}/gemini-error-${TIMESTAMP}.log"

# ── Try companion (structured JSON + session resume) first ───────────────────
COMPANION="${PLUGIN_ROOT}/scripts/gemini-companion.mjs"
USE_COMPANION="$(ai_buddies_config "use_companion" "true")"

if [[ -f "$COMPANION" ]] && [[ "$USE_COMPANION" == "true" ]] && command -v node &>/dev/null; then
  ai_buddies_debug "gemini-run: trying companion"
  CONVERSATIONAL="$(ai_buddies_is_conversational "gemini")"

  COMPANION_ARGS=()
  if [[ "$MODE" == "review" ]]; then
    FINAL_PROMPT="$(ai_buddies_build_review_prompt "$PROMPT" "$CWD" "$REVIEW_TARGET")"
    COMPANION_ARGS+=(review --prompt "$FINAL_PROMPT")
  elif [[ "$CONVERSATIONAL" == "true" ]]; then
    COMPANION_ARGS+=(resume --prompt "$PROMPT")
  else
    COMPANION_ARGS+=(task --prompt "$PROMPT")
  fi

  COMPANION_ARGS+=(--cwd "$CWD" --output "$OUTPUT_FILE" --timeout "$TIMEOUT" --gemini-bin "$GEMINI_BIN")
  [[ -n "$MODEL" ]] && COMPANION_ARGS+=(--model "$MODEL")

  COMPANION_EXIT=0
  node "$COMPANION" "${COMPANION_ARGS[@]}" >/dev/null 2>"$ERROR_FILE" || COMPANION_EXIT=$?

  if [[ $COMPANION_EXIT -eq 0 && -f "$OUTPUT_FILE" ]]; then
    echo "$OUTPUT_FILE"
    ai_buddies_debug "gemini-run: companion succeeded, output at ${OUTPUT_FILE}"
    exit 0
  elif [[ $COMPANION_EXIT -eq 1 && "$CONVERSATIONAL" == "true" ]]; then
    # Resume failed — retry as fresh task
    ai_buddies_debug "gemini-run: resume failed, retrying as fresh task"
    COMPANION_ARGS=(task --prompt "$PROMPT" --cwd "$CWD" --output "$OUTPUT_FILE" --timeout "$TIMEOUT" --gemini-bin "$GEMINI_BIN")
    [[ -n "$MODEL" ]] && COMPANION_ARGS+=(--model "$MODEL")
    node "$COMPANION" "${COMPANION_ARGS[@]}" >/dev/null 2>"$ERROR_FILE" || COMPANION_EXIT=$?
    if [[ $COMPANION_EXIT -eq 0 && -f "$OUTPUT_FILE" ]]; then
      echo "$OUTPUT_FILE"
      ai_buddies_debug "gemini-run: companion fresh task succeeded"
      exit 0
    fi
  fi
  ai_buddies_debug "gemini-run: companion failed (exit $COMPANION_EXIT), falling back to legacy"
fi

# ── Fallback: legacy gemini -p (raw text) ────────────────────────────────────
ai_buddies_debug "gemini-run: falling back to legacy gemini -p"

# Build the prompt
FINAL_PROMPT="$PROMPT"
if [[ "$MODE" == "review" ]]; then
  FINAL_PROMPT="$(ai_buddies_build_review_prompt "$PROMPT" "$CWD" "$REVIEW_TARGET")"
fi

# Map sandbox to gemini CLI flags
GEMINI_SANDBOX_ARGS=()
case "$SANDBOX" in
  full-auto) GEMINI_SANDBOX_ARGS=(--sandbox --approval-mode yolo) ;;
  suggest)   GEMINI_SANDBOX_ARGS=(--sandbox --approval-mode default) ;;
  *)         GEMINI_SANDBOX_ARGS=(--sandbox --approval-mode yolo) ;;
esac

GEMINI_ARGS=(-p "$FINAL_PROMPT")
[[ -n "$MODEL" ]] && GEMINI_ARGS+=(--model "$MODEL")

EXIT_CODE=0
cd "$CWD"
ai_buddies_run_with_timeout "$TIMEOUT" "$GEMINI_BIN" \
  "${GEMINI_ARGS[@]}" \
  "${GEMINI_SANDBOX_ARGS[@]}" \
  > "$OUTPUT_FILE" 2>"$ERROR_FILE" || EXIT_CODE=$?

# ── Handle result ────────────────────────────────────────────────────────────
if [[ $EXIT_CODE -eq 124 ]]; then
  echo "TIMEOUT: Gemini did not respond within ${TIMEOUT}s" > "$OUTPUT_FILE"
  ai_buddies_debug "gemini-run: timed out after ${TIMEOUT}s"
elif [[ $EXIT_CODE -ne 0 ]]; then
  {
    echo "ERROR: Gemini exited with code ${EXIT_CODE}"
    echo ""
    echo "--- stderr ---"
    cat "$ERROR_FILE" 2>/dev/null || echo "(no stderr captured)"
  } > "$OUTPUT_FILE"
  ai_buddies_debug "gemini-run: failed with exit code ${EXIT_CODE}"
fi

# ── Output the file path for Claude to read ──────────────────────────────────
if [[ -f "$OUTPUT_FILE" ]]; then
  echo "$OUTPUT_FILE"
  ai_buddies_debug "gemini-run: output at ${OUTPUT_FILE}"
else
  echo "ERROR: No output file generated" >&2
  ai_buddies_debug "gemini-run: no output file"
  exit 1
fi
