#!/usr/bin/env bash
# claudes-ai-buddies — register a new buddy
# Usage: buddy-register.sh --id NAME --binary BINARY [--display "..."] [--modes exec,review]
#        [--search-paths "/path/one,/path/two"] [--install-hint "pip install ..."]
#        [--timeout SECS]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../hooks/lib.sh
source "${PLUGIN_ROOT}/hooks/lib.sh"

# ── Defaults ─────────────────────────────────────────────────────────────────
BUDDY_ID=""
BINARY=""
DISPLAY_NAME=""
MODES="exec"
SEARCH_PATHS=""
INSTALL_HINT=""
TIMEOUT="120"

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --id)           BUDDY_ID="$2";     shift 2 ;;
    --binary)       BINARY="$2";       shift 2 ;;
    --display)      DISPLAY_NAME="$2"; shift 2 ;;
    --modes)        MODES="$2";        shift 2 ;;
    --search-paths) SEARCH_PATHS="$2"; shift 2 ;;
    --install-hint) INSTALL_HINT="$2"; shift 2 ;;
    --timeout)      TIMEOUT="$2";      shift 2 ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

[[ -z "$BUDDY_ID" ]] && { echo "ERROR: --id is required" >&2; exit 1; }
[[ -z "$BINARY" ]]   && { echo "ERROR: --binary is required" >&2; exit 1; }

# Validate ID (alphanumeric + hyphens only)
if [[ ! "$BUDDY_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "ERROR: --id must be alphanumeric (plus hyphens/underscores)" >&2
  exit 1
fi

# Default display name
[[ -z "$DISPLAY_NAME" ]] && DISPLAY_NAME="$BUDDY_ID"

# ── Build JSON ───────────────────────────────────────────────────────────────
USER_BUDDIES_DIR="${AI_BUDDIES_HOME}/buddies"
mkdir -p "$USER_BUDDIES_DIR"

BUDDY_FILE="${USER_BUDDIES_DIR}/${BUDDY_ID}.json"

# Convert comma-separated modes to JSON array
MODES_JSON="[]"
if command -v jq &>/dev/null; then
  MODES_JSON=$(printf '%s' "$MODES" | jq -R 'split(",")')
fi

# Convert comma-separated search paths to JSON array
PATHS_JSON="[]"
if [[ -n "$SEARCH_PATHS" ]] && command -v jq &>/dev/null; then
  PATHS_JSON=$(printf '%s' "$SEARCH_PATHS" | jq -R 'split(",")')
fi

if command -v jq &>/dev/null; then
  jq -n \
    --argjson schema_version 1 \
    --arg id "$BUDDY_ID" \
    --arg display_name "$DISPLAY_NAME" \
    --arg binary "$BINARY" \
    --argjson search_paths "$PATHS_JSON" \
    --arg version_cmd "--version" \
    --arg model_config_key "${BUDDY_ID}_model" \
    --argjson modes "$MODES_JSON" \
    --argjson is_local false \
    --argjson builtin false \
    --arg adapter_script "buddy-run.sh" \
    --arg install_hint "$INSTALL_HINT" \
    --argjson timeout "$TIMEOUT" \
    '{
      schema_version: $schema_version,
      id: $id,
      display_name: $display_name,
      binary: $binary,
      search_paths: $search_paths,
      version_cmd: [$version_cmd],
      model_config_key: $model_config_key,
      modes: $modes,
      is_local: $is_local,
      builtin: $builtin,
      adapter_script: $adapter_script,
      install_hint: $install_hint,
      timeout: $timeout
    }' > "$BUDDY_FILE"
else
  echo "ERROR: jq is required to register buddies" >&2
  exit 1
fi

echo "Registered buddy '${BUDDY_ID}' at ${BUDDY_FILE}"
ai_buddies_debug "buddy-register: registered ${BUDDY_ID} at ${BUDDY_FILE}"
