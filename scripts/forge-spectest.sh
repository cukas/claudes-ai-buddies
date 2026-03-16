#!/usr/bin/env bash
# claudes-ai-buddies — speculative test generation for /forge
# Sends "propose fitness tests" to each available engine, collects proposals.
# Usage: forge-spectest.sh --task "DESC" --cwd DIR [--timeout SECS]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../hooks/lib.sh
source "${PLUGIN_ROOT}/hooks/lib.sh"

# ── Defaults ─────────────────────────────────────────────────────────────────
TASK=""
CWD="$(pwd)"
TIMEOUT="$(ai_buddies_forge_timeout)"

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)    TASK="$2";    shift 2 ;;
    --cwd)     CWD="$2";    shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

[[ -z "$TASK" ]] && { echo "ERROR: --task is required" >&2; exit 1; }
[[ -d "$CWD" ]]  || { echo "ERROR: --cwd '$CWD' does not exist" >&2; exit 1; }

ai_buddies_debug "forge-spectest: task=$TASK, cwd=$CWD, timeout=$TIMEOUT"

# ── Safe test command allowlist ─────────────────────────────────────────────
_SAFE_TEST_PREFIXES=(
  "npm test"
  "npx jest"
  "npx vitest"
  "pytest"
  "python -m pytest"
  "go test"
  "cargo test"
  "make test"
  "make check"
  "bun test"
  "bash tests/"
  "./test"
)

_is_safe_test_cmd() {
  local cmd="$1"
  # Reject shell metacharacters that could chain or redirect commands
  local unsafe_pattern='[;&|`$()<>]'
  if [[ "$cmd" =~ $unsafe_pattern ]]; then
    return 1
  fi
  for prefix in "${_SAFE_TEST_PREFIXES[@]}"; do
    if [[ "$cmd" == "$prefix"* ]]; then
      return 0
    fi
  done
  return 1
}

# ── Cleanup trap — kill orphan processes + remove worktrees on interrupt ─────
_SPECTEST_PIDS=()
_SPECTEST_WTS=()
_SPECTEST_REPO_ROOT=""
_spectest_cleanup() {
  for pid in "${_SPECTEST_PIDS[@]}"; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  for wt in "${_SPECTEST_WTS[@]}"; do
    if [[ -n "$_SPECTEST_REPO_ROOT" ]]; then
      git -C "$_SPECTEST_REPO_ROOT" worktree remove "$wt" --force 2>/dev/null || true
    else
      rm -rf "$wt"
    fi
  done
  ai_buddies_debug "forge-spectest: cleanup trap fired"
}
trap _spectest_cleanup EXIT INT TERM

# ── Detect engines (v3: dynamic registry) ────────────────────────────────────
_available_csv=$(ai_buddies_available_buddies)
ENGINES=()
if [[ -n "$_available_csv" ]]; then
  IFS=',' read -ra ENGINES <<< "$_available_csv"
fi

