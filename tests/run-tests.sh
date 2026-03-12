#!/usr/bin/env bash
# claudes-ai-buddies — test suite
# Usage: bash tests/run-tests.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0
TOTAL=0

# ── Test helpers ─────────────────────────────────────────────────────────────
test_start() {
  TOTAL=$((TOTAL + 1))
  printf "  [%02d] %-55s " "$TOTAL" "$1"
}

test_pass() {
  PASS=$((PASS + 1))
  echo "PASS"
}

test_fail() {
  FAIL=$((FAIL + 1))
  echo "FAIL: $1"
}

assert_eq() {
  if [[ "$1" == "$2" ]]; then
    test_pass
  else
    test_fail "expected '$2', got '$1'"
  fi
}

assert_contains() {
  if [[ "$1" == *"$2"* ]]; then
    test_pass
  else
    test_fail "expected to contain '$2', got '$1'"
  fi
}

assert_file_exists() {
  if [[ -f "$1" ]]; then
    test_pass
  else
    test_fail "file not found: $1"
  fi
}

assert_exit_code() {
  if [[ "$1" -eq "$2" ]]; then
    test_pass
  else
    test_fail "expected exit code $2, got $1"
  fi
}

# ── Setup mock CLIs ──────────────────────────────────────────────────────────
MOCK_DIR=$(mktemp -d)

# Mock codex
MOCK_CODEX="${MOCK_DIR}/codex"
cat > "$MOCK_CODEX" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  --version)
    echo "codex-cli 0.101.0 (mock)"
    ;;
  exec)
    OUTPUT_FILE=""
    PROMPT=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -o)         OUTPUT_FILE="$2"; shift 2 ;;
        --ephemeral|--full-auto|--suggest) shift ;;
        --model)    shift 2 ;;
        *)          PROMPT="$1"; shift ;;
      esac
    done
    if [[ -n "$OUTPUT_FILE" ]]; then
      echo "Mock Codex response to: ${PROMPT}" > "$OUTPUT_FILE"
    fi
    ;;
esac
MOCK
chmod +x "$MOCK_CODEX"

# Mock gemini
MOCK_GEMINI="${MOCK_DIR}/gemini"
cat > "$MOCK_GEMINI" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  --version)
    echo "0.32.1 (mock)"
    ;;
  -p)
    # Non-interactive mode: output to stdout
    echo "Mock Gemini response to: $2"
    ;;
esac
MOCK
chmod +x "$MOCK_GEMINI"

# Override PATH to use mocks
export PATH="${MOCK_DIR}:${PATH}"

# Setup temp config
TEST_HOME=$(mktemp -d)
export HOME="$TEST_HOME"
export AI_BUDDIES_HOME="${TEST_HOME}/.claudes-ai-buddies"
export CLAUDE_SESSION_ID="test-session-$$"

# ── Source lib ───────────────────────────────────────────────────────────────
source "${PLUGIN_ROOT}/hooks/lib.sh"

echo ""
echo "=== claudes-ai-buddies test suite ==="
echo ""

# ── lib.sh — shared tests ───────────────────────────────────────────────────
echo "--- lib.sh (shared) ---"

test_start "ai_buddies_config returns default for missing key"
result=$(ai_buddies_config "nonexistent" "mydefault")
assert_eq "$result" "mydefault"

test_start "ai_buddies_config_set writes config"
ai_buddies_config_set "test_key" "test_value"
result=$(ai_buddies_config "test_key" "")
assert_eq "$result" "test_value"

test_start "ai_buddies_timeout returns default 120"
result=$(ai_buddies_timeout)
assert_eq "$result" "120"

test_start "ai_buddies_sandbox returns default full-auto"
result=$(ai_buddies_sandbox)
assert_eq "$result" "full-auto"

test_start "ai_buddies_session_dir creates directory"
result=$(ai_buddies_session_dir)
if [[ -d "$result" ]]; then
  test_pass
else
  test_fail "directory not found: $result"
fi

test_start "ai_buddies_escape_json handles quotes"
result=$(ai_buddies_escape_json 'hello "world"')
if [[ "$result" == *'\"'* ]] || [[ "$result" == *'\\\"'* ]]; then
  test_pass
