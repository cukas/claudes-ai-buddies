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

# ── Build the prompt ─────────────────────────────────────────────────────────
build_review_prompt() {
  local diff_content=""
  local target="$1"

  case "$target" in
    uncommitted)
      diff_content=$(cd "$CWD" && git diff HEAD 2>/dev/null || git diff 2>/dev/null || echo "(no diff available)")
      ;;
    branch:*)
      local branch="${target#branch:}"
      diff_content=$(cd "$CWD" && git diff "${branch}...HEAD" 2>/dev/null || echo "(no diff for branch ${branch})")
      ;;
    commit:*)
      local sha="${target#commit:}"
      diff_content=$(cd "$CWD" && git show "$sha" 2>/dev/null || echo "(no diff for commit ${sha})")
      ;;
    *)
      diff_content=$(cd "$CWD" && git diff HEAD 2>/dev/null || echo "(no diff available)")
      ;;
  esac

  cat <<EOF
You are reviewing code changes. Provide a thorough code review covering:
- Bugs and logic errors
- Security vulnerabilities
- Performance issues
- Code quality and readability
- Suggestions for improvement

Here are the changes to review:

\`\`\`diff
${diff_content}
\`\`\`

${PROMPT}
EOF
}

FINAL_PROMPT="$PROMPT"
if [[ "$MODE" == "review" ]]; then
  FINAL_PROMPT="$(build_review_prompt "$REVIEW_TARGET")"
fi

# ── Run codex ────────────────────────────────────────────────────────────────
ai_buddies_debug "codex-run: executing codex exec"

# Build command array
CODEX_ARGS=(
  exec
  --ephemeral
  "--${SANDBOX}"
  --model "$MODEL"
  -o "$OUTPUT_FILE"
  "$FINAL_PROMPT"
)

# macOS timeout: use gtimeout (coreutils) or perl fallback
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

EXIT_CODE=0
cd "$CWD"
run_with_timeout "$TIMEOUT" "$CODEX_BIN" "${CODEX_ARGS[@]}" 2>"$ERROR_FILE" || EXIT_CODE=$?

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
