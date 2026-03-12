#!/usr/bin/env bash
# claudes-ai-buddies — forge orchestrator
# Creates peer worktrees, dispatches engines in parallel, runs fitness, writes manifest.
# Expects wt-claude/ to already exist (Claude implements via Edit tool).
# Usage: forge-run.sh --forge-dir DIR --task "DESC" --fitness "CMD" [--timeout SECS]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../hooks/lib.sh
source "${PLUGIN_ROOT}/hooks/lib.sh"

# ── Defaults ─────────────────────────────────────────────────────────────────
FORGE_DIR=""
TASK=""
FITNESS=""
TIMEOUT="$(ai_buddies_forge_timeout)"
FITNESS_TIMEOUT="120"

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --forge-dir)       FORGE_DIR="$2";       shift 2 ;;
    --task)            TASK="$2";            shift 2 ;;
    --fitness)         FITNESS="$2";         shift 2 ;;
    --timeout)         TIMEOUT="$2";         shift 2 ;;
    --fitness-timeout) FITNESS_TIMEOUT="$2"; shift 2 ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

[[ -z "$FORGE_DIR" ]] && { echo "ERROR: --forge-dir is required" >&2; exit 1; }
[[ -z "$TASK" ]]      && { echo "ERROR: --task is required" >&2; exit 1; }
[[ -z "$FITNESS" ]]   && { echo "ERROR: --fitness is required" >&2; exit 1; }

ai_buddies_debug "forge-run: forge_dir=$FORGE_DIR, task=$TASK, timeout=$TIMEOUT"

# ── Cleanup trap — kill orphan background processes on interrupt ──────────────
_FORGE_RUN_PIDS=()
_forge_run_cleanup() {
  for pid in "${_FORGE_RUN_PIDS[@]}"; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  ai_buddies_debug "forge-run: cleanup trap fired, killed ${#_FORGE_RUN_PIDS[@]} background PIDs"
}
trap _forge_run_cleanup EXIT INT TERM

# ── Detect engines ───────────────────────────────────────────────────────────
CODEX_BIN=$(ai_buddies_find_codex 2>/dev/null) || CODEX_BIN=""
GEMINI_BIN=$(ai_buddies_find_gemini 2>/dev/null) || GEMINI_BIN=""

ENGINES=(claude)
[[ -n "$CODEX_BIN" ]]  && ENGINES+=(codex)
[[ -n "$GEMINI_BIN" ]] && ENGINES+=(gemini)

ai_buddies_debug "forge-run: engines=${ENGINES[*]}"

# ── Validate claude worktree exists ──────────────────────────────────────────
if [[ ! -d "${FORGE_DIR}/wt-claude" ]]; then
  echo "ERROR: ${FORGE_DIR}/wt-claude/ must exist (Claude implements via Edit tool)" >&2
  exit 1
fi

# ── Gather project context (F4) ─────────────────────────────────────────────
CONTEXT=""
CONTEXT_FILE="${FORGE_DIR}/context.txt"
CONTEXT=$(ai_buddies_project_context "${FORGE_DIR}/wt-claude")
if [[ -n "$CONTEXT" ]]; then
  printf '%s' "$CONTEXT" > "$CONTEXT_FILE"
  ai_buddies_debug "forge-run: project context saved to ${CONTEXT_FILE}"
fi

# ── Build prompt ─────────────────────────────────────────────────────────────
FORGE_PROMPT=$(ai_buddies_build_forge_prompt "$TASK" "$FITNESS" "$CONTEXT")

# ── Create peer worktrees & dispatch ─────────────────────────────────────────
PIDS=()
PEER_ENGINES=()

# Find git dir from claude worktree
GIT_DIR=$(cd "${FORGE_DIR}/wt-claude" && git rev-parse --git-common-dir 2>/dev/null) || GIT_DIR=""
REPO_ROOT=""
if [[ -n "$GIT_DIR" ]]; then
  REPO_ROOT=$(cd "${FORGE_DIR}/wt-claude" && git rev-parse --show-toplevel 2>/dev/null) || true
fi

