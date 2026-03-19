#!/usr/bin/env bash
# claudes-ai-buddies — session start hook
# Verifies available AI CLIs and emits a status banner.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

ai_buddies_debug "session-start fired (event: ${CLAUDE_HOOK_EVENT:-unknown})"

# ── Detect available engines (v3: dynamic registry) ──────────────────────────
engines=()
buddy_ids=()

while IFS= read -r id; do
  ai_buddies_find_buddy "$id" &>/dev/null || continue
  buddy_version=$(ai_buddies_buddy_version "$id" 2>/dev/null || echo "unknown")
  buddy_model=$(ai_buddies_buddy_model "$id")
  [[ -z "$buddy_model" ]] && buddy_model="default"
  buddy_display=$(ai_buddies_buddy_config "$id" "display_name" "$id")

  # Use short display for banner: "Claude-engine" for claude, display_name for others
  if [[ "$id" == "claude" ]]; then
    engines+=("Claude-engine ${buddy_version} (${buddy_model})")
  else
    engines+=("${buddy_display%% (*} ${buddy_version} (${buddy_model})")
  fi
  buddy_ids+=("$id")
done < <(ai_buddies_list_buddies)

# ── Emit banner ──────────────────────────────────────────────────────────────
if [[ ${#engines[@]} -eq 0 ]]; then
  cat <<'BANNER'
<user-prompt-submit-hook>
[AI Buddies] No peer AI CLIs found.
Install Codex: npm install -g @openai/codex
Install Gemini: npm install -g @google/gemini-cli
Install OpenCode: brew install opencode
</user-prompt-submit-hook>
BANNER
  ai_buddies_debug "no AI CLIs found"
  exit 0
fi

# Build skills list based on what's available
skills=""
has_peer=false
for id in "${buddy_ids[@]}"; do
  case "$id" in
    claude) ;;  # Claude is the orchestrator, not a peer skill
    codex)
      [[ -n "$skills" ]] && skills="${skills}, "
      skills="${skills}/codex, /codex-review"
      has_peer=true
      ;;
    gemini)
      [[ -n "$skills" ]] && skills="${skills}, "
      skills="${skills}/gemini, /gemini-review"
      has_peer=true
      ;;
    opencode)
      [[ -n "$skills" ]] && skills="${skills}, "
      skills="${skills}/opencode, /opencode-review"
      has_peer=true
      ;;
    *)
      # User-registered buddies don't get individual skills yet
      has_peer=true
      ;;
  esac
done

# Multi-buddy skills
if [[ "$has_peer" == "true" ]]; then
  skills="${skills}, /brainstorm"
fi
if [[ ${#buddy_ids[@]} -ge 1 ]]; then
  skills="${skills}, /forge"
fi
# v3 skills
if [[ ${#buddy_ids[@]} -ge 2 ]]; then
  skills="${skills}, /tribunal, /leaderboard"
fi
skills="${skills}, /add-buddy"

cat <<BANNER
<user-prompt-submit-hook>
[AI Buddies] Ready — ${engines[*]}
Available: ${skills}
</user-prompt-submit-hook>
BANNER

ai_buddies_debug "session-start complete: ${engines[*]}"
