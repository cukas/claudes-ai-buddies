#!/usr/bin/env bash
# claudes-ai-buddies — session start hook
# Verifies codex CLI is available and emits a status banner.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

ai_buddies_debug "session-start fired (event: ${CLAUDE_HOOK_EVENT:-unknown})"

# ── Check codex availability ─────────────────────────────────────────────────
codex_bin="$(ai_buddies_find_codex 2>/dev/null)" || codex_bin=""

if [[ -z "$codex_bin" ]]; then
  cat <<'BANNER'
<user-prompt-submit-hook>
[AI Buddies] codex CLI not found. Install it: npm install -g @openai/codex
Skills /codex and /codex-review are disabled until codex is available.
</user-prompt-submit-hook>
BANNER
  ai_buddies_debug "codex binary not found"
  exit 0
fi

# ── Get version and model ───────────────────────────────────────────────────
version=$("$codex_bin" --version 2>/dev/null | head -1 || echo "unknown")
model=$(ai_buddies_codex_model)

cat <<BANNER
<user-prompt-submit-hook>
[AI Buddies] Ready — Codex ${version} | model: ${model}
Use /codex to brainstorm or delegate, /codex-review for code reviews.
</user-prompt-submit-hook>
BANNER

ai_buddies_debug "session-start complete: ${version}, model: ${model}"