else
  test_fail "expected escaped quotes in: $result"
fi

test_start "ai_buddies_run_with_timeout succeeds within limit"
result=$(ai_buddies_run_with_timeout 5 echo "hello" 2>&1)
assert_eq "$result" "hello"

test_start "ai_buddies_run_with_timeout returns 124 on timeout"
ec=0
ai_buddies_run_with_timeout 1 sleep 10 2>/dev/null || ec=$?
assert_eq "$ec" "124"

test_start "ai_buddies_build_review_prompt includes diff header"
REVIEW_TEST_REPO=$(mktemp -d)
cd "$REVIEW_TEST_REPO"
git init -q
echo "init" > f.txt && git add f.txt && git commit -q -m "init"
echo "changed" > f.txt
result=$(ai_buddies_build_review_prompt "check this" "$REVIEW_TEST_REPO" "uncommitted")
cd "$PLUGIN_ROOT"
rm -rf "$REVIEW_TEST_REPO"
assert_contains "$result" "code review"

# ── lib.sh — codex tests ────────────────────────────────────────────────────
echo ""
echo "--- lib.sh (codex) ---"

test_start "ai_buddies_find_codex finds mock"
result=$(ai_buddies_find_codex)
assert_contains "$result" "codex"

test_start "ai_buddies_codex_version returns version"
result=$(ai_buddies_codex_version)
assert_contains "$result" "codex-cli"

test_start "ai_buddies_codex_model returns empty when no override"
result=$(ai_buddies_codex_model)
assert_eq "$result" ""

test_start "ai_buddies_codex_model reads from config"
ai_buddies_config_set "codex_model" "gpt-custom"
unset _AI_BUDDIES_DEBUG_CACHED
result=$(ai_buddies_codex_model)
assert_eq "$result" "gpt-custom"
ai_buddies_config_set "codex_model" ""

# ── lib.sh — gemini tests ───────────────────────────────────────────────────
echo ""
echo "--- lib.sh (gemini) ---"

test_start "ai_buddies_find_gemini finds mock"
result=$(ai_buddies_find_gemini)
assert_contains "$result" "gemini"

test_start "ai_buddies_gemini_version returns version"
result=$(ai_buddies_gemini_version)
assert_contains "$result" "0.32.1"

test_start "ai_buddies_gemini_model returns empty when no override"
result=$(ai_buddies_gemini_model)
assert_eq "$result" ""

test_start "ai_buddies_gemini_model reads from config"
ai_buddies_config_set "gemini_model" "gemini-custom"
result=$(ai_buddies_gemini_model)
assert_eq "$result" "gemini-custom"
ai_buddies_config_set "gemini_model" ""

# ── session-start.sh tests ───────────────────────────────────────────────────
echo ""
echo "--- session-start.sh ---"

test_start "session-start.sh runs without error"
output=$(bash "${PLUGIN_ROOT}/hooks/session-start.sh" 2>&1)
ec=$?
assert_exit_code "$ec" 0

test_start "session-start.sh shows Codex"
assert_contains "$output" "Codex"

test_start "session-start.sh shows Gemini"
assert_contains "$output" "Gemini"

test_start "session-start.sh mentions /codex skill"
assert_contains "$output" "/codex"

test_start "session-start.sh mentions /gemini skill"
assert_contains "$output" "/gemini"

test_start "session-start.sh mentions /brainstorm skill"
assert_contains "$output" "/brainstorm"

test_start "session-start.sh mentions /forge skill"
assert_contains "$output" "/forge"

# ── codex-run.sh tests ──────────────────────────────────────────────────────
echo ""
echo "--- codex-run.sh ---"

test_start "codex-run.sh requires --prompt"
output=$(bash "${PLUGIN_ROOT}/scripts/codex-run.sh" 2>&1 || true)
assert_contains "$output" "ERROR"

test_start "codex-run.sh exec mode produces output file"
output=$(bash "${PLUGIN_ROOT}/scripts/codex-run.sh" --prompt "test query" --mode exec 2>&1)
trimmed=$(echo "$output" | tail -1)
if [[ -f "$trimmed" ]]; then
  content=$(cat "$trimmed")
  test_pass
