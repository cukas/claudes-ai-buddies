#!/usr/bin/env bash
# claudes-ai-buddies — critique-based synthesis for /forge
# Losers critique the winner's diff, winner refines from critiques.
# Usage: forge-synthesize.sh --forge-dir DIR --winner ENGINE --fitness "CMD"
#        [--timeout SECS] [--fitness-timeout SECS]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../hooks/lib.sh
source "${PLUGIN_ROOT}/hooks/lib.sh"

# ── Defaults ─────────────────────────────────────────────────────────────────
FORGE_DIR=""
WINNER=""
FITNESS=""
TIMEOUT="$(ai_buddies_forge_timeout)"
FITNESS_TIMEOUT="120"
SYNTHESIS_TIMEOUT="300"
MAX_CRITIQUES="$(ai_buddies_forge_max_critiques)"

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --forge-dir)         FORGE_DIR="$2";          shift 2 ;;
    --winner)            WINNER="$2";             shift 2 ;;
    --fitness)           FITNESS="$2";            shift 2 ;;
    --timeout)           TIMEOUT="$2";            shift 2 ;;
    --fitness-timeout)   FITNESS_TIMEOUT="$2";    shift 2 ;;
    --synthesis-timeout) SYNTHESIS_TIMEOUT="$2";  shift 2 ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

[[ -z "$FORGE_DIR" ]] && { echo "ERROR: --forge-dir is required" >&2; exit 1; }
[[ -z "$WINNER" ]]    && { echo "ERROR: --winner is required" >&2; exit 1; }
[[ -z "$FITNESS" ]]   && { echo "ERROR: --fitness is required" >&2; exit 1; }

ai_buddies_debug "forge-synthesize: winner=$WINNER, forge_dir=$FORGE_DIR"

