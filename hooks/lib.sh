#!/usr/bin/env bash
# claudes-ai-buddies — shared helpers
# Sourced by hooks and scripts. Never executed directly.

set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────────────
AI_BUDDIES_HOME="${HOME}/.claudes-ai-buddies"
AI_BUDDIES_CONFIG="${AI_BUDDIES_HOME}/config.json"
AI_BUDDIES_DEBUG_LOG="${AI_BUDDIES_HOME}/debug.log"
AI_BUDDIES_MAX_LOG_SIZE=1048576  # 1MB

# ── Debug logging ────────────────────────────────────────────────────────────
ai_buddies_debug() {
  local debug_enabled="${_AI_BUDDIES_DEBUG_CACHED:-}"
  if [[ -z "$debug_enabled" ]]; then
    debug_enabled="$(ai_buddies_config "debug" "false")"
    export _AI_BUDDIES_DEBUG_CACHED="$debug_enabled"
  fi
  [[ "$debug_enabled" != "true" ]] && return 0

  mkdir -p "$AI_BUDDIES_HOME"

  # Rotate if too large
  if [[ -f "$AI_BUDDIES_DEBUG_LOG" ]]; then
    local size
    size=$(wc -c < "$AI_BUDDIES_DEBUG_LOG" 2>/dev/null || echo 0)
    if (( size > AI_BUDDIES_MAX_LOG_SIZE )); then
      mv "$AI_BUDDIES_DEBUG_LOG" "${AI_BUDDIES_DEBUG_LOG}.old"
    fi
  fi

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$AI_BUDDIES_DEBUG_LOG"
}

# ── Config reader ────────────────────────────────────────────────────────────
# Usage: ai_buddies_config "key" "default_value"
ai_buddies_config() {
  local key="$1"
  local default="${2:-}"

  if [[ -f "$AI_BUDDIES_CONFIG" ]] && command -v jq &>/dev/null; then
    local val
    val=$(jq -r --arg k "$key" '.[$k] // empty' "$AI_BUDDIES_CONFIG" 2>/dev/null)
    if [[ -n "$val" ]]; then
      echo "$val"
      return 0
    fi
  fi

  echo "$default"
}

# ── Config writer ────────────────────────────────────────────────────────────
# Usage: ai_buddies_config_set "key" "value"
ai_buddies_config_set() {
  local key="$1"
  local value="$2"

  mkdir -p "$AI_BUDDIES_HOME"

  if ! command -v jq &>/dev/null; then
    ai_buddies_debug "jq not found, cannot write config"
    return 1
  fi

  local existing="{}"
  [[ -f "$AI_BUDDIES_CONFIG" ]] && existing=$(cat "$AI_BUDDIES_CONFIG")

  local tmp="${AI_BUDDIES_CONFIG}.tmp.$$"
  echo "$existing" | jq --arg k "$key" --arg v "$value" '.[$k] = $v' > "$tmp"
  mv "$tmp" "$AI_BUDDIES_CONFIG"
}

# ── Find codex binary ───────────────────────────────────────────────────────
ai_buddies_find_codex() {
  # Check explicit config override first
  local configured
  configured="$(ai_buddies_config "codex_path" "")"
  if [[ -n "$configured" && -x "$configured" ]]; then
    echo "$configured"
    return 0
  fi

  # Standard PATH lookup
  if command -v codex &>/dev/null; then
    command -v codex
    return 0
  fi

  # Common install locations
  local candidates=(
    "${HOME}/.nvm/versions/node/*/bin/codex"
    "${HOME}/.local/bin/codex"
    "/usr/local/bin/codex"
  )
  for pattern in "${candidates[@]}"; do
    # shellcheck disable=SC2086
    for bin in $pattern; do
      if [[ -x "$bin" ]]; then
        echo "$bin"
        return 0
      fi
    done
  done

  return 1
}

# ── Get codex version ───────────────────────────────────────────────────────
ai_buddies_codex_version() {
  local codex_bin
  codex_bin="$(ai_buddies_find_codex 2>/dev/null)" || return 1
  "$codex_bin" --version 2>/dev/null | head -1
}

# ── Session directory ────────────────────────────────────────────────────────
ai_buddies_session_dir() {
  local session_id="${CLAUDE_SESSION_ID:-default}"
  local dir="/tmp/ai-buddies-${session_id}"
  mkdir -p "$dir"
  echo "$dir"
}

# ── Get model from config cascade ───────────────────────────────────────────
# Priority: plugin config → codex config.toml → fallback
ai_buddies_codex_model() {
  # 1. Plugin config
  local model
  model="$(ai_buddies_config "codex_model" "")"
  if [[ -n "$model" ]]; then
    echo "$model"
    return 0
  fi

  # 2. Codex config.toml
  local codex_config="${HOME}/.codex/config.toml"
  if [[ -f "$codex_config" ]]; then
    local toml_model
    toml_model=$(grep '^model' "$codex_config" | head -1 | sed 's/.*= *"\(.*\)"/\1/')
    if [[ -n "$toml_model" ]]; then
      echo "$toml_model"
      return 0
    fi
  fi

  # 3. Fallback
  echo "gpt-5.4-codex"
}

# ── Find gemini binary ───────────────────────────────────────────────────────
ai_buddies_find_gemini() {
  # Check explicit config override first
  local configured
  configured="$(ai_buddies_config "gemini_path" "")"
  if [[ -n "$configured" && -x "$configured" ]]; then
    echo "$configured"
    return 0
  fi

  # Standard PATH lookup
  if command -v gemini &>/dev/null; then
    command -v gemini
    return 0
  fi

  # Common install locations
  local candidates=(
    "${HOME}/.nvm/versions/node/*/bin/gemini"
    "${HOME}/.local/bin/gemini"
    "/usr/local/bin/gemini"
  )
  for pattern in "${candidates[@]}"; do
    # shellcheck disable=SC2086
    for bin in $pattern; do
      if [[ -x "$bin" ]]; then
        echo "$bin"
        return 0
      fi
    done
  done

  return 1
}

# ── Get gemini version ───────────────────────────────────────────────────────
ai_buddies_gemini_version() {
  local gemini_bin
  gemini_bin="$(ai_buddies_find_gemini 2>/dev/null)" || return 1
  "$gemini_bin" --version 2>/dev/null | head -1
}

# ── Get gemini model ────────────────────────────────────────────────────────
# Priority: plugin config → fallback
ai_buddies_gemini_model() {
  local model
  model="$(ai_buddies_config "gemini_model" "")"
  if [[ -n "$model" ]]; then
    echo "$model"
    return 0
  fi

  echo "gemini-2.5-pro"
}

# ── Get sandbox mode ────────────────────────────────────────────────────────
ai_buddies_sandbox() {
  ai_buddies_config "sandbox" "full-auto"
}

# ── Get default timeout (seconds) ───────────────────────────────────────────
ai_buddies_timeout() {
  ai_buddies_config "timeout" "120"
}

# ── JSON escape ──────────────────────────────────────────────────────────────
ai_buddies_escape_json() {
  local input="$1"
  if command -v jq &>/dev/null; then
    printf '%s' "$input" | jq -Rs .
  else
    # Minimal fallback
    printf '"%s"' "$(printf '%s' "$input" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g')"
  fi
}