else
  test_fail "output file not found: $trimmed"
  content=""
fi

test_start "codex exec output contains response"
assert_contains "${content:-}" "Mock Codex response"

test_start "codex-run.sh review mode produces output"
REVIEW_REPO=$(mktemp -d)
cd "$REVIEW_REPO"
git init -q
echo "initial" > file.txt
git add file.txt
git commit -q -m "init"
echo "changed" > file.txt
output=$(bash "${PLUGIN_ROOT}/scripts/codex-run.sh" \
  --prompt "review this" \
  --cwd "$REVIEW_REPO" \
  --mode review \
  --review-target uncommitted 2>&1)
trimmed=$(echo "$output" | tail -1)
if [[ -f "$trimmed" ]]; then
  content=$(cat "$trimmed")
  assert_contains "$content" "Mock Codex response"
else
  test_fail "review output file not found"
fi
cd "$PLUGIN_ROOT"
rm -rf "$REVIEW_REPO"

# ── gemini-run.sh tests ─────────────────────────────────────────────────────
echo ""
echo "--- gemini-run.sh ---"

test_start "gemini-run.sh requires --prompt"
output=$(bash "${PLUGIN_ROOT}/scripts/gemini-run.sh" 2>&1 || true)
assert_contains "$output" "ERROR"

test_start "gemini-run.sh exec mode produces output file"
output=$(bash "${PLUGIN_ROOT}/scripts/gemini-run.sh" --prompt "test query" --mode exec 2>&1)
trimmed=$(echo "$output" | tail -1)
if [[ -f "$trimmed" ]]; then
  content=$(cat "$trimmed")
  test_pass
else
  test_fail "output file not found: $trimmed"
  content=""
fi

test_start "gemini exec output contains response"
assert_contains "${content:-}" "Mock Gemini response"

test_start "gemini-run.sh review mode produces output"
REVIEW_REPO=$(mktemp -d)
cd "$REVIEW_REPO"
git init -q
echo "initial" > file.txt
git add file.txt
git commit -q -m "init"
echo "changed" > file.txt
output=$(bash "${PLUGIN_ROOT}/scripts/gemini-run.sh" \
  --prompt "review this" \
  --cwd "$REVIEW_REPO" \
  --mode review \
  --review-target uncommitted 2>&1)
trimmed=$(echo "$output" | tail -1)
if [[ -f "$trimmed" ]]; then
  content=$(cat "$trimmed")
  assert_contains "$content" "Mock Gemini response"
else
  test_fail "review output file not found"
fi
cd "$PLUGIN_ROOT"
rm -rf "$REVIEW_REPO"

# ── File structure tests ─────────────────────────────────────────────────────
echo ""
echo "--- file structure ---"

test_start "plugin.json exists"
assert_file_exists "${PLUGIN_ROOT}/.claude-plugin/plugin.json"

test_start "marketplace.json exists"
assert_file_exists "${PLUGIN_ROOT}/.claude-plugin/marketplace.json"

test_start "hooks.json exists"
assert_file_exists "${PLUGIN_ROOT}/hooks/hooks.json"

test_start "codex SKILL.md exists"
assert_file_exists "${PLUGIN_ROOT}/skills/codex/SKILL.md"

test_start "codex-review SKILL.md exists"
assert_file_exists "${PLUGIN_ROOT}/skills/codex-review/SKILL.md"

test_start "gemini SKILL.md exists"
assert_file_exists "${PLUGIN_ROOT}/skills/gemini/SKILL.md"

test_start "gemini-review SKILL.md exists"
assert_file_exists "${PLUGIN_ROOT}/skills/gemini-review/SKILL.md"

test_start "brainstorm SKILL.md exists"
assert_file_exists "${PLUGIN_ROOT}/skills/brainstorm/SKILL.md"

test_start "buddy-help.md exists"
assert_file_exists "${PLUGIN_ROOT}/commands/buddy-help.md"

test_start "codex-run.sh exists"
assert_file_exists "${PLUGIN_ROOT}/scripts/codex-run.sh"

test_start "gemini-run.sh exists"
assert_file_exists "${PLUGIN_ROOT}/scripts/gemini-run.sh"

