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

# ── Get codex model (optional override) ──────────────────────────────────────
# Returns the model if explicitly configured, empty string otherwise.
# When empty, codex uses its own default (from ~/.codex/config.toml or server).
ai_buddies_codex_model() {
  # 1. Plugin config override
  local model
  model="$(ai_buddies_config "codex_model" "")"
  if [[ -n "$model" ]]; then
    echo "$model"
    return 0
  fi

  # 2. Read from codex config.toml (for display purposes)
  local codex_config="${HOME}/.codex/config.toml"
  if [[ -f "$codex_config" ]]; then
    local toml_model
    toml_model=$(grep '^model' "$codex_config" | head -1 | sed 's/.*= *"\(.*\)"/\1/')
    if [[ -n "$toml_model" ]]; then
      echo "$toml_model"
      return 0
    fi
  fi

  # 3. No override — let codex use its own default
  echo ""
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

# ── Get gemini model (optional override) ─────────────────────────────────────
# Returns the model if explicitly configured, empty string otherwise.
# When empty, gemini uses its own default (latest from server).
ai_buddies_gemini_model() {
  ai_buddies_config "gemini_model" ""
}

# ── Get sandbox mode ────────────────────────────────────────────────────────
ai_buddies_sandbox() {
  ai_buddies_config "sandbox" "full-auto"
}

# ── Get default timeout (seconds) ───────────────────────────────────────────
ai_buddies_timeout() {
  ai_buddies_config "timeout" "120"
}

# ── Timeout wrapper (shared by all scripts) ─────────────────────────────────
# Usage: ai_buddies_run_with_timeout SECS COMMAND [ARGS...]
ai_buddies_run_with_timeout() {
  local timeout_secs="$1"
  shift

  if command -v gtimeout &>/dev/null; then
    gtimeout "${timeout_secs}s" "$@"
  elif command -v timeout &>/dev/null; then
    timeout "${timeout_secs}s" "$@"
  else
    # Perl-based fallback for macOS without coreutils
    # Uses process group kill (-$$) to reap child trees, not just the direct child
    perl -e '
      use POSIX qw(setpgid);
      alarm shift @ARGV;
      $pid = fork;
      if ($pid == 0) { setpgid(0,0); exec @ARGV; die "exec failed: $!" }
      $SIG{ALRM} = sub { kill -9, $pid; exit 124 };
      waitpid $pid, 0;
      exit ($? >> 8);
    ' "$timeout_secs" "$@"
  fi
}

# ── Build review prompt (shared by codex-run.sh and gemini-run.sh) ──────────
# Usage: ai_buddies_build_review_prompt "user_prompt" "cwd" "target"
ai_buddies_build_review_prompt() {
  local prompt="$1"
  local cwd="$2"
  local target="$3"
  local diff_content=""

  case "$target" in
    uncommitted)
      diff_content=$(cd "$cwd" && git diff HEAD 2>/dev/null || git diff 2>/dev/null || echo "(no diff available)")
      ;;
    branch:*)
      local branch="${target#branch:}"
      diff_content=$(cd "$cwd" && git diff "${branch}...HEAD" 2>/dev/null || echo "(no diff for branch ${branch})")
      ;;
    commit:*)
      local sha="${target#commit:}"
      diff_content=$(cd "$cwd" && git show "$sha" 2>/dev/null || echo "(no diff for commit ${sha})")
      ;;
    *)
      diff_content=$(cd "$cwd" && git diff HEAD 2>/dev/null || echo "(no diff available)")
      ;;
  esac

  cat <<EOF
You are reviewing code changes. Provide a thorough code review covering:
- Bugs and logic errors
- Security vulnerabilities
- Performance issues
- Code quality and readability
- Suggestions for improvement

Here are the changes to review:

