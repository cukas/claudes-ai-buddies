#!/usr/bin/env bash
# claudes-ai-buddies — adversarial debate orchestrator (/tribunal)
# Two+ buddies argue opposite positions with evidence citations, then Claude judges.
# Usage: tribunal-run.sh --question "..." --cwd DIR [--rounds N] [--buddies N] [--timeout SECS]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../hooks/lib.sh
source "${PLUGIN_ROOT}/hooks/lib.sh"

# ── Defaults ─────────────────────────────────────────────────────────────────
QUESTION=""
CWD="$(pwd)"
ROUNDS="$(ai_buddies_tribunal_rounds)"
MAX_BUDDIES="$(ai_buddies_tribunal_max_buddies)"
TIMEOUT="$(ai_buddies_forge_timeout)"

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --question) QUESTION="$2";     shift 2 ;;
    --cwd)      CWD="$2";         shift 2 ;;
    --rounds)   ROUNDS="$2";      shift 2 ;;
    --buddies)  MAX_BUDDIES="$2"; shift 2 ;;
    --timeout)  TIMEOUT="$2";     shift 2 ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

[[ -z "$QUESTION" ]] && { echo "ERROR: --question is required" >&2; exit 1; }
[[ -d "$CWD" ]]      || { echo "ERROR: --cwd '$CWD' does not exist" >&2; exit 1; }

ai_buddies_debug "tribunal-run: question=$QUESTION, rounds=$ROUNDS, max_buddies=$MAX_BUDDIES"