test_start "forge SKILL.md exists"
assert_file_exists "${PLUGIN_ROOT}/skills/forge/SKILL.md"

test_start "forge-fitness.sh exists"
assert_file_exists "${PLUGIN_ROOT}/scripts/forge-fitness.sh"

test_start "forge-fitness.sh is executable"
if [[ -x "${PLUGIN_ROOT}/scripts/forge-fitness.sh" ]]; then
  test_pass
else
  test_fail "forge-fitness.sh is not executable"
fi

test_start "plugin.json is valid JSON"
if jq . "${PLUGIN_ROOT}/.claude-plugin/plugin.json" &>/dev/null; then
  test_pass
else
  test_fail "invalid JSON"
fi

test_start "hooks.json is valid JSON"
if jq . "${PLUGIN_ROOT}/hooks/hooks.json" &>/dev/null; then
  test_pass
else
  test_fail "invalid JSON"
fi

# ── forge-fitness.sh tests ────────────────────────────────────────────────────
echo ""
echo "--- forge-fitness.sh ---"

test_start "forge-fitness.sh requires --dir"
output=$(bash "${PLUGIN_ROOT}/scripts/forge-fitness.sh" --cmd "true" 2>&1 || true)
assert_contains "$output" "ERROR"

test_start "forge-fitness.sh requires --cmd"
output=$(bash "${PLUGIN_ROOT}/scripts/forge-fitness.sh" --dir /tmp 2>&1 || true)
assert_contains "$output" "ERROR"

# Create a temp git repo for fitness tests
FITNESS_REPO=$(mktemp -d)
cd "$FITNESS_REPO"
git init -q
echo "hello" > file.txt
git add file.txt
git commit -q -m "init"

test_start "forge-fitness.sh passing test produces JSON"
echo "modified" > file.txt
result_path=$(bash "${PLUGIN_ROOT}/scripts/forge-fitness.sh" \
  --dir "$FITNESS_REPO" --cmd "true" --label test-pass 2>&1 | tail -1)
if [[ -f "$result_path" ]] && jq . "$result_path" &>/dev/null; then
  test_pass
else
  test_fail "no valid JSON at: $result_path"
fi

test_start "forge-fitness.sh passing test has pass=true"
pass_val=$(jq -r '.pass' "$result_path" 2>/dev/null)
assert_eq "$pass_val" "true"

test_start "forge-fitness.sh passing test has timed_out=false"
timeout_val=$(jq -r '.timed_out' "$result_path" 2>/dev/null)
assert_eq "$timeout_val" "false"

test_start "forge-fitness.sh failing test has pass=false"
git checkout -- file.txt 2>/dev/null || true
echo "changed again" > file.txt
result_path=$(bash "${PLUGIN_ROOT}/scripts/forge-fitness.sh" \
  --dir "$FITNESS_REPO" --cmd "exit 1" --label test-fail 2>&1 | tail -1)
pass_val=$(jq -r '.pass' "$result_path" 2>/dev/null)
assert_eq "$pass_val" "false"

test_start "forge-fitness.sh counts modified files"
git checkout -- file.txt 2>/dev/null || true
git reset HEAD 2>/dev/null || true
echo "tracked change" > file.txt
result_path=$(bash "${PLUGIN_ROOT}/scripts/forge-fitness.sh" \
  --dir "$FITNESS_REPO" --cmd "true" --label test-count 2>&1 | tail -1)
files_val=$(jq -r '.files_changed' "$result_path" 2>/dev/null)
if [[ "$files_val" -ge 1 ]]; then
  test_pass
else
  test_fail "expected >= 1 files_changed, got $files_val"
fi

test_start "forge-fitness.sh detects new (untracked) files"
git checkout -- file.txt 2>/dev/null || true
git reset HEAD 2>/dev/null || true
echo "brand new" > newfile.txt
result_path=$(bash "${PLUGIN_ROOT}/scripts/forge-fitness.sh" \
  --dir "$FITNESS_REPO" --cmd "true" --label test-new 2>&1 | tail -1)
files_val=$(jq -r '.files_changed' "$result_path" 2>/dev/null)
if [[ "$files_val" -ge 1 ]]; then
  test_pass
