#!/usr/bin/env bash
# claudes-ai-buddies — ELO leaderboard formatter
# Usage: elo-show.sh [--task-class CLASS]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../hooks/lib.sh
source "${PLUGIN_ROOT}/hooks/lib.sh"

# ── Defaults ─────────────────────────────────────────────────────────────────
TASK_CLASS=""

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-class) TASK_CLASS="$2"; shift 2 ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

ELO_FILE="$(ai_buddies_elo_file)"

if [[ ! -f "$ELO_FILE" ]]; then
  echo "No ELO data yet. Run /forge to start tracking ratings."
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required to display leaderboard" >&2
  exit 1
fi

# ── Format leaderboard ──────────────────────────────────────────────────────
if [[ -n "$TASK_CLASS" ]]; then
  # Show ratings for a specific task class
  echo "## ELO Leaderboard — ${TASK_CLASS}"
  echo ""
  printf "| %-15s | %-8s | %-6s | %-11s |\n" "Buddy" "Rating" "Games" "Status"
  printf "|%-17s|%-10s|%-8s|%-13s|\n" "-----------------" "----------" "--------" "-------------"

  jq -r --arg c "$TASK_CLASS" '
    to_entries[]
    | select(.value[$c] != null)
    | [.key, (.value[$c].rating | tostring), (.value[$c].games | tostring),
       (if .value[$c].provisional then "provisional" else "established" end)]
    | @tsv
  ' "$ELO_FILE" 2>/dev/null | sort -t$'\t' -k2 -rn | while IFS=$'\t' read -r name rating games status; do
    printf "| %-15s | %-8s | %-6s | %-11s |\n" "$name" "$rating" "$games" "$status"
  done
else
  # Show all task classes
  CLASSES=$(jq -r '[.[] | keys[]] | unique[]' "$ELO_FILE" 2>/dev/null)

  if [[ -z "$CLASSES" ]]; then
    echo "No ELO data yet. Run /forge to start tracking ratings."
    exit 0
  fi

  echo "## ELO Leaderboard — All Classes"
  echo ""

  for class in $CLASSES; do
    echo "### ${class}"
    echo ""
    printf "| %-15s | %-8s | %-6s | %-11s |\n" "Buddy" "Rating" "Games" "Status"
    printf "|%-17s|%-10s|%-8s|%-13s|\n" "-----------------" "----------" "--------" "-------------"

    jq -r --arg c "$class" '
      to_entries[]
      | select(.value[$c] != null)
      | [.key, (.value[$c].rating | tostring), (.value[$c].games | tostring),
         (if .value[$c].provisional then "provisional" else "established" end)]
      | @tsv
    ' "$ELO_FILE" 2>/dev/null | sort -t$'\t' -k2 -rn | while IFS=$'\t' read -r name rating games status; do
      printf "| %-15s | %-8s | %-6s | %-11s |\n" "$name" "$rating" "$games" "$status"
    done
    echo ""
  done
fi