for engine in "${ENGINES[@]}"; do
  [[ "$engine" == "claude" ]] && continue  # claude already implemented
  wt="${FORGE_DIR}/wt-${engine}"

  # Create worktree from the same HEAD as claude
  if [[ -n "$REPO_ROOT" ]]; then
    head_sha=$(cd "${FORGE_DIR}/wt-claude" && git rev-parse HEAD)
    git -C "$REPO_ROOT" worktree add --detach "$wt" "$head_sha" 2>/dev/null || {
      ai_buddies_debug "forge-run: failed to create worktree for $engine"
      continue
    }
  else
    ai_buddies_debug "forge-run: cannot determine repo root, skipping $engine"
    continue
  fi

  PEER_ENGINES+=("$engine")
  ai_buddies_debug "forge-run: created worktree for $engine at $wt"

  # Dispatch engine
  case "$engine" in
    codex)
      bash "${PLUGIN_ROOT}/scripts/codex-run.sh" \
        --prompt "$FORGE_PROMPT" \
        --cwd "$wt" \
        --mode exec \
        --timeout "$TIMEOUT" \
        > "${FORGE_DIR}/${engine}-output.txt" 2>&1 &
      PIDS+=($!); _FORGE_RUN_PIDS+=($!)
      ;;
    gemini)
      bash "${PLUGIN_ROOT}/scripts/gemini-run.sh" \
        --prompt "$FORGE_PROMPT" \
        --cwd "$wt" \
        --mode exec \
        --timeout "$TIMEOUT" \
        > "${FORGE_DIR}/${engine}-output.txt" 2>&1 &
      PIDS+=($!); _FORGE_RUN_PIDS+=($!)
      ;;
  esac
done

# ── Wait for all peers ───────────────────────────────────────────────────────
ai_buddies_debug "forge-run: waiting for ${#PIDS[@]} peer engines"
for pid in "${PIDS[@]}"; do
  wait "$pid" 2>/dev/null || true
done
ai_buddies_debug "forge-run: all peers finished"

# ── Generate diffs for all engines ───────────────────────────────────────────
for engine in "${ENGINES[@]}"; do
  wt="${FORGE_DIR}/wt-${engine}"
  [[ -d "$wt" ]] || continue
  (cd "$wt" && git add -A && git diff --cached > "${FORGE_DIR}/${engine}-patch.diff") 2>/dev/null || true
done

# ── Run fitness on ALL worktrees ─────────────────────────────────────────────
FITNESS_PIDS=()
FITNESS_LABELS=()

for engine in "${ENGINES[@]}"; do
  wt="${FORGE_DIR}/wt-${engine}"
  [[ -d "$wt" ]] || continue
  FITNESS_LABELS+=("$engine")

  bash "${PLUGIN_ROOT}/scripts/forge-fitness.sh" \
    --dir "$wt" \
    --cmd "$FITNESS" \
    --label "$engine" \
    --timeout "$FITNESS_TIMEOUT" \
    > "${FORGE_DIR}/${engine}-fitness-path.txt" 2>&1 &
  FITNESS_PIDS+=($!); _FORGE_RUN_PIDS+=($!)
done

for pid in "${FITNESS_PIDS[@]}"; do
  wait "$pid" 2>/dev/null || true
done
ai_buddies_debug "forge-run: all fitness tests complete"

# ── Run quality scoring (F5) on all engines ──────────────────────────────────
for engine in "${ENGINES[@]}"; do
  wt="${FORGE_DIR}/wt-${engine}"
  diff_file="${FORGE_DIR}/${engine}-patch.diff"
  [[ -d "$wt" ]] || continue

  score_json=$(bash "${PLUGIN_ROOT}/scripts/forge-score.sh" \
    --dir "$wt" \
    --diff "$diff_file" \
    --label "$engine" 2>/dev/null) || score_json='{"lint_warnings":0,"style_score":100}'

  echo "$score_json" > "${FORGE_DIR}/${engine}-score.json"
done

# ── Collect results and determine winner ─────────────────────────────────────
RESULTS_JSON="{}"
PATCHES_JSON="{}"
WINNER="none"
BEST_SCORE=0

