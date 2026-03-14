#!/usr/bin/env bash
# claudes-ai-buddies — ELO rating calculator
# Pure awk/jq ELO update. Stores per-task-class ratings.
# Usage: elo-update.sh --winner ID --loser ID [--task-class CLASS]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../hooks/lib.sh
source "${PLUGIN_ROOT}/hooks/lib.sh"

# ── Defaults ─────────────────────────────────────────────────────────────────
WINNER=""
LOSER=""
TASK_CLASS="other"

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --winner)     WINNER="$2";     shift 2 ;;
    --loser)      LOSER="$2";      shift 2 ;;
    --task-class) TASK_CLASS="$2"; shift 2 ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

[[ -z "$WINNER" ]] && { echo "ERROR: --winner is required" >&2; exit 1; }
[[ -z "$LOSER" ]]  && { echo "ERROR: --loser is required" >&2; exit 1; }

if [[ "$(ai_buddies_elo_enabled)" != "true" ]]; then
  ai_buddies_debug "elo-update: ELO disabled, skipping"
  exit 0
fi

ELO_FILE="$(ai_buddies_elo_file)"
K_FACTOR="$(ai_buddies_elo_k_factor)"

# Ensure file exists
mkdir -p "$(dirname "$ELO_FILE")"
[[ -f "$ELO_FILE" ]] || echo '{}' > "$ELO_FILE"

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required for ELO updates" >&2
  exit 1
fi

# ── Read current ratings ─────────────────────────────────────────────────────
DEFAULT_RATING=1200

get_rating() {
  local id="$1"
  local class="$2"
  local rating=""
  rating=$(jq -r --arg id "$id" --arg c "$class" \
    '.[$id][$c].rating // empty' "$ELO_FILE" 2>/dev/null) || true
  if [[ -z "$rating" || "$rating" == "null" ]]; then
    echo "$DEFAULT_RATING"
  else
    echo "$rating"
  fi
}

get_games() {
  local id="$1"
  local class="$2"
  local games=""
  games=$(jq -r --arg id "$id" --arg c "$class" \
    '.[$id][$c].games // 0' "$ELO_FILE" 2>/dev/null) || true
  if [[ -z "$games" || "$games" == "null" ]]; then
    echo "0"
  else
    echo "$games"
  fi
}

WINNER_RATING=$(get_rating "$WINNER" "$TASK_CLASS")
LOSER_RATING=$(get_rating "$LOSER" "$TASK_CLASS")
WINNER_GAMES=$(get_games "$WINNER" "$TASK_CLASS")
LOSER_GAMES=$(get_games "$LOSER" "$TASK_CLASS")

# ── Calculate new ratings (ELO formula) ──────────────────────────────────────
# Expected scores
NEW_RATINGS=$(awk -v wr="$WINNER_RATING" -v lr="$LOSER_RATING" -v k="$K_FACTOR" '
BEGIN {
  ew = 1 / (1 + 10^((lr - wr) / 400))
  el = 1 / (1 + 10^((wr - lr) / 400))
  new_wr = wr + k * (1 - ew)
  new_lr = lr + k * (0 - el)
  # Floor at 100
  if (new_lr < 100) new_lr = 100
  printf "%d %d\n", new_wr, new_lr
}')

NEW_WINNER_RATING=$(echo "$NEW_RATINGS" | awk '{print $1}')
NEW_LOSER_RATING=$(echo "$NEW_RATINGS" | awk '{print $2}')
NEW_WINNER_GAMES=$((WINNER_GAMES + 1))
NEW_LOSER_GAMES=$((LOSER_GAMES + 1))

# Provisional status: < 10 games
WINNER_PROVISIONAL="false"
LOSER_PROVISIONAL="false"
(( NEW_WINNER_GAMES < 10 )) && WINNER_PROVISIONAL="true"
(( NEW_LOSER_GAMES < 10 )) && LOSER_PROVISIONAL="true"

# ── Write updated ratings ────────────────────────────────────────────────────
TMP_FILE="${ELO_FILE}.tmp.$$"
jq \
  --arg w "$WINNER" \
  --arg l "$LOSER" \
  --arg c "$TASK_CLASS" \
  --argjson wr "$NEW_WINNER_RATING" \
  --argjson lr "$NEW_LOSER_RATING" \
  --argjson wg "$NEW_WINNER_GAMES" \
  --argjson lg "$NEW_LOSER_GAMES" \
  --argjson wp "$WINNER_PROVISIONAL" \
  --argjson lp "$LOSER_PROVISIONAL" \
  '
    .[$w][$c] = {rating: $wr, games: $wg, provisional: $wp} |
    .[$l][$c] = {rating: $lr, games: $lg, provisional: $lp}
  ' "$ELO_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$ELO_FILE"

ai_buddies_debug "elo-update: ${WINNER} (${WINNER_RATING}->${NEW_WINNER_RATING}) beat ${LOSER} (${LOSER_RATING}->${NEW_LOSER_RATING}) in ${TASK_CLASS}"

echo "ELO updated: ${WINNER} ${WINNER_RATING}->${NEW_WINNER_RATING}, ${LOSER} ${LOSER_RATING}->${NEW_LOSER_RATING} (${TASK_CLASS})"
