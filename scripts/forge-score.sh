#!/usr/bin/env bash
# claudes-ai-buddies — quality scorer for forge implementations
# Runs available linters on changed files, checks style, outputs JSON.
# Usage: forge-score.sh --dir DIR --diff DIFF_FILE [--label NAME]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../hooks/lib.sh
source "${PLUGIN_ROOT}/hooks/lib.sh"

# ── Defaults ─────────────────────────────────────────────────────────────────
DIR=""
DIFF_FILE=""
LABEL="unknown"

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)   DIR="$2";       shift 2 ;;
    --diff)  DIFF_FILE="$2"; shift 2 ;;
    --label) LABEL="$2";     shift 2 ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

[[ -z "$DIR" ]] && { echo "ERROR: --dir is required" >&2; exit 1; }
[[ -d "$DIR" ]] || { echo "ERROR: --dir '$DIR' does not exist" >&2; exit 1; }

ai_buddies_debug "forge-score: label=$LABEL, dir=$DIR, diff=$DIFF_FILE"

# ── Collect changed files ────────────────────────────────────────────────────
CHANGED_FILES=()
if [[ -n "$DIFF_FILE" && -f "$DIFF_FILE" ]]; then
  while IFS= read -r f; do
    [[ -f "${DIR}/${f}" ]] && CHANGED_FILES+=("$f")
  done < <(grep '^+++ b/' "$DIFF_FILE" 2>/dev/null | sed 's|^+++ b/||' || true)
else
  # Fall back to git diff in the directory
  while IFS= read -r f; do
    [[ -f "${DIR}/${f}" ]] && CHANGED_FILES+=("$f")
  done < <(cd "$DIR" && git diff --cached --name-only 2>/dev/null || true)
fi

ai_buddies_debug "forge-score: ${#CHANGED_FILES[@]} changed files"

# ── Lint detection & execution ───────────────────────────────────────────────
LINT_WARNINGS=0
LINTERS_RUN=0