else
  test_fail "expected >= 1 for new file, got $files_val"
fi

test_start "forge-fitness.sh includes diff_lines in output"
diff_val=$(jq -r '.diff_lines' "$result_path" 2>/dev/null)
if [[ "$diff_val" -ge 1 ]]; then
  test_pass
else
  test_fail "expected >= 1 diff_lines, got $diff_val"
fi

test_start "forge-fitness.sh label is preserved in JSON"
label_val=$(jq -r '.label' "$result_path" 2>/dev/null)
assert_eq "$label_val" "test-new"

cd "$PLUGIN_ROOT"
rm -rf "$FITNESS_REPO"

# ── ai_buddies_project_context tests (F4) ────────────────────────────────────
echo ""
echo "--- ai_buddies_project_context (F4) ---"

# Node project
CTX_NODE_DIR=$(mktemp -d)
cd "$CTX_NODE_DIR"
git init -q
echo '{"scripts":{"test":"jest"}}' > package.json
echo "# My App" > README.md
echo "init" > f.txt && git add -A && git commit -q -m "init"

test_start "project_context detects Node/JS language"
result=$(ai_buddies_project_context "$CTX_NODE_DIR")
assert_contains "$result" "JavaScript"

test_start "project_context includes README content"
assert_contains "$result" "My App"

test_start "project_context includes recent commits"
assert_contains "$result" "init"

test_start "project_context detects test convention"
assert_contains "$result" "jest"

cd "$PLUGIN_ROOT"
rm -rf "$CTX_NODE_DIR"

# Python project
CTX_PY_DIR=$(mktemp -d)
cd "$CTX_PY_DIR"
git init -q
echo '[project]' > pyproject.toml
echo "init" > f.txt && git add -A && git commit -q -m "init"

test_start "project_context detects Python language"
result=$(ai_buddies_project_context "$CTX_PY_DIR")
assert_contains "$result" "Python"

cd "$PLUGIN_ROOT"
rm -rf "$CTX_PY_DIR"

# Empty project (no manifest)
CTX_EMPTY_DIR=$(mktemp -d)
cd "$CTX_EMPTY_DIR"
git init -q
echo "hi" > f.txt && git add -A && git commit -q -m "init"

test_start "project_context works with empty project"
result=$(ai_buddies_project_context "$CTX_EMPTY_DIR")
# Should not fail, may return commits only
assert_contains "$result" "init"

cd "$PLUGIN_ROOT"
rm -rf "$CTX_EMPTY_DIR"

# Disabled via config
test_start "project_context respects config=false"
ai_buddies_config_set "context_summary" "false"
result=$(ai_buddies_project_context "/tmp")
assert_eq "$result" ""
ai_buddies_config_set "context_summary" "true"

# ── ai_buddies_compute_forge_score tests (F5) ────────────────────────────────
echo ""
echo "--- ai_buddies_compute_forge_score (F5) ---"

test_start "score: fail always returns 0"
result=$(ai_buddies_compute_forge_score "false" 10 1 5 0 100)
assert_eq "$result" "0"

test_start "score: perfect pass returns high score"
result=$(ai_buddies_compute_forge_score "true" 0 1 0 0 100)
if [[ "$result" -ge 90 ]]; then
  test_pass
else
  test_fail "expected >= 90, got $result"
fi

test_start "score: more diff lines = lower score"
score_small=$(ai_buddies_compute_forge_score "true" 10 1 5 0 100)
score_big=$(ai_buddies_compute_forge_score "true" 200 1 5 0 100)
if [[ "$score_small" -gt "$score_big" ]]; then
  test_pass
else
  test_fail "expected small diff ($score_small) > big diff ($score_big)"
fi

test_start "score: lint warnings reduce score"
score_clean=$(ai_buddies_compute_forge_score "true" 10 1 5 0 100)
score_dirty=$(ai_buddies_compute_forge_score "true" 10 1 5 10 100)
if [[ "$score_clean" -gt "$score_dirty" ]]; then
  test_pass
else
  test_fail "expected clean ($score_clean) > dirty ($score_dirty)"
fi