# ── Cleanup trap ─────────────────────────────────────────────────────────────
_SYNTH_PIDS=()
_SYNTH_WTS=()
_SYNTH_REPO_ROOT=""
_synth_cleanup() {
  for pid in "${_SYNTH_PIDS[@]}"; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  if [[ -n "$_SYNTH_REPO_ROOT" && ${#_SYNTH_WTS[@]} -gt 0 ]]; then
    for wt in "${_SYNTH_WTS[@]}"; do
      git -C "$_SYNTH_REPO_ROOT" worktree remove "$wt" --force 2>/dev/null || true
    done
  fi
  ai_buddies_debug "forge-synthesize: cleanup trap fired, killed ${#_SYNTH_PIDS[@]} PIDs, removed ${#_SYNTH_WTS[@]} WTs"
}
trap _synth_cleanup EXIT INT TERM

# ── Read manifest to find engines and scores ─────────────────────────────────
MANIFEST="${FORGE_DIR}/manifest.json"
[[ -f "$MANIFEST" ]] || { echo "ERROR: manifest.json not found" >&2; exit 1; }

ENGINES=()
LOSERS=()
if command -v jq &>/dev/null; then
  while IFS= read -r e; do ENGINES+=("$e"); done < <(jq -r '.engines[]' "$MANIFEST" 2>/dev/null)
  for e in "${ENGINES[@]}"; do
    [[ "$e" != "$WINNER" ]] && LOSERS+=("$e")
  done
fi

if [[ ${#LOSERS[@]} -eq 0 ]]; then
  ai_buddies_debug "forge-synthesize: no losers to critique, skipping"
  echo "$MANIFEST"
  exit 0
fi

# ── Read winner's diff ───────────────────────────────────────────────────────
WINNER_DIFF=""
WINNER_PATCH="${FORGE_DIR}/${WINNER}-patch.diff"
[[ -f "$WINNER_PATCH" ]] && WINNER_DIFF=$(cat "$WINNER_PATCH")

WINNER_SCORE=0
if command -v jq &>/dev/null; then
  WINNER_SCORE=$(jq -r ".results.${WINNER}.score // 0" "$MANIFEST" 2>/dev/null || echo 0)
fi

# ── Phase 1: Dispatch losers for critique hunks ─────────────────────────────
ai_buddies_debug "forge-synthesize: requesting critiques from ${LOSERS[*]}"

CRITIQUE_PROMPT=$(ai_buddies_build_critique_prompt "$WINNER" "$WINNER_DIFF" "$MAX_CRITIQUES")
CRITIQUE_PIDS=()
CRITIQUE_ENGINES=()

for engine in "${LOSERS[@]}"; do
  wt="${FORGE_DIR}/wt-${engine}"
  [[ -d "$wt" ]] || continue
  CRITIQUE_ENGINES+=("$engine")

  case "$engine" in
    claude)
      bash "${PLUGIN_ROOT}/scripts/claude-run.sh" \
        --prompt "$CRITIQUE_PROMPT" \
        --cwd "$wt" \
        --mode exec \
        --timeout "$SYNTHESIS_TIMEOUT" \
        > "${FORGE_DIR}/${engine}-critique-output.txt" 2>&1 &
      CRITIQUE_PIDS+=($!); _SYNTH_PIDS+=($!)
      ;;
    codex)
      bash "${PLUGIN_ROOT}/scripts/codex-run.sh" \
        --prompt "$CRITIQUE_PROMPT" \
        --cwd "$wt" \
        --mode exec \
        --timeout "$SYNTHESIS_TIMEOUT" \
        > "${FORGE_DIR}/${engine}-critique-output.txt" 2>&1 &
      CRITIQUE_PIDS+=($!); _SYNTH_PIDS+=($!)
      ;;
    gemini)
      bash "${PLUGIN_ROOT}/scripts/gemini-run.sh" \
        --prompt "$CRITIQUE_PROMPT" \
        --cwd "$wt" \
        --mode exec \
        --timeout "$SYNTHESIS_TIMEOUT" \
        > "${FORGE_DIR}/${engine}-critique-output.txt" 2>&1 &
      CRITIQUE_PIDS+=($!); _SYNTH_PIDS+=($!)
      ;;
  esac
done

for pid in "${CRITIQUE_PIDS[@]}"; do
  wait "$pid" 2>/dev/null || true
done
ai_buddies_debug "forge-synthesize: all critiques received"

# ── Collect critiques ────────────────────────────────────────────────────────
ALL_CRITIQUES=""
for engine in "${CRITIQUE_ENGINES[@]}"; do
  output_file="${FORGE_DIR}/${engine}-critique-output.txt"
  critique_text=""
  if [[ -f "$output_file" ]]; then
    result_path=$(tail -1 "$output_file")
    [[ -f "$result_path" ]] && critique_text=$(cat "$result_path" 2>/dev/null || echo "")
  fi
  if [[ -n "$critique_text" && "$critique_text" != TIMEOUT:* && "$critique_text" != ERROR:* ]]; then
    ALL_CRITIQUES+="CRITIQUES FROM ${engine}:"$'\n'"${critique_text}"$'\n\n'
  fi
done

if [[ -z "$ALL_CRITIQUES" ]]; then
  ai_buddies_debug "forge-synthesize: no valid critiques received, keeping original winner"
  echo "$MANIFEST"
  exit 0
fi

# ── Phase 2: Winner refines from critiques in fresh synth worktree ───────────
SYNTH_WT="${FORGE_DIR}/wt-synth"
WINNER_WT="${FORGE_DIR}/wt-${WINNER}"

# Create synth worktree from winner state
if [[ -d "$WINNER_WT" ]]; then
  REPO_ROOT=$(cd "$WINNER_WT" && git rev-parse --show-toplevel 2>/dev/null) || REPO_ROOT=""
  _SYNTH_REPO_ROOT="$REPO_ROOT"
  if [[ -n "$REPO_ROOT" ]]; then
    head_sha=$(cd "$WINNER_WT" && git rev-parse HEAD)
    git -C "$REPO_ROOT" worktree prune 2>/dev/null || true
    git -C "$REPO_ROOT" worktree add --detach "$SYNTH_WT" "$head_sha" 2>/dev/null || {
      ai_buddies_debug "forge-synthesize: failed to create synth worktree"
      echo "$MANIFEST"
      exit 0
    }
    _SYNTH_WTS+=("$SYNTH_WT")
    # Apply winner's changes to synth worktree
    if [[ -f "$WINNER_PATCH" && -s "$WINNER_PATCH" ]]; then
      (cd "$SYNTH_WT" && git apply --allow-empty "$WINNER_PATCH" 2>/dev/null) || {
        ai_buddies_debug "forge-synthesize: failed to apply winner patch to synth worktree"
        git -C "$REPO_ROOT" worktree remove "$SYNTH_WT" --force 2>/dev/null || true
        echo "$MANIFEST"
        exit 0
      }
    fi
  else
    ai_buddies_debug "forge-synthesize: cannot determine repo root"
    echo "$MANIFEST"
    exit 0
  fi
else
  ai_buddies_debug "forge-synthesize: winner worktree not found"
  echo "$MANIFEST"
  exit 0
fi

# Build synthesis prompt and dispatch to winner engine
SYNTH_PROMPT=$(ai_buddies_build_synthesis_prompt "$WINNER_DIFF" "$ALL_CRITIQUES" "$FITNESS")

ai_buddies_debug "forge-synthesize: dispatching refinement to $WINNER"

case "$WINNER" in
  claude)
    bash "${PLUGIN_ROOT}/scripts/claude-run.sh" \
      --prompt "$SYNTH_PROMPT" \
      --cwd "$SYNTH_WT" \
      --mode exec \
      --timeout "$SYNTHESIS_TIMEOUT" \
      > "${FORGE_DIR}/synth-output.txt" 2>&1
    ;;
  codex)
    bash "${PLUGIN_ROOT}/scripts/codex-run.sh" \
      --prompt "$SYNTH_PROMPT" \
      --cwd "$SYNTH_WT" \
      --mode exec \
      --timeout "$SYNTHESIS_TIMEOUT" \
      > "${FORGE_DIR}/synth-output.txt" 2>&1
    ;;
  gemini)
    bash "${PLUGIN_ROOT}/scripts/gemini-run.sh" \
      --prompt "$SYNTH_PROMPT" \
      --cwd "$SYNTH_WT" \
      --mode exec \
      --timeout "$SYNTHESIS_TIMEOUT" \
      > "${FORGE_DIR}/synth-output.txt" 2>&1
    ;;
