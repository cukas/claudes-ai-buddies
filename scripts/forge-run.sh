#!/usr/bin/env bash
# claudes-ai-buddies — forge orchestrator v2
# Staged escalation: starter → challengers → synthesis.
# Claude is a PURE orchestrator — all engines (including claude) run as subprocesses.
# Usage: forge-run.sh --forge-dir DIR --task "DESC" --fitness "CMD" [--timeout SECS]
#        [--starter ENGINE] [--engines claude,codex,gemini]

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
STARTER=""
REQUESTED_ENGINES=""
AUTO_ACCEPT="$(ai_buddies_forge_auto_accept_score)"
CLEAR_SPREAD="$(ai_buddies_forge_clear_winner_spread)"
ENABLE_SYNTHESIS="$(ai_buddies_forge_enable_synthesis)"
BASELINE_CHECK="$(ai_buddies_forge_require_baseline_check)"
CWD=""

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --forge-dir)       FORGE_DIR="$2";       shift 2 ;;
    --task)            TASK="$2";            shift 2 ;;
    --fitness)         FITNESS="$2";         shift 2 ;;
    --timeout)         TIMEOUT="$2";         shift 2 ;;
    --fitness-timeout) FITNESS_TIMEOUT="$2"; shift 2 ;;
    --starter)         STARTER="$2";         shift 2 ;;
    --engines)         REQUESTED_ENGINES="$2"; shift 2 ;;
    --cwd)             CWD="$2";              shift 2 ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

[[ -z "$FORGE_DIR" ]] && { echo "ERROR: --forge-dir is required" >&2; exit 1; }
[[ -z "$TASK" ]]      && { echo "ERROR: --task is required" >&2; exit 1; }
[[ -z "$FITNESS" ]]   && { echo "ERROR: --fitness is required" >&2; exit 1; }
[[ -z "$CWD" ]]       && { echo "ERROR: --cwd is required (pass the repo working directory)" >&2; exit 1; }

ai_buddies_debug "forge-run: forge_dir=$FORGE_DIR, task=$TASK, timeout=$TIMEOUT"