test_start "score: low style reduces score"
score_styled=$(ai_buddies_compute_forge_score "true" 10 1 5 0 100)
score_ugly=$(ai_buddies_compute_forge_score "true" 10 1 5 0 20)
if [[ "$score_styled" -gt "$score_ugly" ]]; then
  test_pass
else
  test_fail "expected styled ($score_styled) > ugly ($score_ugly)"
fi

test_start "score: more files = lower score"
score_one=$(ai_buddies_compute_forge_score "true" 10 1 5 0 100)
score_many=$(ai_buddies_compute_forge_score "true" 10 8 5 0 100)
if [[ "$score_one" -gt "$score_many" ]]; then
  test_pass
else
  test_fail "expected 1 file ($score_one) > 8 files ($score_many)"
fi

# ── ai_buddies_forge_timeout tests ───────────────────────────────────────────
echo ""
echo "--- ai_buddies_forge_timeout ---"

test_start "forge_timeout returns default 600"
result=$(ai_buddies_forge_timeout)
assert_eq "$result" "600"

test_start "forge_timeout reads config override"
ai_buddies_config_set "forge_timeout" "300"
result=$(ai_buddies_forge_timeout)
assert_eq "$result" "300"
ai_buddies_config_set "forge_timeout" ""

# ── ai_buddies_build_forge_prompt tests ──────────────────────────────────────
echo ""
echo "--- ai_buddies_build_forge_prompt ---"

test_start "build_forge_prompt includes task"
result=$(ai_buddies_build_forge_prompt "fix the bug" "npm test" "")
assert_contains "$result" "fix the bug"

test_start "build_forge_prompt includes fitness"
assert_contains "$result" "npm test"

test_start "build_forge_prompt includes context when provided"
result=$(ai_buddies_build_forge_prompt "task" "cmd" "LANGUAGES: Python")
assert_contains "$result" "Python"

test_start "build_forge_prompt includes rules"
result=$(ai_buddies_build_forge_prompt "task" "cmd" "")
assert_contains "$result" "RULES"

# ── ai_buddies_build_spectest_prompt tests ───────────────────────────────────
echo ""
echo "--- ai_buddies_build_spectest_prompt ---"

test_start "build_spectest_prompt includes task"
result=$(ai_buddies_build_spectest_prompt "add validation" "")
assert_contains "$result" "add validation"

test_start "build_spectest_prompt includes RUN_CMD instruction"
assert_contains "$result" "RUN_CMD"

# ── ai_buddies_forge_status tests ────────────────────────────────────────────
echo ""
echo "--- ai_buddies_forge_status ---"

test_start "forge_status returns pending when no manifest"
STATUS_DIR=$(mktemp -d)
result=$(ai_buddies_forge_status "$STATUS_DIR")
assert_eq "$result" "pending"

test_start "forge_status parses manifest"
echo '{"winner":"codex","engines":["claude","codex","gemini"]}' > "${STATUS_DIR}/manifest.json"
result=$(ai_buddies_forge_status "$STATUS_DIR")
assert_contains "$result" "codex"
rm -rf "$STATUS_DIR"

# ── ai_buddies_forge_manifest tests ──────────────────────────────────────────
echo ""
echo "--- ai_buddies_forge_manifest ---"

test_start "forge_manifest writes valid JSON"
MANIFEST_DIR=$(mktemp -d)
MANIFEST_FILE="${MANIFEST_DIR}/manifest.json"
ai_buddies_forge_manifest "$MANIFEST_FILE" "test-123" "/tmp/forge" "fix bug" "claude,codex" '{"claude":{"pass":true,"score":80},"codex":{"pass":true,"score":90}}' '{"claude":"/tmp/c.diff","codex":"/tmp/x.diff"}' "codex"
if jq . "$MANIFEST_FILE" &>/dev/null; then
  test_pass
else
  test_fail "invalid JSON"
fi

test_start "forge_manifest has correct winner"
winner=$(jq -r '.winner' "$MANIFEST_FILE")
assert_eq "$winner" "codex"

test_start "forge_manifest has correct engines"
engine_count=$(jq '.engines | length' "$MANIFEST_FILE")
assert_eq "$engine_count" "2"

rm -rf "$MANIFEST_DIR"