for engine in "${ENGINES[@]}"; do
  # Read fitness result
  fitness_path_file="${FORGE_DIR}/${engine}-fitness-path.txt"
  fitness_json="{}"
  if [[ -f "$fitness_path_file" ]]; then
    fitness_file=$(tail -1 "$fitness_path_file")
    [[ -f "$fitness_file" ]] && fitness_json=$(cat "$fitness_file")
  fi

  # Read quality score
  score_file="${FORGE_DIR}/${engine}-score.json"
  lint_warnings=0
  style_score=100
  if [[ -f "$score_file" ]] && command -v jq &>/dev/null; then
    lint_warnings=$(jq -r '.lint_warnings // 0' "$score_file" 2>/dev/null || echo 0)
    style_score=$(jq -r '.style_score // 100' "$score_file" 2>/dev/null || echo 100)
  fi

  # Extract fitness fields
  pass="false"
  diff_lines=0
  files_changed=0
  duration=0
  if command -v jq &>/dev/null && [[ "$fitness_json" != "{}" ]]; then
    pass=$(echo "$fitness_json" | jq -r '.pass // false' 2>/dev/null || echo false)
    diff_lines=$(echo "$fitness_json" | jq -r '.diff_lines // 0' 2>/dev/null || echo 0)
    files_changed=$(echo "$fitness_json" | jq -r '.files_changed // 0' 2>/dev/null || echo 0)
    duration=$(echo "$fitness_json" | jq -r '.duration_sec // 0' 2>/dev/null || echo 0)
  fi

  # Compute composite score
  composite=$(ai_buddies_compute_forge_score "$pass" "$diff_lines" "$files_changed" "$duration" "$lint_warnings" "$style_score")

  # Build per-engine result
  engine_result=$(jq -n \
    --argjson pass "$([[ "$pass" == "true" ]] && echo true || echo false)" \
    --argjson score "$composite" \
    --argjson diff_lines "$diff_lines" \
    --argjson files_changed "$files_changed" \
    --argjson duration "$duration" \
    --argjson lint_warnings "$lint_warnings" \
    --argjson style_score "$style_score" \
    '{pass:$pass, score:$score, diff_lines:$diff_lines, files_changed:$files_changed, duration_sec:$duration, lint_warnings:$lint_warnings, style_score:$style_score}' 2>/dev/null) || \
    engine_result="{\"pass\":${pass},\"score\":${composite}}"

  # Use temp variable to avoid losing previous results on jq failure
  if next_results=$(echo "$RESULTS_JSON" | jq --arg e "$engine" --argjson r "$engine_result" '.[$e] = $r' 2>/dev/null); then
    RESULTS_JSON="$next_results"
  fi

  # Track patches
  patch_file="${FORGE_DIR}/${engine}-patch.diff"
  if [[ -f "$patch_file" ]]; then
    if next_patches=$(echo "$PATCHES_JSON" | jq --arg e "$engine" --arg p "$patch_file" '.[$e] = $p' 2>/dev/null); then
      PATCHES_JSON="$next_patches"
    fi
  fi

  # Track winner
  if (( composite > BEST_SCORE )); then
    BEST_SCORE=$composite
    WINNER="$engine"
  fi

  ai_buddies_debug "forge-run: $engine pass=$pass score=$composite"
done

# ── Check for close call ─────────────────────────────────────────────────────
CLOSE_CALL=false
if command -v jq &>/dev/null; then
  scores=$(echo "$RESULTS_JSON" | jq '[.[].score]' 2>/dev/null)
  max_score=$(echo "$scores" | jq 'max // 0' 2>/dev/null || echo 0)
  second=$(echo "$scores" | jq 'sort | reverse | .[1] // 0' 2>/dev/null || echo 0)
  if (( max_score > 0 && (max_score - second) <= 5 )); then
    CLOSE_CALL=true
    ai_buddies_debug "forge-run: close call detected (spread <= 5pts)"
  fi
fi

# ── Write manifest ───────────────────────────────────────────────────────────
FORGE_ID=$(basename "$FORGE_DIR")
ENGINES_CSV=$(IFS=,; echo "${ENGINES[*]}")
ai_buddies_forge_manifest \
  "${FORGE_DIR}/manifest.json" \
  "$FORGE_ID" \
  "$FORGE_DIR" \
  "$TASK" \
  "$ENGINES_CSV" \
  "$RESULTS_JSON" \
  "$PATCHES_JSON" \
  "$WINNER"

# Add close_call field
if [[ "$CLOSE_CALL" == "true" ]] && command -v jq &>/dev/null; then
  tmp="${FORGE_DIR}/manifest.json.tmp"
  jq '.close_call = true' "${FORGE_DIR}/manifest.json" > "$tmp" && mv "$tmp" "${FORGE_DIR}/manifest.json"
fi

# ── Output manifest path ────────────────────────────────────────────────────
echo "${FORGE_DIR}/manifest.json"
ai_buddies_debug "forge-run: complete, winner=$WINNER, manifest at ${FORGE_DIR}/manifest.json"