if [[ ${#ENGINES[@]} -eq 0 ]]; then
  echo "ERROR: No engines available for spectest" >&2
  exit 1
fi

ai_buddies_debug "forge-spectest: engines=${ENGINES[*]}"

# ── Gather context ───────────────────────────────────────────────────────────
CONTEXT=$(ai_buddies_project_context "$CWD")

# ── Build spectest prompt ────────────────────────────────────────────────────
SPECTEST_PROMPT=$(ai_buddies_build_spectest_prompt "$TASK" "$CONTEXT")

# ── Create temp worktrees and dispatch engines ───────────────────────────────
SESSION_DIR="$(ai_buddies_session_dir)"
SPECTEST_DIR="${SESSION_DIR}/spectest-$(date +%s)-${RANDOM}"
mkdir -p "$SPECTEST_DIR"

PIDS=()
ACTIVE_ENGINES=()

REPO_ROOT=$(cd "$CWD" && git rev-parse --show-toplevel 2>/dev/null) || REPO_ROOT=""
HEAD_SHA=$(cd "$CWD" && git rev-parse HEAD 2>/dev/null) || HEAD_SHA=""
_SPECTEST_REPO_ROOT="$REPO_ROOT"

for engine in "${ENGINES[@]}"; do
  wt="${SPECTEST_DIR}/wt-${engine}"

  # Create worktree
  if [[ -n "$REPO_ROOT" && -n "$HEAD_SHA" ]]; then
    git -C "$REPO_ROOT" worktree add --detach "$wt" "$HEAD_SHA" 2>/dev/null || {
      ai_buddies_debug "forge-spectest: failed to create worktree for $engine"
      continue
    }
  else
    # No git repo — just copy the directory
    cp -r "$CWD" "$wt"
  fi

  ACTIVE_ENGINES+=("$engine")
  _SPECTEST_WTS+=("$wt")

  ai_buddies_dispatch_buddy "$engine" "$wt" "$SPECTEST_PROMPT" "$TIMEOUT" "$SPECTEST_DIR" "$PLUGIN_ROOT" \
    > "${SPECTEST_DIR}/${engine}-output.txt" 2>&1 &
  PIDS+=($!); _SPECTEST_PIDS+=($!)
done

# ── Wait for all engines ─────────────────────────────────────────────────────
for pid in "${PIDS[@]}"; do
  wait "$pid" 2>/dev/null || true
done
ai_buddies_debug "forge-spectest: all engines finished"

# ── Collect proposals ────────────────────────────────────────────────────────
PROPOSALS_JSON="{}"

for engine in "${ACTIVE_ENGINES[@]}"; do
  wt="${SPECTEST_DIR}/wt-${engine}"
  output_file="${SPECTEST_DIR}/${engine}-output.txt"

  # Gather the engine's output
  engine_output=""
  if [[ -f "$output_file" ]]; then
    result_path=$(tail -1 "$output_file")
    [[ -f "$result_path" ]] && engine_output=$(cat "$result_path" 2>/dev/null || echo "")
  fi

  # Check for TIMEOUT/ERROR markers
  status="ok"
  if [[ "$engine_output" == TIMEOUT:* ]]; then
    status="timeout"
  elif [[ "$engine_output" == ERROR:* ]]; then
    status="error"
  fi

  # Get diff of test files written
  diff=""
  if [[ -d "$wt" ]]; then
    diff=$(cd "$wt" && git add -A && git diff --cached 2>/dev/null || echo "")
  fi

  # Extract run command (last line starting with RUN_CMD:)
  run_cmd=""
  if [[ -n "$engine_output" ]]; then
    run_cmd=$(echo "$engine_output" | grep '^RUN_CMD:' | tail -1 | sed 's/^RUN_CMD: *//' || true)
  fi

  # Check if the run command is in the safe test allowlist
  needs_review=false
  if [[ -n "$run_cmd" ]] && ! _is_safe_test_cmd "$run_cmd"; then
    needs_review=true
    ai_buddies_debug "forge-spectest: $engine run_cmd needs review: $run_cmd"
  fi

  # Build per-engine proposal
  if command -v jq &>/dev/null; then
    proposal=$(jq -n \
      --arg status "$status" \
      --arg output "$engine_output" \
      --arg diff "$diff" \
      --arg run_cmd "$run_cmd" \
      --argjson needs_review "$([[ "$needs_review" == "true" ]] && echo true || echo false)" \
      '{status:$status, output:$output, diff:$diff, run_cmd:$run_cmd, needs_review:$needs_review}' 2>/dev/null) || proposal='{"status":"error","output":"","diff":"","run_cmd":"","needs_review":false}'
    PROPOSALS_JSON=$(echo "$PROPOSALS_JSON" | jq --arg e "$engine" --argjson p "$proposal" '.[$e] = $p' 2>/dev/null) || true
  fi

  ai_buddies_debug "forge-spectest: $engine status=$status, run_cmd=$run_cmd"
done

# ── Clean up worktrees ───────────────────────────────────────────────────────
for engine in "${ACTIVE_ENGINES[@]}"; do
  wt="${SPECTEST_DIR}/wt-${engine}"
  if [[ -n "$REPO_ROOT" ]]; then
    git -C "$REPO_ROOT" worktree remove "$wt" --force 2>/dev/null || true
  else
    rm -rf "$wt"
  fi
done

# ── Write output ─────────────────────────────────────────────────────────────
RESULT_FILE="${SPECTEST_DIR}/spectest-proposals.json"
if command -v jq &>/dev/null; then
  jq -n \
    --arg task "$TASK" \
    --argjson proposals "$PROPOSALS_JSON" \
    --arg engines "$(IFS=,; echo "${ACTIVE_ENGINES[*]}")" \
    '{task:$task, engines:($engines | split(",")), proposals:$proposals}' > "$RESULT_FILE" 2>/dev/null || \
    echo "{\"task\":$(ai_buddies_escape_json "$TASK"),\"engines\":[],\"proposals\":{}}" > "$RESULT_FILE"
else
  echo "$PROPOSALS_JSON" > "$RESULT_FILE"
fi

echo "$RESULT_FILE"
ai_buddies_debug "forge-spectest: proposals at $RESULT_FILE"
