#!/usr/bin/env bash
# claudes-ai-buddies — session start hook
# Verifies available AI CLIs and emits a status banner.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

ai_buddies_debug "session-start fired (event: ${CLAUDE_HOOK_EVENT:-unknown})"

# ── Detect available engines ─────────────────────────────────────────────────
engines=()

codex_bin="$(ai_buddies_find_codex 2>/dev/null)" || codex_bin=""
if [[ -n "$codex_bin" ]]; then
  codex_version=$("$codex_bin" --version 2>/dev/null | head -1 || echo "unknown")
  codex_model=$(ai_buddies_codex_model)
  engines+=("Codex ${codex_version} (${codex_model})")
fi

gemini_bin="$(ai_buddies_find_gemini 2>/dev/null)" || gemini_bin=""
if [[ -n "$gemini_bin" ]]; then
  gemini_version=$("$gemini_bin" --version 2>/dev/null | head -1 || echo "unknown")
  gemini_model=$(ai_buddies_gemini_model)
  engines+=("Gemini ${gemini_version} (${gemini_model})")
fi

# ── Emit banner ──────────────────────────────────────────────────────────────
if [[ ${#engines[@]} -eq 0 ]]; then
  cat <<'BANNER'
<user-prompt-submit-hook>
[AI Buddies] No peer AI CLIs found.
Install Codex: npm install -g @openai/codex
Install Gemini: npm install -g @google/gemini-cli
</user-prompt-submit-hook>
BANNER
  ai_buddies_debug "no AI CLIs found"
  exit 0
fi

# Build skills list based on what's available
skills=""
[[ -n "$codex_bin" ]] && skills="/codex, /codex-review"
if [[ -n "$gemini_bin" ]]; then
  [[ -n "$skills" ]] && skills="${skills}, "
  skills="${skills}/gemini, /gemini-review"
fi

engine_list=$(printf '%s' "${engines[*]}" | sed 's/ /; /2')

cat <<BANNER
<user-prompt-submit-hook>
[AI Buddies] Ready — ${engines[*]}
Available: ${skills}
</user-prompt-submit-hook>
BANNER

ai_buddies_debug "session-start complete: ${engines[*]}"