\`\`\`diff
${diff_content}
\`\`\`

${prompt}
EOF
}

# ── Project context summary (F4) ─────────────────────────────────────────────
# Reads project info from CWD: CLAUDE.md/README, recent commits, language, conventions.
# Returns formatted block, max 3000 chars. Config key: context_summary (default true).
ai_buddies_project_context() {
  local cwd="${1:-$(pwd)}"
  local enabled
  enabled="$(ai_buddies_config "context_summary" "true")"
  [[ "$enabled" != "true" ]] && return 0

  local ctx=""
  local max_chars=3000

  # 1. Project description from CLAUDE.md or README.md (first 100 lines, cap 2000 chars)
  local desc_file=""
  for candidate in CLAUDE.md .claude/CLAUDE.md README.md readme.md; do
    if [[ -f "${cwd}/${candidate}" ]]; then
      desc_file="${cwd}/${candidate}"
      break
    fi
  done
  if [[ -n "$desc_file" ]]; then
    local desc
    desc=$(head -100 "$desc_file" | head -c 2000)
    ctx+="PROJECT DESCRIPTION (from $(basename "$desc_file")):"$'\n'"${desc}"$'\n\n'
  fi

  # 2. Recent commits for style reference
  local commits
  commits=$(cd "$cwd" && git log --oneline -10 2>/dev/null || echo "")
  if [[ -n "$commits" ]]; then
    ctx+="RECENT COMMITS:"$'\n'"${commits}"$'\n\n'
  fi

  # 3. Detect language from manifest files
  local langs=""
  [[ -f "${cwd}/package.json" ]]     && langs+="JavaScript/TypeScript, "
  [[ -f "${cwd}/pyproject.toml" || -f "${cwd}/setup.py" || -f "${cwd}/requirements.txt" ]] && langs+="Python, "
  [[ -f "${cwd}/Cargo.toml" ]]       && langs+="Rust, "
  [[ -f "${cwd}/go.mod" ]]           && langs+="Go, "
  [[ -f "${cwd}/Gemfile" ]]          && langs+="Ruby, "
  [[ -f "${cwd}/pom.xml" || -f "${cwd}/build.gradle" ]] && langs+="Java, "
  langs="${langs%, }"
  if [[ -n "$langs" ]]; then
    ctx+="LANGUAGES: ${langs}"$'\n'
  fi

  # 4. Conventions (test framework, linting, formatting)
  local conventions=""
  if [[ -f "${cwd}/package.json" ]]; then
    command -v jq &>/dev/null && {
      local test_cmd
      test_cmd=$(jq -r '.scripts.test // empty' "${cwd}/package.json" 2>/dev/null)
      [[ -n "$test_cmd" ]] && conventions+="Test: ${test_cmd}, "
    }
  fi
  [[ -f "${cwd}/.eslintrc" || -f "${cwd}/.eslintrc.json" || -f "${cwd}/.eslintrc.js" || -f "${cwd}/eslint.config.js" ]] && conventions+="ESLint, "
  [[ -f "${cwd}/.prettierrc" || -f "${cwd}/.prettierrc.json" ]] && conventions+="Prettier, "
  [[ -f "${cwd}/pyproject.toml" ]] && grep -q "ruff" "${cwd}/pyproject.toml" 2>/dev/null && conventions+="Ruff, "
  [[ -f "${cwd}/.shellcheckrc" ]] && conventions+="ShellCheck, "
  [[ -f "${cwd}/rustfmt.toml" || -f "${cwd}/.rustfmt.toml" ]] && conventions+="rustfmt, "
  conventions="${conventions%, }"
  if [[ -n "$conventions" ]]; then
    ctx+="CONVENTIONS: ${conventions}"$'\n'
  fi

  # Cap total output
  if [[ ${#ctx} -gt $max_chars ]]; then
    ctx="${ctx:0:$max_chars}..."
  fi

  printf '%s' "$ctx"
}

# ── Forge timeout (F1) ──────────────────────────────────────────────────────
# Reads forge_timeout config key, default 600. Used by forge-run.sh and SKILL.md.
ai_buddies_forge_timeout() {
  ai_buddies_config "forge_timeout" "600"
}

# ── Build forge prompt (F1) ─────────────────────────────────────────────────
# Constructs engine prompt from task + fitness + context. Single source of truth.
# Usage: ai_buddies_build_forge_prompt "task" "fitness_cmd" "context_text"
ai_buddies_build_forge_prompt() {
  local task="$1"
  local fitness="$2"
  local context="${3:-}"

  local prompt="You are competing in a code forge against other AI engines. Implement this task so it passes the fitness test. Best implementation wins."
  prompt+=$'\n\n'"TASK: ${task}"
  prompt+=$'\n'"FITNESS TEST: ${fitness}"

  if [[ -n "$context" ]]; then
    prompt+=$'\n\n'"PROJECT CONTEXT:"$'\n'"${context}"
  fi

  prompt+=$'\n\n'"RULES:"
  prompt+=$'\n'"- Write the actual code — do not plan or ask questions."
  prompt+=$'\n'"- Modify only files necessary. Follow existing conventions."
  prompt+=$'\n'"- After implementing, RUN the fitness test yourself. If it fails, fix and retry until it passes."
  prompt+=$'\n'"- Exit when you'\''re confident the fitness test passes. Take the time you need."
  prompt+=$'\n'"- Be thorough but minimal. Fewest lines changed wins ties."

  printf '%s' "$prompt"
}

# ── Build spectest prompt (F3) ──────────────────────────────────────────────
# Constructs prompt for speculative test generation.
# Usage: ai_buddies_build_spectest_prompt "task" "context_text"
ai_buddies_build_spectest_prompt() {
  local task="$1"
  local context="${2:-}"

  local prompt="Propose fitness tests for this task. Write test files and a run command that will PASS only when the task is correctly implemented and FAIL otherwise."
  prompt+=$'\n\n'"TASK: ${task}"

  if [[ -n "$context" ]]; then
    prompt+=$'\n\n'"PROJECT CONTEXT:"$'\n'"${context}"
  fi

  prompt+=$'\n\n'"RULES:"
  prompt+=$'\n'"- Write actual test files — executable, not pseudocode."
  prompt+=$'\n'"- Tests must be runnable with a single command."
  prompt+=$'\n'"- Tests should fail right now (task not yet implemented) and pass after correct implementation."
  prompt+=$'\n'"- Keep tests focused and minimal. Test behavior, not implementation details."
  prompt+=$'\n'"- Output the run command as the last line of your response, prefixed with RUN_CMD:"

  printf '%s' "$prompt"
}

# ── Forge manifest writer (F1) ──────────────────────────────────────────────
# Writes manifest.json from arguments. Reused by forge-run.sh and forge-spectest.sh.
# Usage: ai_buddies_forge_manifest MANIFEST_FILE FORGE_ID FORGE_DIR TASK ENGINES_CSV RESULTS_JSON PATCHES_JSON WINNER
ai_buddies_forge_manifest() {
  local manifest_file="$1"
  local forge_id="$2"
  local forge_dir="$3"
  local task="$4"
  local engines_csv="$5"   # "claude,codex,gemini"
  local results_json="$6"  # '{"claude":{"pass":true,...},...}'
  local patches_json="$7"  # '{"claude":"path/to/patch",...}'
  local winner="$8"

  if command -v jq &>/dev/null; then
    jq -n \
      --arg fid "$forge_id" \
      --arg fdir "$forge_dir" \
      --arg task "$task" \
      --arg engines "$engines_csv" \
      --argjson results "$results_json" \
      --argjson patches "$patches_json" \
      --arg winner "$winner" \
      '{
        forge_id: $fid,
        forge_dir: $fdir,
        engines: ($engines | split(",")),
        task: $task,
        results: $results,
        patches: $patches,
        winner: $winner
      }' > "$manifest_file"
  else
    ai_buddies_debug "forge-manifest: jq not available, writing minimal JSON"
    cat > "$manifest_file" <<EOF
{"forge_id":"${forge_id}","forge_dir":"${forge_dir}","task":$(ai_buddies_escape_json "$task"),"winner":"${winner}"}
EOF
  fi

  ai_buddies_debug "forge-manifest: wrote ${manifest_file}"
}

# ── Forge status (F2) ───────────────────────────────────────────────────────
# Reads manifest.json, returns one-line summary.
# Usage: ai_buddies_forge_status FORGE_DIR
ai_buddies_forge_status() {
  local forge_dir="$1"
  local manifest="${forge_dir}/manifest.json"

  if [[ ! -f "$manifest" ]]; then
    echo "pending"
    return 0
  fi

  if command -v jq &>/dev/null; then
    local winner engines_count
    winner=$(jq -r '.winner // "none"' "$manifest" 2>/dev/null)
    engines_count=$(jq -r '.engines | length' "$manifest" 2>/dev/null)
    echo "done: winner=${winner}, engines=${engines_count}"
  else
    echo "done: manifest exists"
  fi
}

# ── Compute forge composite score (F5) ──────────────────────────────────────
# Composite 0-100: diff_size 30%, lint 15%, style 15%, files 10%, test_output 10%, duration 5%, shellcheck 15%.
# Pass is a hard filter (score=0 if fail). Scores within 5pts flagged as "close".
# Usage: ai_buddies_compute_forge_score PASS DIFF_LINES FILES_CHANGED DURATION LINT_WARNINGS STYLE_SCORE
# Outputs: composite score (integer 0-100)
ai_buddies_compute_forge_score() {
  local pass="$1"
  # Sanitize inputs: strip non-numeric chars, default to 0/100. Protects against
  # jq returning floats ("12.5"), empty strings, or "null".
  local diff_lines="${2:-0}";       diff_lines="${diff_lines%%.*}";    diff_lines="${diff_lines//[!0-9]/}"; diff_lines="${diff_lines:-0}"
  local files_changed="${3:-0}";    files_changed="${files_changed%%.*}"; files_changed="${files_changed//[!0-9]/}"; files_changed="${files_changed:-0}"
  local duration="${4:-0}";         duration="${duration%%.*}";        duration="${duration//[!0-9]/}"; duration="${duration:-0}"
  local lint_warnings="${5:-0}";    lint_warnings="${lint_warnings%%.*}"; lint_warnings="${lint_warnings//[!0-9]/}"; lint_warnings="${lint_warnings:-0}"
  local style_score="${6:-100}";    style_score="${style_score%%.*}";  style_score="${style_score//[!0-9]/}"; style_score="${style_score:-100}"

  # Hard filter: fail = 0
  [[ "$pass" != "true" ]] && echo "0" && return 0

  # Diff size score (30%): fewer lines = better. 0 lines=100, 500+=0
  local diff_score=100
  if (( diff_lines > 0 )); then
    diff_score=$(( 100 - (diff_lines * 100 / 500) ))
    (( diff_score < 0 )) && diff_score=0 || true
  fi

  # Lint score (15%): 0 warnings=100, 20+=0
  local lint_score=100
  if (( lint_warnings > 0 )); then
    lint_score=$(( 100 - (lint_warnings * 5) ))
    (( lint_score < 0 )) && lint_score=0 || true
  fi

  # Files score (10%): fewer files = better. 1=100, 10+=0
  local files_score=100
  if (( files_changed > 1 )); then
    files_score=$(( 100 - ((files_changed - 1) * 11) ))
    (( files_score < 0 )) && files_score=0 || true
  fi

  # Duration score (5%): faster = better. 0-10s=100, 600s+=0
  local dur_score=100
  if (( duration > 10 )); then
    dur_score=$(( 100 - ((duration - 10) * 100 / 590) ))
    (( dur_score < 0 )) && dur_score=0 || true
  fi

  # Composite: diff 30%, lint 15%, style 15%, files 10%, duration 5%, reserve 25% (test pass)
  # Since pass is a hard filter, the 25% reserve is always 100 when we get here
  local composite=$(( (diff_score * 30 + lint_score * 15 + style_score * 15 + files_score * 10 + dur_score * 5 + 100 * 25) / 100 ))
  (( composite > 100 )) && composite=100 || true

  echo "$composite"
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