# ── forge-score.sh tests ─────────────────────────────────────────────────────
echo ""
echo "--- forge-score.sh ---"

test_start "forge-score.sh requires --dir"
output=$(bash "${PLUGIN_ROOT}/scripts/forge-score.sh" 2>&1 || true)
assert_contains "$output" "ERROR"

SCORE_REPO=$(mktemp -d)
cd "$SCORE_REPO"
git init -q
echo "hello" > file.sh
git add -A && git commit -q -m "init"
echo "modified  " > file.sh  # trailing whitespace
git add -A

test_start "forge-score.sh outputs valid JSON"
output=$(bash "${PLUGIN_ROOT}/scripts/forge-score.sh" --dir "$SCORE_REPO" --label test-score 2>&1)
if echo "$output" | jq . &>/dev/null; then
  test_pass
else
  test_fail "invalid JSON: $output"
fi

test_start "forge-score.sh detects style issues"
style_score=$(echo "$output" | jq -r '.style_score' 2>/dev/null)
if [[ "$style_score" -lt 100 ]]; then
  test_pass
else
  test_fail "expected style_score < 100, got $style_score"
fi

test_start "forge-score.sh preserves label"
label=$(echo "$output" | jq -r '.label' 2>/dev/null)
assert_eq "$label" "test-score"

cd "$PLUGIN_ROOT"
rm -rf "$SCORE_REPO"

# ── forge-run.sh tests ──────────────────────────────────────────────────────
echo ""
echo "--- forge-run.sh ---"

test_start "forge-run.sh requires --forge-dir"
output=$(bash "${PLUGIN_ROOT}/scripts/forge-run.sh" --task "x" --fitness "true" 2>&1 || true)
assert_contains "$output" "ERROR"

test_start "forge-run.sh requires --task"
output=$(bash "${PLUGIN_ROOT}/scripts/forge-run.sh" --forge-dir /tmp --fitness "true" 2>&1 || true)
assert_contains "$output" "ERROR"

test_start "forge-run.sh requires --fitness"
output=$(bash "${PLUGIN_ROOT}/scripts/forge-run.sh" --forge-dir /tmp --task "x" 2>&1 || true)
assert_contains "$output" "ERROR"

# Full forge-run test with mock engines
RUN_REPO=$(mktemp -d)
cd "$RUN_REPO"
git init -q
echo "base" > code.txt
git add -A && git commit -q -m "init"
RUN_FORGE_DIR=$(mktemp -d)
git worktree add --detach "${RUN_FORGE_DIR}/wt-claude" HEAD 2>/dev/null
echo "claude-impl" > "${RUN_FORGE_DIR}/wt-claude/code.txt"

test_start "forge-run.sh produces manifest.json"
manifest_path=$(bash "${PLUGIN_ROOT}/scripts/forge-run.sh" \
  --forge-dir "$RUN_FORGE_DIR" \
  --task "test task" \
  --fitness "true" \
  --timeout 30 2>&1 | tail -1)
if [[ -f "$manifest_path" ]] && jq . "$manifest_path" &>/dev/null; then
  test_pass
else
  test_fail "no valid manifest at: $manifest_path"
fi

test_start "forge-run.sh manifest has winner"
if [[ -f "$manifest_path" ]]; then
  winner=$(jq -r '.winner' "$manifest_path" 2>/dev/null)
  if [[ -n "$winner" && "$winner" != "null" && "$winner" != "none" ]]; then
    test_pass
  else
    test_fail "winner is empty/null: $winner"
  fi
else
  test_fail "no manifest"
fi

test_start "forge-run.sh manifest has engines array"
if [[ -f "$manifest_path" ]]; then
  count=$(jq '.engines | length' "$manifest_path" 2>/dev/null)
  if [[ "$count" -ge 1 ]]; then
    test_pass
  else
    test_fail "expected >= 1 engine, got $count"
  fi
else
  test_fail "no manifest"
fi

# Clean up worktrees
git -C "$RUN_REPO" worktree remove "${RUN_FORGE_DIR}/wt-claude" --force 2>/dev/null || true
for e in codex gemini; do
  [[ -d "${RUN_FORGE_DIR}/wt-${e}" ]] && git -C "$RUN_REPO" worktree remove "${RUN_FORGE_DIR}/wt-${e}" --force 2>/dev/null || true