esac

# ── Phase 3: Score the synthesized version ───────────────────────────────────
# Generate diff
(cd "$SYNTH_WT" && git add -A && git diff --cached > "${FORGE_DIR}/synth-patch.diff") 2>/dev/null || true

# Run fitness
SYNTH_FITNESS_FILE=$(bash "${PLUGIN_ROOT}/scripts/forge-fitness.sh" \
  --dir "$SYNTH_WT" \
  --cmd "$FITNESS" \
  --label "synth" \
  --timeout "$FITNESS_TIMEOUT" 2>&1 | tail -1)

SYNTH_PASS=false
SYNTH_SCORE=0
if [[ -f "$SYNTH_FITNESS_FILE" ]] && command -v jq &>/dev/null; then
  SYNTH_PASS=$(jq -r '.pass // false' "$SYNTH_FITNESS_FILE" 2>/dev/null || echo false)
  SYNTH_SCORE=$(jq -r '.composite_score // 0' "$SYNTH_FITNESS_FILE" 2>/dev/null || echo 0)
fi

ai_buddies_debug "forge-synthesize: synth pass=$SYNTH_PASS score=$SYNTH_SCORE vs winner score=$WINNER_SCORE"

# ── Phase 4: Compare and decide ─────────────────────────────────────────────
SYNTH_WINS=false
# Sanitize scores for arithmetic
SYNTH_SCORE_INT="${SYNTH_SCORE%%.*}"; SYNTH_SCORE_INT="${SYNTH_SCORE_INT//[!0-9]/}"; SYNTH_SCORE_INT="${SYNTH_SCORE_INT:-0}"
WINNER_SCORE_INT="${WINNER_SCORE%%.*}"; WINNER_SCORE_INT="${WINNER_SCORE_INT//[!0-9]/}"; WINNER_SCORE_INT="${WINNER_SCORE_INT:-0}"

