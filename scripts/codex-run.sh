#!/usr/bin/env bash
# claudes-ai-buddies — core wrapper for codex exec
# Usage: codex-run.sh --prompt "..." [--cwd DIR] [--mode exec|review]
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
MODEL="$(ai_buddies_codex_model)"
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

# ── Find codex ───────────────────────────────────────────────────────────────
CODEX_BIN="$(ai_buddies_find_codex 2>/dev/null)" || {
  echo "ERROR: codex CLI not found. Install: npm install -g @openai/codex" >&2
  exit 1
}

ai_buddies_debug "codex-run: mode=$MODE, model=$MODEL, timeout=$TIMEOUT, cwd=$CWD"

# ── Prepare output ───────────────────────────────────────────────────────────
SESSION_DIR="$(ai_buddies_session_dir)"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
OUTPUT_FILE="${SESSION_DIR}/codex-output-${TIMESTAMP}.md"
ERROR_FILE="${SESSION_DIR}/codex-error-${TIMESTAMP}.log"

# ── Try companion (app-server protocol) first ────────────────────────────────
COMPANION="${PLUGIN_ROOT}/scripts/codex-companion.mjs"
USE_APP_SERVER="$(ai_buddies_config "use_app_server" "true")"

if [[ -f "$COMPANION" ]] && [[ "$USE_APP_SERVER" == "true" ]] && command -v node &>/dev/null; then
  ai_buddies_debug "codex-run: trying companion (app-server protocol)"

  CONVERSATIONAL="$(ai_buddies_is_conversational "codex")"

  COMPANION_ARGS=()
  if [[ "$MODE" == "review" ]]; then
    # Always preserve the review target scope (uncommitted, branch:X, commit:X)
    # If user provided extra instructions, append them as custom instructions
    if [[ -n "$PROMPT" && "$PROMPT" != "Review this code" ]]; then
      COMPANION_ARGS+=(review --review-target "${REVIEW_TARGET}" --prompt "$PROMPT")
    else
      COMPANION_ARGS+=(review --review-target "$REVIEW_TARGET")
    fi
  elif [[ "$CONVERSATIONAL" == "true" ]]; then
    # Conversational mode: try to resume last thread
    COMPANION_ARGS+=(resume --prompt "$PROMPT" --ephemeral false)
  else
    COMPANION_ARGS+=(task --prompt "$PROMPT")
  fi

  COMPANION_ARGS+=(
    --cwd "$CWD"
    --output "$OUTPUT_FILE"
    --timeout "$TIMEOUT"
    --codex-bin "$CODEX_BIN"
  )
  [[ -n "$MODEL" ]] && COMPANION_ARGS+=(--model "$MODEL")

  # Map sandbox mode for companion
  case "$SANDBOX" in
    full-auto)  COMPANION_ARGS+=(--sandbox "workspace-write") ;;
    suggest)    COMPANION_ARGS+=(--sandbox "read-only") ;;
    *)          COMPANION_ARGS+=(--sandbox "$SANDBOX") ;;
  esac

  COMPANION_EXIT=0
  node "$COMPANION" "${COMPANION_ARGS[@]}" >/dev/null 2>"$ERROR_FILE" || COMPANION_EXIT=$?

  if [[ $COMPANION_EXIT -eq 0 ]]; then
    # Companion succeeded — output file path
    if [[ -f "$OUTPUT_FILE" ]]; then
      echo "$OUTPUT_FILE"
      ai_buddies_debug "codex-run: companion succeeded, output at ${OUTPUT_FILE}"
      exit 0
    fi
  elif [[ $COMPANION_EXIT -eq 1 && "$CONVERSATIONAL" == "true" ]]; then
    # Resume failed (no prior thread) — retry as fresh task
    ai_buddies_debug "codex-run: resume failed, retrying as fresh task"
    COMPANION_ARGS=(task --prompt "$PROMPT" --ephemeral false
      --cwd "$CWD" --output "$OUTPUT_FILE" --timeout "$TIMEOUT" --codex-bin "$CODEX_BIN")
    [[ -n "$MODEL" ]] && COMPANION_ARGS+=(--model "$MODEL")
    case "$SANDBOX" in
      full-auto)  COMPANION_ARGS+=(--sandbox "workspace-write") ;;
      suggest)    COMPANION_ARGS+=(--sandbox "read-only") ;;
      *)          COMPANION_ARGS+=(--sandbox "$SANDBOX") ;;
    esac
    node "$COMPANION" "${COMPANION_ARGS[@]}" >/dev/null 2>"$ERROR_FILE" || COMPANION_EXIT=$?
    if [[ $COMPANION_EXIT -eq 0 && -f "$OUTPUT_FILE" ]]; then
      echo "$OUTPUT_FILE"
      ai_buddies_debug "codex-run: companion fresh task succeeded"
      exit 0
    fi
  elif [[ $COMPANION_EXIT -eq 2 ]]; then
    ai_buddies_debug "codex-run: companion reports app-server unavailable, falling back to exec"
  else
    ai_buddies_debug "codex-run: companion failed (exit $COMPANION_EXIT), falling back to exec"
  fi
fi

# ── Fallback: codex exec (legacy) ───────────────────────────────────────────
ai_buddies_debug "codex-run: falling back to codex exec"

# Build the prompt
FINAL_PROMPT="$PROMPT"
if [[ "$MODE" == "review" ]]; then
  FINAL_PROMPT="$(ai_buddies_build_review_prompt "$PROMPT" "$CWD" "$REVIEW_TARGET")"
fi

CODEX_ARGS=(
  exec
  --ephemeral
  "--${SANDBOX}"
)
[[ -n "$MODEL" ]] && CODEX_ARGS+=(--model "$MODEL")
CODEX_ARGS+=(
  -o "$OUTPUT_FILE"
  "$FINAL_PROMPT"
)

EXIT_CODE=0
cd "$CWD"
# codex exec 0.120.0 reads stdin additively even when a prompt arg is given.
# Redirect from /dev/null so non-tty contexts (tribunal, forge background) don't
# error with "stdin is not a terminal".
ai_buddies_run_with_timeout "$TIMEOUT" "$CODEX_BIN" "${CODEX_ARGS[@]}" < /dev/null 2>"$ERROR_FILE" || EXIT_CODE=$?

# ── Handle result ────────────────────────────────────────────────────────────
if [[ $EXIT_CODE -eq 124 ]]; then
  echo "TIMEOUT: Codex did not respond within ${TIMEOUT}s" > "$OUTPUT_FILE"
  ai_buddies_debug "codex-run: timed out after ${TIMEOUT}s"
elif [[ $EXIT_CODE -ne 0 ]]; then
  {
    echo "ERROR: Codex exited with code ${EXIT_CODE}"
    echo ""
    echo "--- stderr ---"
    cat "$ERROR_FILE" 2>/dev/null || echo "(no stderr captured)"
  } > "$OUTPUT_FILE"
  ai_buddies_debug "codex-run: failed with exit code ${EXIT_CODE}"
fi

# ── Output the file path for Claude to read ──────────────────────────────────
if [[ -f "$OUTPUT_FILE" ]]; then
  echo "$OUTPUT_FILE"
  ai_buddies_debug "codex-run: output at ${OUTPUT_FILE}"
else
  echo "ERROR: No output file generated" >&2
  ai_buddies_debug "codex-run: no output file"
  exit 1
fi