done
cd "$PLUGIN_ROOT"
rm -rf "$RUN_REPO" "$RUN_FORGE_DIR"

# ── forge-spectest.sh tests ──────────────────────────────────────────────────
echo ""
echo "--- forge-spectest.sh ---"

test_start "forge-spectest.sh requires --task"
output=$(bash "${PLUGIN_ROOT}/scripts/forge-spectest.sh" 2>&1 || true)
assert_contains "$output" "ERROR"

SPEC_REPO=$(mktemp -d)
cd "$SPEC_REPO"
git init -q
echo "base" > code.txt
git add -A && git commit -q -m "init"

test_start "forge-spectest.sh produces proposals file"
result_path=$(bash "${PLUGIN_ROOT}/scripts/forge-spectest.sh" \
  --task "add validation" --cwd "$SPEC_REPO" --timeout 30 2>&1 | tail -1)
if [[ -f "$result_path" ]] && jq . "$result_path" &>/dev/null; then
  test_pass
else
  test_fail "no valid proposals at: $result_path"
fi

test_start "forge-spectest.sh proposals contain task"
if [[ -f "$result_path" ]]; then
  task=$(jq -r '.task' "$result_path" 2>/dev/null)
  assert_contains "$task" "validation"
else
  test_fail "no proposals file"
fi

cd "$PLUGIN_ROOT"
rm -rf "$SPEC_REPO"

# ── forge-fitness.sh composite score tests ───────────────────────────────────
echo ""
echo "--- forge-fitness.sh (composite score) ---"

FITNESS2_REPO=$(mktemp -d)
cd "$FITNESS2_REPO"
git init -q
echo "hello" > file.txt
git add file.txt && git commit -q -m "init"
echo "modified" > file.txt

test_start "forge-fitness.sh includes composite_score field"
result_path=$(bash "${PLUGIN_ROOT}/scripts/forge-fitness.sh" \
  --dir "$FITNESS2_REPO" --cmd "true" --label test-composite 2>&1 | tail -1)
if [[ -f "$result_path" ]]; then
  composite=$(jq -r '.composite_score' "$result_path" 2>/dev/null)
  if [[ -n "$composite" && "$composite" != "null" ]]; then
    test_pass
  else
    test_fail "no composite_score field"
  fi
else
  test_fail "no result file"
fi

test_start "forge-fitness.sh composite_score is numeric"
if [[ "$composite" =~ ^[0-9]+$ ]]; then
  test_pass
else
  test_fail "expected numeric, got $composite"
fi

cd "$PLUGIN_ROOT"
rm -rf "$FITNESS2_REPO"

# ── File structure tests (new scripts) ───────────────────────────────────────
echo ""
echo "--- file structure (v2.1) ---"

test_start "forge-run.sh exists"
assert_file_exists "${PLUGIN_ROOT}/scripts/forge-run.sh"

test_start "forge-run.sh is executable"
if [[ -x "${PLUGIN_ROOT}/scripts/forge-run.sh" ]]; then
  test_pass
else
  test_fail "forge-run.sh is not executable"
fi

test_start "forge-score.sh exists"
assert_file_exists "${PLUGIN_ROOT}/scripts/forge-score.sh"

test_start "forge-score.sh is executable"
if [[ -x "${PLUGIN_ROOT}/scripts/forge-score.sh" ]]; then
  test_pass
else
  test_fail "forge-score.sh is not executable"
fi

test_start "forge-spectest.sh exists"
assert_file_exists "${PLUGIN_ROOT}/scripts/forge-spectest.sh"

test_start "forge-spectest.sh is executable"
if [[ -x "${PLUGIN_ROOT}/scripts/forge-spectest.sh" ]]; then
  test_pass
else
  test_fail "forge-spectest.sh is not executable"
fi

# ── Cleanup ──────────────────────────────────────────────────────────────────
rm -rf "$MOCK_DIR" "$TEST_HOME"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "=== Results: ${PASS}/${TOTAL} passed, ${FAIL} failed ==="
echo ""

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