# ── Cleanup trap ─────────────────────────────────────────────────────────────
_TRIBUNAL_PIDS=()
_TRIBUNAL_WTS=()
_TRIBUNAL_REPO_ROOT=""
_tribunal_cleanup() {
  for pid in "${_TRIBUNAL_PIDS[@]}"; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  if [[ -n "$_TRIBUNAL_REPO_ROOT" && ${#_TRIBUNAL_WTS[@]} -gt 0 ]]; then
    for wt in "${_TRIBUNAL_WTS[@]}"; do
      git -C "$_TRIBUNAL_REPO_ROOT" worktree remove "$wt" --force 2>/dev/null || true
    done
  fi
  ai_buddies_debug "tribunal-run: cleanup trap fired"
}
trap _tribunal_cleanup EXIT INT TERM

# ── Select buddies ───────────────────────────────────────────────────────────
_available_csv=$(ai_buddies_available_buddies)
ALL_AVAILABLE=()
if [[ -n "$_available_csv" ]]; then
  IFS=',' read -ra ALL_AVAILABLE <<< "$_available_csv"
fi

if [[ ${#ALL_AVAILABLE[@]} -lt 2 ]]; then
  echo "ERROR: Tribunal requires at least 2 available buddies (found ${#ALL_AVAILABLE[@]})" >&2
  exit 1
fi

# Shuffle available buddies so selection isn't always alphabetical.
# Uses seconds-based rotation: rotate the array by (epoch % length) positions.
SHUFFLED=()
if [[ ${#ALL_AVAILABLE[@]} -gt 0 ]]; then
  local_len=${#ALL_AVAILABLE[@]}
  rotation=$(( $(date +%s) % local_len ))
  for (( i=0; i<local_len; i++ )); do
    idx=$(( (i + rotation) % local_len ))
    SHUFFLED+=("${ALL_AVAILABLE[$idx]}")
  done
fi

# Take top N buddies from shuffled list
DEBATERS=()
for id in "${SHUFFLED[@]}"; do
  DEBATERS+=("$id")
  (( ${#DEBATERS[@]} >= MAX_BUDDIES )) && break
done

ai_buddies_debug "tribunal-run: debaters=${DEBATERS[*]}"

# ── Setup working directories ────────────────────────────────────────────────
SESSION_DIR="$(ai_buddies_session_dir)"
TRIBUNAL_DIR="${SESSION_DIR}/tribunal-$(date +%s)-${RANDOM}"
mkdir -p "$TRIBUNAL_DIR"

REPO_ROOT=$(cd "$CWD" && git rev-parse --show-toplevel 2>/dev/null) || REPO_ROOT=""
HEAD_SHA=$(cd "$CWD" && git rev-parse HEAD 2>/dev/null) || HEAD_SHA=""
_TRIBUNAL_REPO_ROOT="$REPO_ROOT"

# ── Assign adversarial positions ─────────────────────────────────────────────
# Position 1: "YES / FOR" — argues the affirmative
# Position 2: "NO / AGAINST" — argues the negative
POSITIONS=()
POSITIONS+=("ARGUE FOR: Yes, this is correct / should be done / is the best approach. Find evidence that supports this position.")
POSITIONS+=("ARGUE AGAINST: No, this is wrong / should not be done / there's a better way. Find evidence that contradicts this position.")
# If more than 2, alternate
for i in $(seq 2 $((${#DEBATERS[@]} - 1))); do
  if (( i % 2 == 0 )); then
    POSITIONS+=("ARGUE FOR (additional perspective): Find further supporting evidence, especially edge cases.")
  else
    POSITIONS+=("ARGUE AGAINST (additional perspective): Find further counterevidence, especially risks and costs.")
  fi
done

# ── Create worktrees for each debater ────────────────────────────────────────
for id in "${DEBATERS[@]}"; do
  wt="${TRIBUNAL_DIR}/wt-${id}"
  if [[ -n "$REPO_ROOT" && -n "$HEAD_SHA" ]]; then
    git -C "$REPO_ROOT" worktree prune 2>/dev/null || true
    git -C "$REPO_ROOT" worktree add --detach "$wt" "$HEAD_SHA" 2>/dev/null || {
      ai_buddies_debug "tribunal-run: failed to create worktree for $id"
      continue
    }
    _TRIBUNAL_WTS+=("$wt")
  else
    # No git repo — just copy CWD
    cp -r "$CWD" "$wt"
  fi
done

# ── Run adversarial rounds ───────────────────────────────────────────────────
ALL_ARGUMENTS="{}"
PREV_ROUND_ARGS=""

for round in $(seq 1 "$ROUNDS"); do
  ai_buddies_debug "tribunal-run: ROUND $round/$ROUNDS"

  ROUND_PIDS=()
  ROUND_DEBATERS=()

  for i in "${!DEBATERS[@]}"; do
    id="${DEBATERS[$i]}"
    position="${POSITIONS[$i]}"
    wt="${TRIBUNAL_DIR}/wt-${id}"
    [[ -d "$wt" ]] || continue

    ROUND_DEBATERS+=("$id")

    # Build round-specific prompt
    tribunal_prompt=$(ai_buddies_build_tribunal_prompt "$QUESTION" "$position" "$round" "$ROUNDS" "$PREV_ROUND_ARGS")

    ai_buddies_dispatch_buddy "$id" "$wt" "$tribunal_prompt" "$TIMEOUT" "$TRIBUNAL_DIR" "$PLUGIN_ROOT" \
      > "${TRIBUNAL_DIR}/${id}-round${round}-output.txt" 2>&1 &
    ROUND_PIDS+=($!); _TRIBUNAL_PIDS+=($!)
  done

  # Wait for all debaters this round
  for pid in "${ROUND_PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  ai_buddies_debug "tribunal-run: round $round complete"

  # Collect arguments from this round
  PREV_ROUND_ARGS=""
  for id in "${ROUND_DEBATERS[@]}"; do
    output_file="${TRIBUNAL_DIR}/${id}-round${round}-output.txt"
    argument=""
    if [[ -f "$output_file" ]]; then
      result_path=$(tail -1 "$output_file")
      [[ -f "$result_path" ]] && argument=$(cat "$result_path" 2>/dev/null || echo "")
    fi

    # Skip timeout/error responses
    if [[ -n "$argument" && "$argument" != TIMEOUT:* && "$argument" != ERROR:* ]]; then
      PREV_ROUND_ARGS+="ARGUMENTS FROM ${id} (round ${round}):"$'\n'"${argument}"$'\n\n'

      # Accumulate in all-arguments JSON
      if command -v jq &>/dev/null; then
        ALL_ARGUMENTS=$(echo "$ALL_ARGUMENTS" | jq \
          --arg id "$id" \
          --arg round "round_${round}" \
          --arg args "$argument" \
          '.[$id] //= {} | .[$id][$round] = $args' 2>/dev/null) || true
      fi
    fi
  done
done

# ── Write tribunal manifest ──────────────────────────────────────────────────
MANIFEST="${TRIBUNAL_DIR}/tribunal-manifest.json"
if command -v jq &>/dev/null; then
  jq -n \
    --arg question "$QUESTION" \
    --argjson rounds "$ROUNDS" \
    --arg debaters "$(IFS=,; echo "${DEBATERS[*]}")" \
    --argjson arguments "$ALL_ARGUMENTS" \
    '{
      question: $question,
      rounds: $rounds,
      debaters: ($debaters | split(",")),
      arguments: $arguments
    }' > "$MANIFEST" 2>/dev/null || {
    echo "{\"question\":$(ai_buddies_escape_json "$QUESTION"),\"debaters\":[],\"arguments\":{}}" > "$MANIFEST"
  }
else
  echo "{\"question\":$(ai_buddies_escape_json "$QUESTION"),\"debaters\":[],\"arguments\":{}}" > "$MANIFEST"
fi

# ── Cleanup worktrees ────────────────────────────────────────────────────────
for id in "${DEBATERS[@]}"; do
  wt="${TRIBUNAL_DIR}/wt-${id}"
  if [[ -n "$REPO_ROOT" ]]; then
    git -C "$REPO_ROOT" worktree remove "$wt" --force 2>/dev/null || true
  else
    rm -rf "$wt"
  fi
done

# ── Output manifest path ────────────────────────────────────────────────────
echo "$MANIFEST"
ai_buddies_debug "tribunal-run: complete, manifest at $MANIFEST"