# ── Cleanup trap ─────────────────────────────────────────────────────────────
_FORGE_RUN_PIDS=()
_FORGE_RUN_WTS=()
_FORGE_RUN_REPO_ROOT=""
_forge_run_cleanup() {
  # Kill background PIDs
  if [[ ${#_FORGE_RUN_PIDS[@]} -gt 0 ]]; then
    for pid in "${_FORGE_RUN_PIDS[@]}"; do
      kill -TERM "$pid" 2>/dev/null || true
    done
  fi
  # Prune any worktrees created during this run
  if [[ -n "$_FORGE_RUN_REPO_ROOT" && ${#_FORGE_RUN_WTS[@]} -gt 0 ]]; then
    for wt in "${_FORGE_RUN_WTS[@]}"; do
      git -C "$_FORGE_RUN_REPO_ROOT" worktree remove "$wt" --force 2>/dev/null || true
    done
  fi
  ai_buddies_debug "forge-run: cleanup trap fired, killed ${#_FORGE_RUN_PIDS[@]} PIDs, removed ${#_FORGE_RUN_WTS[@]} WTs"
}
trap _forge_run_cleanup EXIT INT TERM

# ── Detect available engines ─────────────────────────────────────────────────
CLAUDE_BIN=$(ai_buddies_find_claude 2>/dev/null) || CLAUDE_BIN=""
CODEX_BIN=$(ai_buddies_find_codex 2>/dev/null) || CODEX_BIN=""
GEMINI_BIN=$(ai_buddies_find_gemini 2>/dev/null) || GEMINI_BIN=""

ALL_AVAILABLE=()
[[ -n "$CLAUDE_BIN" ]] && ALL_AVAILABLE+=(claude)
[[ -n "$CODEX_BIN" ]]  && ALL_AVAILABLE+=(codex)
[[ -n "$GEMINI_BIN" ]] && ALL_AVAILABLE+=(gemini)

# Filter by requested engines if specified
ENGINES=()
if [[ -n "$REQUESTED_ENGINES" ]]; then
  IFS=',' read -ra requested <<< "$REQUESTED_ENGINES"
  for r in "${requested[@]}"; do
    for a in "${ALL_AVAILABLE[@]}"; do
      [[ "$r" == "$a" ]] && ENGINES+=("$r")
    done
  done
else
  ENGINES=("${ALL_AVAILABLE[@]}")
fi

if [[ ${#ENGINES[@]} -eq 0 ]]; then
  echo "ERROR: No engines available" >&2
  exit 1
fi

ai_buddies_debug "forge-run: available engines=${ENGINES[*]}"

# ── Pick starter engine ──────────────────────────────────────────────────────
if [[ -z "$STARTER" ]]; then
  STARTER=$(ai_buddies_forge_pick_starter "$(IFS=,; echo "${ENGINES[*]}")")
fi
ai_buddies_debug "forge-run: starter=$STARTER"

# Separate starter from challengers
CHALLENGERS=()
for e in "${ENGINES[@]}"; do
  [[ "$e" != "$STARTER" ]] && CHALLENGERS+=("$e")
done

# ── Resolve repo root from --cwd ─────────────────────────────────────────────
FORGE_CWD="$CWD"
REPO_ROOT=$(cd "$FORGE_CWD" && git rev-parse --show-toplevel 2>/dev/null) || REPO_ROOT=""
HEAD_SHA=$(cd "$FORGE_CWD" && git rev-parse HEAD 2>/dev/null) || HEAD_SHA=""
_FORGE_RUN_REPO_ROOT="$REPO_ROOT"

# ── Helper: create worktree for an engine ────────────────────────────────────
# NOTE: Do NOT call via $(...) command substitution — that runs in a subshell
# and _FORGE_RUN_WTS updates would be lost. Use _create_worktree_for instead.
_create_worktree_for() {
  local engine="$1"
  _LAST_WORKTREE="${FORGE_DIR}/wt-${engine}"
  if [[ -n "$REPO_ROOT" && -n "$HEAD_SHA" ]]; then
    git -C "$REPO_ROOT" worktree prune 2>/dev/null || true
    git -C "$REPO_ROOT" worktree add --detach "$_LAST_WORKTREE" "$HEAD_SHA" >/dev/null 2>&1 || {
      ai_buddies_debug "forge-run: failed to create worktree for $engine"
      _LAST_WORKTREE=""
      return 1
    }
    _FORGE_RUN_WTS+=("$_LAST_WORKTREE")
  else
    ai_buddies_debug "forge-run: cannot determine repo root"
    _LAST_WORKTREE=""
    return 1
  fi
}

# ── Helper: dispatch a single engine ─────────────────────────────────────────
_dispatch_engine() {
  local engine="$1"
  local wt="$2"
  local prompt="$3"
  local timeout="$4"

  case "$engine" in
    claude)
      bash "${PLUGIN_ROOT}/scripts/claude-run.sh" \
        --prompt "$prompt" \
        --cwd "$wt" \
        --mode exec \
        --timeout "$timeout" \
        > "${FORGE_DIR}/${engine}-output.txt" 2>&1
      ;;
    codex)
      bash "${PLUGIN_ROOT}/scripts/codex-run.sh" \
        --prompt "$prompt" \
        --cwd "$wt" \
        --mode exec \
        --timeout "$timeout" \
        > "${FORGE_DIR}/${engine}-output.txt" 2>&1
      ;;
    gemini)
      bash "${PLUGIN_ROOT}/scripts/gemini-run.sh" \
        --prompt "$prompt" \
        --cwd "$wt" \
        --mode exec \
        --timeout "$timeout" \
        > "${FORGE_DIR}/${engine}-output.txt" 2>&1
      ;;
  esac
}

# ── Helper: score an engine's worktree ───────────────────────────────────────
_score_engine() {
  local engine="$1"
  local wt="${FORGE_DIR}/wt-${engine}"
  [[ -d "$wt" ]] || return 1

  # Generate diff
  (cd "$wt" && git add -A && git diff --cached > "${FORGE_DIR}/${engine}-patch.diff") 2>/dev/null || true

  # Check for empty diff (no-op)
  local diff_size
  diff_size=$(wc -c < "${FORGE_DIR}/${engine}-patch.diff" 2>/dev/null | tr -d ' ')
  if (( diff_size == 0 )); then
    ai_buddies_debug "forge-run: $engine produced empty diff (no-op)"
  fi

  # Run fitness
  local fitness_output
  fitness_output=$(bash "${PLUGIN_ROOT}/scripts/forge-fitness.sh" \
    --dir "$wt" \
    --cmd "$FITNESS" \
    --label "$engine" \
    --timeout "$FITNESS_TIMEOUT" 2>&1 | tail -1)

  echo "$fitness_output"
}

# ── Helper: read score from fitness result ───────────────────────────────────
_read_score() {
  local fitness_file="$1"
  local score=0
  if [[ -f "$fitness_file" ]] && command -v jq &>/dev/null; then
    score=$(jq -r '.composite_score // 0' "$fitness_file" 2>/dev/null || echo 0)
  fi
  echo "$score"
}

_read_pass() {
  local fitness_file="$1"
  local pass=false
  if [[ -f "$fitness_file" ]] && command -v jq &>/dev/null; then
    pass=$(jq -r '.pass // false' "$fitness_file" 2>/dev/null || echo false)
  fi
  echo "$pass"
}

# ── Gather task-scoped context (v2: lighter than full project context) ──────
CONTEXT=""
CONTEXT_FILE="${FORGE_DIR}/context.txt"
CONTEXT=$(ai_buddies_task_context "$FORGE_CWD" "$TASK")
if [[ -n "$CONTEXT" ]]; then
  printf '%s' "$CONTEXT" > "$CONTEXT_FILE"
fi

# ── Build compressed prompt ──────────────────────────────────────────────────
FORGE_PROMPT=$(ai_buddies_build_forge_prompt "$TASK" "$FITNESS" "$CONTEXT")

# ── Phase 0: Baseline preflight ─────────────────────────────────────────────
BASELINE_ALREADY_PASSES=false
if [[ "$BASELINE_CHECK" == "true" ]]; then
  ai_buddies_debug "forge-run: running baseline fitness check"
  if _create_worktree_for "baseline"; then
    BASELINE_WT="$_LAST_WORKTREE"
    BASELINE_EXIT=0
    (cd "$BASELINE_WT" && bash -lc "$FITNESS") >/dev/null 2>&1 || BASELINE_EXIT=$?
    if [[ $BASELINE_EXIT -eq 0 ]]; then
      BASELINE_ALREADY_PASSES=true
      # Warning to stderr only — stdout is reserved for manifest path
      echo "WARNING: fitness already passes on untouched code — test may be non-discriminating" >&2
      ai_buddies_debug "forge-run: WARNING — fitness already passes on base code"
    fi
    # Clean up baseline worktree
    git -C "$REPO_ROOT" worktree remove "$BASELINE_WT" --force 2>/dev/null || true
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 1: Run starter engine alone
# ══════════════════════════════════════════════════════════════════════════════
ai_buddies_debug "forge-run: STAGE 1 — dispatching starter: $STARTER"

_create_worktree_for "$STARTER" || {
  echo "ERROR: Failed to create worktree for starter $STARTER" >&2
  exit 1
}
STARTER_WT="$_LAST_WORKTREE"

_dispatch_engine "$STARTER" "$STARTER_WT" "$FORGE_PROMPT" "$TIMEOUT"

# Score starter
STARTER_FITNESS_FILE=$(_score_engine "$STARTER")
STARTER_SCORE=$(_read_score "$STARTER_FITNESS_FILE")
STARTER_PASS=$(_read_pass "$STARTER_FITNESS_FILE")

ai_buddies_debug "forge-run: starter $STARTER pass=$STARTER_PASS score=$STARTER_SCORE"

# Sanitize for arithmetic
STARTER_SCORE_INT="${STARTER_SCORE%%.*}"; STARTER_SCORE_INT="${STARTER_SCORE_INT//[!0-9]/}"; STARTER_SCORE_INT="${STARTER_SCORE_INT:-0}"
AUTO_ACCEPT_INT="${AUTO_ACCEPT%%.*}"; AUTO_ACCEPT_INT="${AUTO_ACCEPT_INT//[!0-9]/}"; AUTO_ACCEPT_INT="${AUTO_ACCEPT_INT:-88}"

# Check auto-accept gate
STAGE1_ACCEPTED=false
if [[ "$STARTER_PASS" == "true" ]] && (( STARTER_SCORE_INT >= AUTO_ACCEPT_INT )); then
  # Additional gates: lint and style
  STARTER_LINT=0
  STARTER_STYLE=100
  if [[ -f "$STARTER_FITNESS_FILE" ]] && command -v jq &>/dev/null; then
    STARTER_LINT=$(jq -r '.lint_warnings // 0' "$STARTER_FITNESS_FILE" 2>/dev/null || echo 0)
    STARTER_STYLE=$(jq -r '.style_score // 100' "$STARTER_FITNESS_FILE" 2>/dev/null || echo 100)
  fi
  STARTER_LINT_INT="${STARTER_LINT%%.*}"; STARTER_LINT_INT="${STARTER_LINT_INT//[!0-9]/}"; STARTER_LINT_INT="${STARTER_LINT_INT:-0}"
  STARTER_STYLE_INT="${STARTER_STYLE%%.*}"; STARTER_STYLE_INT="${STARTER_STYLE_INT//[!0-9]/}"; STARTER_STYLE_INT="${STARTER_STYLE_INT:-100}"

  if (( STARTER_LINT_INT <= 2 && STARTER_STYLE_INT >= 90 )); then
    STAGE1_ACCEPTED=true
    ai_buddies_debug "forge-run: STAGE 1 auto-accepted (score=$STARTER_SCORE_INT, lint=$STARTER_LINT_INT, style=$STARTER_STYLE_INT)"
  fi
fi

# Track all scored engines (fitness files stored as engine:path pairs in indexed array)
SCORED_ENGINES=("$STARTER")
ENGINE_FITNESS_PAIRS=("${STARTER}:${STARTER_FITNESS_FILE}")

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 2: Dispatch challengers (if starter didn't auto-accept)
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$STAGE1_ACCEPTED" != "true" ]] && [[ ${#CHALLENGERS[@]} -gt 0 ]]; then
  ai_buddies_debug "forge-run: STAGE 2 — dispatching challengers: ${CHALLENGERS[*]}"

  CHALLENGER_PIDS=()
  ACTIVE_CHALLENGERS=()

  for engine in "${CHALLENGERS[@]}"; do
    _create_worktree_for "$engine" || continue
    wt="$_LAST_WORKTREE"
    ACTIVE_CHALLENGERS+=("$engine")

    _dispatch_engine "$engine" "$wt" "$FORGE_PROMPT" "$TIMEOUT" &
    CHALLENGER_PIDS+=($!); _FORGE_RUN_PIDS+=($!)
  done

  # Wait for all challengers
  for pid in "${CHALLENGER_PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
  done
  ai_buddies_debug "forge-run: all challengers finished"

  # Score challengers
  for engine in "${ACTIVE_CHALLENGERS[@]}"; do
    fitness_file=$(_score_engine "$engine")
    SCORED_ENGINES+=("$engine")
    ENGINE_FITNESS_PAIRS+=("${engine}:${fitness_file}")
  done
fi

# ══════════════════════════════════════════════════════════════════════════════
# SCORING: Collect results and determine winner
# ══════════════════════════════════════════════════════════════════════════════
RESULTS_JSON="{}"
PATCHES_JSON="{}"
WINNER="none"
BEST_SCORE=0
SECOND_SCORE=0

for engine in "${SCORED_ENGINES[@]}"; do
  # Look up fitness file from pairs array
  fitness_file=""
  for pair in "${ENGINE_FITNESS_PAIRS[@]}"; do
    if [[ "${pair%%:*}" == "$engine" ]]; then
      fitness_file="${pair#*:}"
      break
    fi
  done
  fitness_json="{}"
  [[ -f "$fitness_file" ]] && fitness_json=$(cat "$fitness_file" 2>/dev/null || echo "{}")

  # Extract fields
  pass="false"
  diff_lines=0
  files_changed=0
  duration=0
  lint_warnings=0
  style_score=100
  composite=0

  if command -v jq &>/dev/null && [[ "$fitness_json" != "{}" ]]; then
    pass=$(echo "$fitness_json" | jq -r '.pass // false' 2>/dev/null || echo false)
    diff_lines=$(echo "$fitness_json" | jq -r '.diff_lines // 0' 2>/dev/null || echo 0)
    files_changed=$(echo "$fitness_json" | jq -r '.files_changed // 0' 2>/dev/null || echo 0)
    duration=$(echo "$fitness_json" | jq -r '.duration_sec // 0' 2>/dev/null || echo 0)
    lint_warnings=$(echo "$fitness_json" | jq -r '.lint_warnings // 0' 2>/dev/null || echo 0)
    style_score=$(echo "$fitness_json" | jq -r '.style_score // 100' 2>/dev/null || echo 100)
    composite=$(echo "$fitness_json" | jq -r '.composite_score // 0' 2>/dev/null || echo 0)
  fi

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

  # Sanitize composite for arithmetic
  composite_int="${composite%%.*}"; composite_int="${composite_int//[!0-9]/}"; composite_int="${composite_int:-0}"

  # Deterministic tiebreaker: score > lint(fewer) > style(higher) > diff(fewer) > files(fewer) > duration(less)
  if (( composite_int > BEST_SCORE )); then
    SECOND_SCORE=$BEST_SCORE
    BEST_SCORE=$composite_int
    WINNER="$engine"
  elif (( composite_int > SECOND_SCORE )); then
    SECOND_SCORE=$composite_int
  fi

  ai_buddies_debug "forge-run: $engine pass=$pass score=$composite"
done

# ── Check for close call ─────────────────────────────────────────────────────
CLOSE_CALL=false
SPREAD_INT="${CLEAR_SPREAD%%.*}"; SPREAD_INT="${SPREAD_INT//[!0-9]/}"; SPREAD_INT="${SPREAD_INT:-8}"
if (( BEST_SCORE > 0 && (BEST_SCORE - SECOND_SCORE) < SPREAD_INT )); then
  CLOSE_CALL=true
  ai_buddies_debug "forge-run: close call (spread=$((BEST_SCORE - SECOND_SCORE)) < ${SPREAD_INT})"
fi

# ── Write manifest ───────────────────────────────────────────────────────────
FORGE_ID=$(basename "$FORGE_DIR")
ENGINES_CSV=$(IFS=,; echo "${SCORED_ENGINES[*]}")
ai_buddies_forge_manifest \
  "${FORGE_DIR}/manifest.json" \
  "$FORGE_ID" \
  "$FORGE_DIR" \
  "$TASK" \
  "$ENGINES_CSV" \
  "$RESULTS_JSON" \
  "$PATCHES_JSON" \
  "$WINNER"

# Add metadata fields
if command -v jq &>/dev/null; then
  tmp="${FORGE_DIR}/manifest.json.tmp"
  jq \
    --argjson close_call "$([[ "$CLOSE_CALL" == "true" ]] && echo true || echo false)" \
    --argjson stage1_accepted "$([[ "$STAGE1_ACCEPTED" == "true" ]] && echo true || echo false)" \
    --argjson baseline_passes "$([[ "$BASELINE_ALREADY_PASSES" == "true" ]] && echo true || echo false)" \
    --arg starter "$STARTER" \
    --argjson engines_dispatched "${#SCORED_ENGINES[@]}" \
    '. + {close_call:$close_call, stage1_accepted:$stage1_accepted, baseline_passes:$baseline_passes, starter:$starter, engines_dispatched:$engines_dispatched}' \
    "${FORGE_DIR}/manifest.json" > "$tmp" && mv "$tmp" "${FORGE_DIR}/manifest.json"
fi

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 3: Synthesis (if close call and synthesis enabled)
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$CLOSE_CALL" == "true" && "$ENABLE_SYNTHESIS" == "true" && ${#SCORED_ENGINES[@]} -gt 1 ]]; then
  # Check at least 2 engines passed
  PASSING_COUNT=0
  if command -v jq &>/dev/null; then
    PASSING_COUNT=$(echo "$RESULTS_JSON" | jq '[.[] | select(.pass == true)] | length' 2>/dev/null || echo 0)
  fi

  if (( PASSING_COUNT >= 2 )); then
    ai_buddies_debug "forge-run: STAGE 3 — running synthesis ($PASSING_COUNT passing, close call)"
    bash "${PLUGIN_ROOT}/scripts/forge-synthesize.sh" \
      --forge-dir "$FORGE_DIR" \
      --winner "$WINNER" \
      --fitness "$FITNESS" \
      --timeout "$TIMEOUT" \
      --fitness-timeout "$FITNESS_TIMEOUT" \
      > "${FORGE_DIR}/synth-run-output.txt" 2>&1 || true
  else
    ai_buddies_debug "forge-run: skipping synthesis (only $PASSING_COUNT engines passed)"
  fi
else
  ai_buddies_debug "forge-run: skipping synthesis (close_call=$CLOSE_CALL, enabled=$ENABLE_SYNTHESIS, engines=${#SCORED_ENGINES[@]})"
fi

# ── Output manifest path ────────────────────────────────────────────────────
echo "${FORGE_DIR}/manifest.json"
ai_buddies_debug "forge-run: complete, winner=$WINNER, manifest at ${FORGE_DIR}/manifest.json"