# ESLint
if command -v npx &>/dev/null && [[ -f "${DIR}/package.json" ]]; then
  JS_FILES=()
  for f in "${CHANGED_FILES[@]}"; do
    case "$f" in *.js|*.ts|*.jsx|*.tsx) JS_FILES+=("$f") ;; esac
  done
  if [[ ${#JS_FILES[@]} -gt 0 ]]; then
    local_warnings=0
    eslint_out=$(cd "$DIR" && npx eslint --no-error-on-unmatched-pattern --format json "${JS_FILES[@]}" 2>/dev/null) || true
    if [[ -n "$eslint_out" ]] && command -v jq &>/dev/null; then
      local_warnings=$(echo "$eslint_out" | jq '[.[].messages | length] | add // 0' 2>/dev/null || echo 0)
    fi
    LINT_WARNINGS=$((LINT_WARNINGS + local_warnings))
    LINTERS_RUN=$((LINTERS_RUN + 1))
    ai_buddies_debug "forge-score: eslint found ${local_warnings} warnings"
  fi
fi

# Ruff (Python)
if command -v ruff &>/dev/null; then
  PY_FILES=()
  for f in "${CHANGED_FILES[@]}"; do
    case "$f" in *.py) PY_FILES+=("$f") ;; esac
  done
  if [[ ${#PY_FILES[@]} -gt 0 ]]; then
    local_warnings=0
    ruff_out=$(cd "$DIR" && ruff check --output-format json "${PY_FILES[@]}" 2>/dev/null) || true
    if [[ -n "$ruff_out" ]] && command -v jq &>/dev/null; then
      local_warnings=$(echo "$ruff_out" | jq 'length' 2>/dev/null || echo 0)
    fi
    LINT_WARNINGS=$((LINT_WARNINGS + local_warnings))
    LINTERS_RUN=$((LINTERS_RUN + 1))
    ai_buddies_debug "forge-score: ruff found ${local_warnings} warnings"
  fi
fi

# ShellCheck
if command -v shellcheck &>/dev/null; then
  SH_FILES=()
  for f in "${CHANGED_FILES[@]}"; do
    case "$f" in *.sh|*.bash) SH_FILES+=("$f") ;; esac
  done
  if [[ ${#SH_FILES[@]} -gt 0 ]]; then
    local_warnings=0
    sc_out=$(cd "$DIR" && shellcheck -f json "${SH_FILES[@]}" 2>/dev/null) || true
    if [[ -n "$sc_out" ]] && command -v jq &>/dev/null; then
      local_warnings=$(echo "$sc_out" | jq 'length' 2>/dev/null || echo 0)
    fi
    LINT_WARNINGS=$((LINT_WARNINGS + local_warnings))
    LINTERS_RUN=$((LINTERS_RUN + 1))
    ai_buddies_debug "forge-score: shellcheck found ${local_warnings} warnings"
  fi
fi

# Clippy (Rust)
if command -v cargo &>/dev/null && [[ -f "${DIR}/Cargo.toml" ]]; then
  RS_FILES=()
  for f in "${CHANGED_FILES[@]}"; do
    case "$f" in *.rs) RS_FILES+=("$f") ;; esac
  done
  if [[ ${#RS_FILES[@]} -gt 0 ]]; then
    local_warnings=0
    clippy_out=$(cd "$DIR" && cargo clippy --message-format json 2>/dev/null) || true
    if [[ -n "$clippy_out" ]]; then
      local_warnings=$(echo "$clippy_out" | grep '"level":"warning"' | wc -l | tr -d ' ')
    fi
    LINT_WARNINGS=$((LINT_WARNINGS + local_warnings))
    LINTERS_RUN=$((LINTERS_RUN + 1))
    ai_buddies_debug "forge-score: clippy found ${local_warnings} warnings"
  fi
fi

# ── Style checks ─────────────────────────────────────────────────────────────
STYLE_SCORE=100
STYLE_ISSUES=0

for f in "${CHANGED_FILES[@]}"; do
  filepath="${DIR}/${f}"
  [[ -f "$filepath" ]] || continue

  # Trailing whitespace (POSIX-compatible, works on macOS)
  tw=$(grep -c '[[:space:]]$' "$filepath" 2>/dev/null || echo 0)
  STYLE_ISSUES=$((STYLE_ISSUES + tw))

  # Lines > 120 chars
  long_lines=$(awk 'length > 120' "$filepath" 2>/dev/null | wc -l | tr -d ' ')
  STYLE_ISSUES=$((STYLE_ISSUES + long_lines))
done

# Deduct 5 points per style issue, floor at 0
if (( STYLE_ISSUES > 0 )); then
  STYLE_SCORE=$(( 100 - (STYLE_ISSUES * 5) ))
  (( STYLE_SCORE < 0 )) && STYLE_SCORE=0
fi

ai_buddies_debug "forge-score: lint=${LINT_WARNINGS}, linters_run=${LINTERS_RUN}, style=${STYLE_SCORE}, style_issues=${STYLE_ISSUES}"

# ── Output JSON ──────────────────────────────────────────────────────────────
if command -v jq &>/dev/null; then
  jq -n \
    --arg label "$LABEL" \
    --argjson lint_warnings "$LINT_WARNINGS" \
    --argjson linters_run "$LINTERS_RUN" \
    --argjson style_score "$STYLE_SCORE" \
    --argjson style_issues "$STYLE_ISSUES" \
    --argjson files_checked "${#CHANGED_FILES[@]}" \
    '{label:$label, lint_warnings:$lint_warnings, linters_run:$linters_run, style_score:$style_score, style_issues:$style_issues, files_checked:$files_checked}'
else
  echo "{\"label\":\"${LABEL}\",\"lint_warnings\":${LINT_WARNINGS},\"linters_run\":${LINTERS_RUN},\"style_score\":${STYLE_SCORE},\"style_issues\":${STYLE_ISSUES},\"files_checked\":${#CHANGED_FILES[@]}}"
fi
