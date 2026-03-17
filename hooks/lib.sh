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

# NOTE: find_claude, find_codex, find_gemini, and their version/model helpers
# are now thin wrappers around the generic buddy registry at the bottom of this file.

# ── Session directory ────────────────────────────────────────────────────────
ai_buddies_session_dir() {
  local session_id="${CLAUDE_SESSION_ID:-default}"
  local dir="/tmp/ai-buddies-${session_id}"
  mkdir -p "$dir"
  echo "$dir"
}




# ── Get sandbox mode ────────────────────────────────────────────────────────
ai_buddies_sandbox() {
  ai_buddies_config "sandbox" "full-auto"
}

# ── Get default timeout (seconds) ───────────────────────────────────────────
# Default 360s (6 min) — Codex regularly needs 5-6 min for non-trivial tasks.
ai_buddies_timeout() {
  ai_buddies_config "timeout" "360"
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

  # Cap diff at 100K chars to avoid exceeding context windows or shell arg limits
  local max_diff_chars=100000

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

  # Truncate if too large
  if [[ ${#diff_content} -gt $max_diff_chars ]]; then
    diff_content="${diff_content:0:$max_diff_chars}"$'\n'"... (truncated — diff exceeded ${max_diff_chars} chars)"
  fi

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

# ── Forge v2 config helpers ─────────────────────────────────────────────────
ai_buddies_forge_auto_accept_score() {
  ai_buddies_config "forge_auto_accept_score" "88"
}

ai_buddies_forge_clear_winner_spread() {
  ai_buddies_config "forge_clear_winner_spread" "8"
}

ai_buddies_forge_enable_synthesis() {
  ai_buddies_config "forge_enable_synthesis" "true"
}

ai_buddies_forge_max_critiques() {
  ai_buddies_config "forge_max_critiques" "3"
}

ai_buddies_forge_starter_strategy() {
  ai_buddies_config "forge_starter_strategy" "fixed"
}

ai_buddies_forge_fixed_starter() {
  ai_buddies_config "forge_fixed_starter" "claude"
}

ai_buddies_forge_require_baseline_check() {
  ai_buddies_config "forge_require_baseline_check" "true"
}

ai_buddies_forge_enabled_engines() {
  ai_buddies_config "forge_enabled_engines" "claude,codex,gemini"
}

# ── Forge starter picker ────────────────────────────────────────────────────
# Picks the starter engine based on strategy and available engines.
# Usage: ai_buddies_forge_pick_starter "claude,codex,gemini"
ai_buddies_forge_pick_starter() {
  local available_csv="$1"
  local strategy
  strategy="$(ai_buddies_forge_starter_strategy)"

  IFS=',' read -ra available <<< "$available_csv"

  case "$strategy" in
    rotate)
      # Use seconds-based rotation across available engines
      local count=${#available[@]}
      if (( count > 0 )); then
        local idx=$(( $(date +%s) % count ))
        echo "${available[$idx]}"
      else
        echo "claude"
      fi
      ;;
    fixed|*)
      local preferred
      preferred="$(ai_buddies_forge_fixed_starter)"
      # Check if preferred is available
      for e in "${available[@]}"; do
        if [[ "$e" == "$preferred" ]]; then
          echo "$preferred"
          return 0
        fi
      done
      # Fallback to first available
      echo "${available[0]:-claude}"
      ;;
  esac
}

# ── Build forge prompt (F1 — v2 compressed) ─────────────────────────────────
# Constructs engine prompt from task + fitness + context. Compressed format.
# Usage: ai_buddies_build_forge_prompt "task" "fitness_cmd" "context_text"
ai_buddies_build_forge_prompt() {
  local task="$1"
  local fitness="$2"
  local context="${3:-}"

  local prompt="TASK"$'\n'"${task}"
  prompt+=$'\n\n'"FITNESS"$'\n'"${fitness}"

  if [[ -n "$context" ]]; then
    prompt+=$'\n\n'"CONTEXT"$'\n'"${context}"
  fi

  prompt+=$'\n\n'"CONSTRAINTS"
  prompt+=$'\n'"- Write code, not plans. No questions."
  prompt+=$'\n'"- Modify only necessary files. Follow existing conventions."
  prompt+=$'\n'"- Run the fitness test. If it fails, fix and retry."
  prompt+=$'\n'"- Exit when fitness passes. Fewest lines changed wins ties."

  printf '%s' "$prompt"
}

# ── Build critique prompt (v2 synthesis) ─────────────────────────────────────
# Asks a losing engine to critique the winner's diff.
# Usage: ai_buddies_build_critique_prompt "winner_engine" "winner_diff" "max_critiques"
ai_buddies_build_critique_prompt() {
  local winner="$1"
  local diff="$2"
  local max="${3:-3}"

  # Cap diff at 50K to avoid context overflow
  if [[ ${#diff} -gt 50000 ]]; then
    diff="${diff:0:50000}"$'\n'"... (truncated)"
  fi

  local prompt="Review this winning implementation and find specific improvements."
  prompt+=$'\n\n'"WINNER DIFF (from ${winner}):"$'\n'"${diff}"
  prompt+=$'\n\n'"Respond with ONLY a JSON array of max ${max} critiques. No other text."
  prompt+=$'\n'"Each critique must target the diff lines. No redesigns or rewrites."
  prompt+=$'\n\n'"FORMAT:"
  prompt+=$'\n''[{"file":"path","lines":"N-M","problem":"...","minimal_fix":"..."}]'
  prompt+=$'\n\n'"Return [] if the implementation is solid."

  printf '%s' "$prompt"
}

# ── Build synthesis prompt (v2 synthesis) ────────────────────────────────────
# Asks the winner engine to refine based on critique hunks.
# Usage: ai_buddies_build_synthesis_prompt "winner_diff" "critiques_text" "fitness_cmd"
ai_buddies_build_synthesis_prompt() {
  local diff="$1"
  local critiques="$2"
  local fitness="$3"

  # Cap diff at 50K to avoid context overflow
  if [[ ${#diff} -gt 50000 ]]; then
    diff="${diff:0:50000}"$'\n'"... (truncated)"
  fi

  local prompt="TASK"$'\n'"Refine your implementation using these specific critiques. Apply only what improves the code."
  prompt+=$'\n\n'"YOUR CURRENT DIFF:"$'\n'"${diff}"
  prompt+=$'\n\n'"CRITIQUES TO ADDRESS:"$'\n'"${critiques}"
  prompt+=$'\n\n'"FITNESS"$'\n'"${fitness}"
  prompt+=$'\n\n'"CONSTRAINTS"
  prompt+=$'\n'"- Apply valid critiques only. Reject vague or incorrect ones."
  prompt+=$'\n'"- Run the fitness test after changes. Must still pass."
  prompt+=$'\n'"- Keep changes minimal. Do not refactor beyond critiques."

  printf '%s' "$prompt"
}

# ── Task-scoped context (v2 — lighter than project_context) ──────────────────
# Only includes candidate files, fitness command, and top conventions.
# Usage: ai_buddies_task_context "cwd" "task_description"
ai_buddies_task_context() {
  local cwd="${1:-$(pwd)}"
  local task="${2:-}"
  local ctx=""

  # 1. Detect conventions (compact)
  local conventions=""
  [[ -f "${cwd}/.eslintrc" || -f "${cwd}/.eslintrc.json" || -f "${cwd}/eslint.config.js" ]] && conventions+="ESLint, "
  [[ -f "${cwd}/.prettierrc" || -f "${cwd}/.prettierrc.json" ]] && conventions+="Prettier, "
  [[ -f "${cwd}/pyproject.toml" ]] && grep -q "ruff" "${cwd}/pyproject.toml" 2>/dev/null && conventions+="Ruff, "
  [[ -f "${cwd}/.shellcheckrc" ]] && conventions+="ShellCheck, "
  conventions="${conventions%, }"
  [[ -n "$conventions" ]] && ctx+="CONVENTIONS: ${conventions}"$'\n'

  # 2. Detect languages
  local langs=""
  [[ -f "${cwd}/package.json" ]]     && langs+="JS/TS, "
  [[ -f "${cwd}/pyproject.toml" || -f "${cwd}/requirements.txt" ]] && langs+="Python, "
  [[ -f "${cwd}/Cargo.toml" ]]       && langs+="Rust, "
  [[ -f "${cwd}/go.mod" ]]           && langs+="Go, "
  langs="${langs%, }"
  [[ -n "$langs" ]] && ctx+="LANGUAGES: ${langs}"$'\n'

  # 3. Find candidate files from task keywords (if task provided)
  if [[ -n "$task" ]] && command -v grep &>/dev/null; then
    local keywords
    # Extract likely filenames or identifiers from task
    keywords=$(printf '%s' "$task" | grep -oE '[a-zA-Z_][a-zA-Z0-9_.-]+\.(ts|js|py|rs|go|sh|tsx|jsx)' | head -8)
    if [[ -n "$keywords" ]]; then
      ctx+="CANDIDATE FILES:"$'\n'
      while IFS= read -r kw; do
        local found
        found=$(cd "$cwd" && find . -name "$kw" -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | head -3)
        [[ -n "$found" ]] && ctx+="${found}"$'\n'
      done <<< "$keywords"
    fi
  fi

  printf '%s' "$ctx"
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

  # No-op guard (F1): If no lines changed, score is 0.
  # This prevents false positives from non-discriminating fitness tests.
  if (( diff_lines == 0 )); then
    echo "0"
    return 0
  fi

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

# ══════════════════════════════════════════════════════════════════════════════
# Dynamic Buddy Registry (v3)
# ══════════════════════════════════════════════════════════════════════════════

# ── Registry directory ───────────────────────────────────────────────────────
# Returns paths to buddy definitions: builtin + user directories.
ai_buddies_registry_dir() {
  local plugin_root="${PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  local builtin_dir="${plugin_root}/buddies/builtin"
  local user_dir="${AI_BUDDIES_HOME}/buddies"
  echo "${builtin_dir}:${user_dir}"
}

# ── List all registered buddy IDs ────────────────────────────────────────────
ai_buddies_list_buddies() {
  local registry
  registry="$(ai_buddies_registry_dir)"
  IFS=':' read -ra dirs <<< "$registry"

  local seen=()
  for dir in "${dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    for f in "$dir"/*.json; do
      [[ -f "$f" ]] || continue
      local id
      id=$(basename "$f" .json)
      # Deduplicate (user overrides builtin)
      local dup=false
      for s in "${seen[@]+"${seen[@]}"}"; do
        [[ "$s" == "$id" ]] && { dup=true; break; }
      done
      [[ "$dup" == "true" ]] && continue
      seen+=("$id")
      echo "$id"
    done
  done
}

# ── Find buddy JSON file (user dir takes precedence) ────────────────────────
_ai_buddies_find_buddy_json() {
  local id="$1"
  local registry
  registry="$(ai_buddies_registry_dir)"
  IFS=':' read -ra dirs <<< "$registry"

  # User dir first (override), then builtin
  local user_dir="${dirs[1]:-}"
  local builtin_dir="${dirs[0]:-}"

  if [[ -n "$user_dir" && -f "${user_dir}/${id}.json" ]]; then
    echo "${user_dir}/${id}.json"
    return 0
  fi
  if [[ -n "$builtin_dir" && -f "${builtin_dir}/${id}.json" ]]; then
    echo "${builtin_dir}/${id}.json"
    return 0
  fi
  return 1
}

# ── Read a field from buddy JSON via jq ──────────────────────────────────────
# Usage: ai_buddies_buddy_config ID KEY [DEFAULT]
ai_buddies_buddy_config() {
  local id="$1"
  local key="$2"
  local default="${3:-}"

  local json_file
  json_file=$(_ai_buddies_find_buddy_json "$id" 2>/dev/null) || {
    echo "$default"
    return 0
  }

  if command -v jq &>/dev/null; then
    local val
    val=$(jq -r --arg k "$key" '.[$k] // empty' "$json_file" 2>/dev/null)
    if [[ -n "$val" && "$val" != "null" ]]; then
      echo "$val"
      return 0
    fi
  fi

  echo "$default"
}

# ── Generic binary finder ────────────────────────────────────────────────────
# Replaces find_codex, find_gemini, find_claude.
ai_buddies_find_buddy() {
  local id="$1"
  local binary
  binary=$(ai_buddies_buddy_config "$id" "binary" "$id")

  # 1. Check explicit config override (e.g. codex_path)
  local configured
  configured="$(ai_buddies_config "${id}_path" "")"
  if [[ -n "$configured" && -x "$configured" ]]; then
    echo "$configured"
    return 0
  fi

  # 2. Standard PATH lookup
  if command -v "$binary" &>/dev/null; then
    command -v "$binary"
    return 0
  fi

  # 3. Search paths from buddy JSON
  local json_file
  json_file=$(_ai_buddies_find_buddy_json "$id" 2>/dev/null) || return 1

  if command -v jq &>/dev/null; then
    local paths
    paths=$(jq -r '.search_paths[]? // empty' "$json_file" 2>/dev/null)
    while IFS= read -r pattern; do
      [[ -z "$pattern" ]] && continue
      # Expand ${HOME}
      pattern="${pattern//\$\{HOME\}/${HOME}}"
      # shellcheck disable=SC2086
      for bin in $pattern; do
        if [[ -x "$bin" ]]; then
          echo "$bin"
          return 0
        fi
      done
    done <<< "$paths"
  fi

  return 1
}

# ── Generic version query ────────────────────────────────────────────────────
ai_buddies_buddy_version() {
  local id="$1"
  local buddy_bin
  buddy_bin="$(ai_buddies_find_buddy "$id" 2>/dev/null)" || return 1

  local version_cmd
  version_cmd=$(ai_buddies_buddy_config "$id" "version_cmd" "--version")
  # version_cmd in JSON is an array but we only use first element
  if command -v jq &>/dev/null; then
    local json_file
    json_file=$(_ai_buddies_find_buddy_json "$id" 2>/dev/null) || true
    if [[ -n "$json_file" ]]; then
      version_cmd=$(jq -r '.version_cmd[0] // "--version"' "$json_file" 2>/dev/null)
    fi
  fi

  # shellcheck disable=SC2086
  "$buddy_bin" ${version_cmd:---version} 2>/dev/null | head -1
}

# ── Generic model query ──────────────────────────────────────────────────────
ai_buddies_buddy_model() {
  local id="$1"
  local config_key
  config_key=$(ai_buddies_buddy_config "$id" "model_config_key" "${id}_model")
  ai_buddies_config "$config_key" ""
}

# ── Available buddies (installed only) ───────────────────────────────────────
# Returns CSV of installed buddy IDs. Replaces hardcoded arrays.
ai_buddies_available_buddies() {
  local available=()
  while IFS= read -r id; do
    if ai_buddies_find_buddy "$id" &>/dev/null; then
      available+=("$id")
    fi
  done < <(ai_buddies_list_buddies)

  local IFS=','
  echo "${available[*]}"
}

# ── Check mode support ──────────────────────────────────────────────────────
ai_buddies_buddy_supports_mode() {
  local id="$1"
  local mode="$2"

  local json_file
  json_file=$(_ai_buddies_find_buddy_json "$id" 2>/dev/null) || return 1

  if command -v jq &>/dev/null; then
    local has_mode
    has_mode=$(jq -r --arg m "$mode" '.modes // [] | index($m) // empty' "$json_file" 2>/dev/null)
    [[ -n "$has_mode" ]] && return 0
  fi

  return 1
}

# ── Generic dispatch ─────────────────────────────────────────────────────────
# Replaces case statements in forge-run.sh, forge-synthesize.sh, forge-spectest.sh.
# Usage: ai_buddies_dispatch_buddy ID WT PROMPT TIMEOUT [DIR] [ROOT]
ai_buddies_dispatch_buddy() {
  local id="$1"
  local wt="$2"
  local prompt="$3"
  local timeout="$4"
  local output_dir="${5:-$(dirname "$wt")}"
  local plugin_root="${6:-${PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}}"

  local adapter
  adapter=$(ai_buddies_buddy_config "$id" "adapter_script" "buddy-run.sh")
  local is_builtin
  is_builtin=$(ai_buddies_buddy_config "$id" "builtin" "false")

  if [[ "$is_builtin" == "true" ]]; then
    # Builtin buddies use their dedicated adapter scripts
    bash "${plugin_root}/scripts/${adapter}" \
      --prompt "$prompt" \
      --cwd "$wt" \
      --mode exec \
      --timeout "$timeout"
  else
    # Non-builtin buddies use the generic buddy-run.sh
    bash "${plugin_root}/scripts/buddy-run.sh" \
      --id "$id" \
      --prompt "$prompt" \
      --cwd "$wt" \
      --mode exec \
      --timeout "$timeout"
  fi
}

# ── Backward-compatible wrappers (thin) ──────────────────────────────────────
# These delegate to the generic registry functions so old code keeps working.
ai_buddies_find_claude()    { ai_buddies_find_buddy "claude"; }
ai_buddies_claude_version() { ai_buddies_buddy_version "claude"; }
ai_buddies_claude_model()   { ai_buddies_buddy_model "claude"; }
ai_buddies_find_codex()     { ai_buddies_find_buddy "codex"; }
ai_buddies_codex_version()  { ai_buddies_buddy_version "codex"; }
ai_buddies_codex_model()    { ai_buddies_buddy_model "codex"; }
ai_buddies_find_gemini()    { ai_buddies_find_buddy "gemini"; }
ai_buddies_gemini_version() { ai_buddies_buddy_version "gemini"; }
ai_buddies_gemini_model()   { ai_buddies_buddy_model "gemini"; }

# ══════════════════════════════════════════════════════════════════════════════
# Tribunal helpers (v3)
# ══════════════════════════════════════════════════════════════════════════════

# ── Tribunal config readers ──────────────────────────────────────────────────
ai_buddies_tribunal_rounds() {
  ai_buddies_config "tribunal_rounds" "2"
}

ai_buddies_tribunal_max_buddies() {
  ai_buddies_config "tribunal_max_buddies" "3"
}

# ── Build tribunal prompt ────────────────────────────────────────────────────
# Usage: ai_buddies_build_tribunal_prompt "question" "position" ROUND TOTAL [prev_args] [mode]
ai_buddies_build_tribunal_prompt() {
  local question="$1"
  local position="$2"
  local round="$3"
  local total="$4"
  local prev_args="${5:-}"
  local mode="${6:-adversarial}"

  local prompt=""

  case "$mode" in
    socratic)
      _ai_buddies_build_socratic_prompt "$question" "$position" "$round" "$total" "$prev_args"
      return ;;
    steelman)
      _ai_buddies_build_steelman_prompt "$question" "$position" "$round" "$total" "$prev_args"
      return ;;
    red-team)
      _ai_buddies_build_redteam_prompt "$question" "$position" "$round" "$total" "$prev_args"
      return ;;
    synthesis)
      _ai_buddies_build_synthesis_prompt "$question" "$position" "$round" "$total" "$prev_args"
      return ;;
    postmortem)
      _ai_buddies_build_postmortem_prompt "$question" "$position" "$round" "$total" "$prev_args"
      return ;;
    *)
      prompt="ADVERSARIAL DEBATE — Round ${round}/${total}"
      ;;
  esac

  prompt+=$'\n\n'"QUESTION: ${question}"
  prompt+=$'\n\n'"YOUR POSITION: ${position}"
  prompt+=$'\n\n'"EVIDENCE PROTOCOL:"
  prompt+=$'\n'"Every claim MUST include a citation: {\"claim\":\"...\",\"file\":\"path\",\"lines\":\"N-M\",\"evidence\":\"quoted code\",\"severity\":1-5}"
  prompt+=$'\n'"Claims without file:line evidence score ZERO."
  prompt+=$'\n\n'"RULES:"
  prompt+=$'\n'"- Argue your assigned position with real code evidence."
  prompt+=$'\n'"- Reference specific files and line numbers."
  prompt+=$'\n'"- If you genuinely cannot find evidence for your position, say so."
  prompt+=$'\n'"- Respond with a JSON array of evidence objects. No other text."

  if [[ -n "$prev_args" ]]; then
    prompt+=$'\n\n'"PREVIOUS ROUND ARGUMENTS:"$'\n'"${prev_args}"
    prompt+=$'\n\n'"ADDRESS the opposing arguments above. Rebut with evidence or concede specific points."
  fi

  printf '%s' "$prompt"
}

# ── Build Socratic tribunal prompt ──────────────────────────────────────────
# Internal helper for socratic mode prompts.
_ai_buddies_build_socratic_prompt() {
  local question="$1"
  local position="$2"
  local round="$3"
  local total="$4"
  local prev_args="${5:-}"

  local prompt="SOCRATIC INQUIRY — Round ${round}/${total}"
  prompt+=$'\n\n'"TOPIC: ${question}"
  prompt+=$'\n'"ROLE: ${position}"

  if [[ "$round" -eq 1 ]]; then
    prompt+=$'\n\n'"TASK: Generate 3-5 probing questions that would materially change the engineering decision if answered."
    prompt+=$'\n'"Allowed type values: ASSUMPTION, CLARIFYING, EVIDENCE, VIEWPOINT, CONSEQUENCE, META."
    prompt+=$'\n'"Each question must target one concrete gap, ambiguity, hidden assumption, or consequence visible in the codebase."
    prompt+=$'\n\n'"Return a JSON array only. No markdown, no code fences, no prose."
    prompt+=$'\n'"Schema:"
    prompt+=$'\n'"["
    prompt+=$'\n'"  {"
    prompt+=$'\n'"    \"question_id\": \"Q1\","
    prompt+=$'\n'"    \"type\": \"ASSUMPTION\","
    prompt+=$'\n'"    \"question\": \"What happens when the cache is cold on deployment?\","
    prompt+=$'\n'"    \"file\": \"src/cache/warmup.ts\","
    prompt+=$'\n'"    \"lines\": \"14-28\","
    prompt+=$'\n'"    \"evidence\": \"// No warmup logic exists\","
    prompt+=$'\n'"    \"why_it_matters\": \"The current proposal assumes cache availability during first-request traffic.\""
    prompt+=$'\n'"  }"
    prompt+=$'\n'"]"
    prompt+=$'\n\n'"Rules:"
    prompt+=$'\n'"- Do not answer the topic."
    prompt+=$'\n'"- Do not ask generic due-diligence questions."
    prompt+=$'\n'"- If you cannot cite code for a question, omit that question."
  else
    prompt+=$'\n\n'"TASK: Answer the questions below with code evidence."
    prompt+=$'\n'"Input contains questions authored by other interrogators."
    prompt+=$'\n\n'"QUESTIONS:"
    prompt+=$'\n'"${prev_args}"
    prompt+=$'\n\n'"Return one JSON object per input question. No markdown, no code fences, no prose."
    prompt+=$'\n'"Schema:"
    prompt+=$'\n'"["
    prompt+=$'\n'"  {"
    prompt+=$'\n'"    \"question_id\": \"Q1\","
    prompt+=$'\n'"    \"original_question\": \"What happens when cache is cold?\","
    prompt+=$'\n'"    \"answer_status\": \"ANSWERED\","
    prompt+=$'\n'"    \"answer\": \"No warmup logic exists, so the first request falls through to the DB path.\","
    prompt+=$'\n'"    \"file\": \"src/cache/client.ts\","
    prompt+=$'\n'"    \"lines\": \"45-52\","
    prompt+=$'\n'"    \"evidence\": \"const get = async (key) => { ... }\","
    prompt+=$'\n'"    \"deeper_question\": \"What is the p99 latency of the DB fallback path under load?\","
    prompt+=$'\n'"    \"confidence\": \"HIGH\""
    prompt+=$'\n'"  }"
    prompt+=$'\n'"]"
    prompt+=$'\n\n'"Rules:"
    prompt+=$'\n'"- Use answer_status = ANSWERED or UNANSWERABLE."
    prompt+=$'\n'"- If UNANSWERABLE, set file, lines, and evidence to null and explain what evidence is missing."
    prompt+=$'\n'"- deeper_question may be null if no deeper question is justified."
  fi

  printf '%s' "$prompt"
}

# ── Build Steelman tribunal prompt ──────────────────────────────────────────
_ai_buddies_build_steelman_prompt() {
  local question="$1"
  local position="$2"
  local round="$3"
  local total="$4"
  local prev_args="${5:-}"

  local prompt="STEELMAN DEBATE — Round ${round}/${total}"
  prompt+=$'\n\n'"QUESTION: ${question}"
  prompt+=$'\n'"ROLE: ${position}"

  if [[ "$round" -eq 1 || -z "$prev_args" ]]; then
    prompt+=$'\n\n'"TASK: Build the STRONGEST possible case for your assigned position, even if you personally disagree."
    prompt+=$'\n'"A steelman is the opposite of a strawman — you present the most charitable, rigorous, well-evidenced version of the argument."
    prompt+=$'\n\n'"Return a JSON array only. No markdown, no code fences, no prose."
    prompt+=$'\n'"Schema:"
    prompt+=$'\n'"["
    prompt+=$'\n'"  {"
    prompt+=$'\n'"    \"claim\": \"The strongest argument for this position\","
    prompt+=$'\n'"    \"file\": \"path/to/file.ts\","
    prompt+=$'\n'"    \"lines\": \"N-M\","
    prompt+=$'\n'"    \"evidence\": \"quoted code that supports this claim\","
    prompt+=$'\n'"    \"severity\": 1-5,"
    prompt+=$'\n'"    \"why_strongest\": \"Why this is the best version of this argument, not a weak strawman\","
    prompt+=$'\n'"    \"concession\": \"What the opposing side is legitimately right about that this claim does not address\""
    prompt+=$'\n'"  }"
    prompt+=$'\n'"]"
    prompt+=$'\n\n'"Rules:"
    prompt+=$'\n'"- Find genuine merit, not obvious points."
    prompt+=$'\n'"- Every claim MUST include a concession — what the other side is right about. This is what makes it a steelman, not a debate."
    prompt+=$'\n'"- If you cannot find strong evidence, return an empty array []."
    prompt+=$'\n'"- Quality over quantity — 2 strong claims beat 5 weak ones."
  else
    prompt+=$'\n\n'"PREVIOUS ROUND STEELMAN ARGUMENTS:"
    prompt+=$'\n'"${prev_args}"
    prompt+=$'\n\n'"TASK: Challenge the other steelman. Find where even the strongest version has weaknesses."
    prompt+=$'\n'"Same JSON schema as before. Reference specific claims from the previous round."
  fi

  printf '%s' "$prompt"
}

# ── Build Red-team tribunal prompt ─────────────────────────────────────────
_ai_buddies_build_redteam_prompt() {
  local question="$1"
  local position="$2"
  local round="$3"
  local total="$4"
  local prev_args="${5:-}"

  local prompt="RED-TEAM ASSESSMENT — Round ${round}/${total}"
  prompt+=$'\n\n'"TARGET: ${question}"
  prompt+=$'\n'"ROLE: ${position}"

  if [[ "$round" -eq 1 ]]; then
    prompt+=$'\n\n'"TASK: Attack this proposal from your assigned angle. Find every vulnerability, weakness, edge case, and failure mode."
    prompt+=$'\n'"Be thorough and adversarial. You are a hostile auditor."
    prompt+=$'\n\n'"Return a JSON array only. No markdown, no code fences, no prose."
    prompt+=$'\n'"Schema:"
    prompt+=$'\n'"["
    prompt+=$'\n'"  {"
    prompt+=$'\n'"    \"vulnerability\": \"Description of the weakness\","
    prompt+=$'\n'"    \"attack_type\": \"reliability|security|performance|maintainability\","
    prompt+=$'\n'"    \"file\": \"path/to/file.ts\","
    prompt+=$'\n'"    \"lines\": \"N-M\","
    prompt+=$'\n'"    \"evidence\": \"quoted code showing the weakness\","
    prompt+=$'\n'"    \"severity\": 1-5,"
    prompt+=$'\n'"    \"exploit_scenario\": \"How this could be exploited or cause failure\""
    prompt+=$'\n'"  }"
    prompt+=$'\n'"]"
    prompt+=$'\n\n'"Rules:"
    prompt+=$'\n'"- Do not defend the proposal. Only attack."
    prompt+=$'\n'"- Every finding must have code evidence."
    prompt+=$'\n'"- Focus on your assigned attack vector."
  else
    prompt+=$'\n\n'"OTHER ATTACKER'S FINDINGS:"
    prompt+=$'\n'"${prev_args}"
    prompt+=$'\n\n'"TASK: Find ADDITIONAL vulnerabilities the other attacker missed. Chain attacks: combine findings for compound vulnerabilities."
    prompt+=$'\n'"Same JSON schema. Do not repeat findings already listed above."
  fi

  printf '%s' "$prompt"
}

# ── Build Synthesis tribunal prompt ────────────────────────────────────────
_ai_buddies_build_synthesis_prompt() {
  local question="$1"
  local position="$2"
  local round="$3"
  local total="$4"
  local prev_args="${5:-}"

  local prompt="SYNTHESIS SESSION — Round ${round}/${total}"
  prompt+=$'\n\n'"PROBLEM: ${question}"
  prompt+=$'\n'"ROLE: ${position}"

  if [[ "$round" -eq 1 ]]; then
    prompt+=$'\n\n'"TASK: Propose a complete solution. Be specific — files to change, architecture decisions, trade-offs."
    prompt+=$'\n\n'"Return a JSON object only. No markdown, no code fences, no prose."
    prompt+=$'\n'"Schema:"
    prompt+=$'\n'"{"
    prompt+=$'\n'"  \"approach_name\": \"Short name for this approach\","
    prompt+=$'\n'"  \"summary\": \"2-3 sentence description\","
    prompt+=$'\n'"  \"changes\": ["
    prompt+=$'\n'"    {\"file\": \"path\", \"lines\": \"N-M\", \"change\": \"what to do and why\"}"
    prompt+=$'\n'"  ],"
    prompt+=$'\n'"  \"trade_offs\": \"What this approach sacrifices\","
    prompt+=$'\n'"  \"complexity\": \"LOW|MEDIUM|HIGH\","
    prompt+=$'\n'"  \"strengths\": \"What this approach does best\""
    prompt+=$'\n'"}"
    prompt+=$'\n\n'"Rules:"
    prompt+=$'\n'"- Be concrete. Abstract proposals score zero."
    prompt+=$'\n'"- Reference actual code, not hypothetical files."
    prompt+=$'\n'"- State trade-offs honestly."
  else
    prompt+=$'\n\n'"OTHER PROPOSAL:"
    prompt+=$'\n'"${prev_args}"
    prompt+=$'\n\n'"TASK: Create a HYBRID solution. Take the best parts of both proposals. Explain what you take from each and why."
    prompt+=$'\n\n'"Schema:"
    prompt+=$'\n'"{"
    prompt+=$'\n'"  \"hybrid_name\": \"Short name\","
    prompt+=$'\n'"  \"take_from_own\": \"What to keep from your proposal and why\","
    prompt+=$'\n'"  \"take_from_other\": \"What to take from the other proposal and why\","
    prompt+=$'\n'"  \"changes\": [{\"file\": \"path\", \"lines\": \"N-M\", \"change\": \"what to do\"}],"
    prompt+=$'\n'"  \"trade_offs\": \"What the hybrid sacrifices\","
    prompt+=$'\n'"  \"why_better\": \"Why this hybrid beats either proposal alone\""
    prompt+=$'\n'"}"
  fi

  printf '%s' "$prompt"
}

# ── Build Postmortem tribunal prompt ───────────────────────────────────────
_ai_buddies_build_postmortem_prompt() {
  local question="$1"
  local position="$2"
  local round="$3"
  local total="$4"
  local prev_args="${5:-}"

  local prompt="POSTMORTEM INVESTIGATION — Round ${round}/${total}"
  prompt+=$'\n\n'"INCIDENT: ${question}"
  prompt+=$'\n'"ROLE: ${position}"

  if [[ "$round" -eq 1 ]]; then
    prompt+=$'\n\n'"TASK: Investigate this failure from your assigned angle. Build a timeline of what went wrong."
    prompt+=$'\n\n'"Return a JSON array only. No markdown, no code fences, no prose."
    prompt+=$'\n'"Schema:"
    prompt+=$'\n'"["
    prompt+=$'\n'"  {"
    prompt+=$'\n'"    \"finding_id\": \"F1\","
    prompt+=$'\n'"    \"category\": \"execution|config|dependency|external\","
    prompt+=$'\n'"    \"finding\": \"What went wrong\","
    prompt+=$'\n'"    \"file\": \"path/to/file.ts\","
    prompt+=$'\n'"    \"lines\": \"N-M\","
    prompt+=$'\n'"    \"evidence\": \"quoted code or config showing the issue\","
    prompt+=$'\n'"    \"timeline_order\": 1,"
    prompt+=$'\n'"    \"is_root_cause\": false,"
    prompt+=$'\n'"    \"is_contributing_factor\": true"
    prompt+=$'\n'"  }"
    prompt+=$'\n'"]"
    prompt+=$'\n\n'"Rules:"
    prompt+=$'\n'"- Stay in your investigation lane (execution vs environment)."
    prompt+=$'\n'"- Build a chronological timeline."
    prompt+=$'\n'"- Mark exactly one finding as potential root cause if you find it."
  else
    prompt+=$'\n\n'"OTHER INVESTIGATOR'S FINDINGS:"
    prompt+=$'\n'"${prev_args}"
    prompt+=$'\n\n'"TASK: Cross-reference with your findings. Where do the timelines connect? Identify the root cause by combining both perspectives."
    prompt+=$'\n'"Same JSON schema, with one addition: include a \"cross_references\" field (array of finding_ids from the other investigator that relate to this finding)."
  fi

  printf '%s' "$prompt"
}

# ══════════════════════════════════════════════════════════════════════════════
# ELO helpers (v3)
# ══════════════════════════════════════════════════════════════════════════════

ai_buddies_elo_enabled() {
  ai_buddies_config "elo_enabled" "true"
}

ai_buddies_elo_k_factor() {
  ai_buddies_config "elo_k_factor" "32"
}

ai_buddies_elo_file() {
  echo "${AI_BUDDIES_HOME}/elo.json"
}

# ── Detect task class from description ───────────────────────────────────────
# Keyword-based classification: algorithm, refactor, bugfix, feature, test, docs, other
ai_buddies_detect_task_class() {
  local desc="$1"
  local lower
  lower=$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]')

  case "$lower" in
    *algorithm*|*sort*|*search*|*scoring*|*math*|*compute*|*calculate*)
      echo "algorithm" ;;
    *refactor*|*rename*|*extract*|*simplify*|*reorganize*|*clean*)
      echo "refactor" ;;
    *fix*|*bug*|*error*|*crash*|*broken*|*regression*)
      echo "bugfix" ;;
    *test*|*spec*|*coverage*|*assert*)
      echo "test" ;;
    *doc*|*readme*|*comment*|*changelog*)
      echo "docs" ;;
    *add*|*implement*|*create*|*build*|*feature*|*new*)
      echo "feature" ;;
    *)
      echo "other" ;;
  esac
}