if [[ "$SYNTH_PASS" == "true" ]] && (( SYNTH_SCORE_INT > WINNER_SCORE_INT )); then
  SYNTH_WINS=true
  ai_buddies_debug "forge-synthesize: synthesis improved score ($SYNTH_SCORE_INT > $WINNER_SCORE_INT)"
else
  ai_buddies_debug "forge-synthesize: synthesis did NOT improve (synth=$SYNTH_SCORE_INT, winner=$WINNER_SCORE_INT), keeping original"
fi

# ── Write synthesis result to manifest ───────────────────────────────────────
if command -v jq &>/dev/null; then
  tmp="${MANIFEST}.synth.tmp"
  jq \
    --argjson synth_pass "$([[ "$SYNTH_PASS" == "true" ]] && echo true || echo false)" \
    --argjson synth_score "$SYNTH_SCORE_INT" \
    --argjson synth_wins "$([[ "$SYNTH_WINS" == "true" ]] && echo true || echo false)" \
    --arg synth_patch "${FORGE_DIR}/synth-patch.diff" \
    --argjson original_winner_score "$WINNER_SCORE_INT" \
    '.synthesis = {pass:$synth_pass, score:$synth_score, wins:$synth_wins, patch:$synth_patch, original_winner_score:$original_winner_score}' \
    "$MANIFEST" > "$tmp" && mv "$tmp" "$MANIFEST"

  # If synthesis won, rewrite winner, patches, and results so downstream reads the right data
  if [[ "$SYNTH_WINS" == "true" ]]; then
    # Read synth fitness details for results
    SYNTH_DIFF_LINES=0
    SYNTH_FILES=0
    SYNTH_DURATION=0
    SYNTH_LINT=0
    SYNTH_STYLE=100
    if [[ -f "$SYNTH_FITNESS_FILE" ]]; then
      SYNTH_DIFF_LINES=$(jq -r '.diff_lines // 0' "$SYNTH_FITNESS_FILE" 2>/dev/null || echo 0)
      SYNTH_FILES=$(jq -r '.files_changed // 0' "$SYNTH_FITNESS_FILE" 2>/dev/null || echo 0)
      SYNTH_DURATION=$(jq -r '.duration_sec // 0' "$SYNTH_FITNESS_FILE" 2>/dev/null || echo 0)
      SYNTH_LINT=$(jq -r '.lint_warnings // 0' "$SYNTH_FITNESS_FILE" 2>/dev/null || echo 0)
      SYNTH_STYLE=$(jq -r '.style_score // 100' "$SYNTH_FITNESS_FILE" 2>/dev/null || echo 100)
    fi

    tmp="${MANIFEST}.winner.tmp"
    jq \
      --arg synth_patch "${FORGE_DIR}/synth-patch.diff" \
      --argjson synth_score "$SYNTH_SCORE_INT" \
      --argjson diff_lines "$SYNTH_DIFF_LINES" \
      --argjson files "$SYNTH_FILES" \
      --argjson duration "$SYNTH_DURATION" \
      --argjson lint "$SYNTH_LINT" \
      --argjson style "$SYNTH_STYLE" \
      '
        .winner_source = "synthesis" |
        .winner = "synthesis" |
        .patches.synthesis = $synth_patch |
        .results.synthesis = {pass:true, score:$synth_score, diff_lines:$diff_lines, files_changed:$files, duration_sec:$duration, lint_warnings:$lint, style_score:$style}
      ' "$MANIFEST" > "$tmp" && mv "$tmp" "$MANIFEST"
  fi
fi

# ── Cleanup synth worktree ───────────────────────────────────────────────────
if [[ -n "${REPO_ROOT:-}" ]]; then
  git -C "$REPO_ROOT" worktree remove "$SYNTH_WT" --force 2>/dev/null || true
fi

echo "$MANIFEST"
ai_buddies_debug "forge-synthesize: complete, synth_wins=$SYNTH_WINS"
