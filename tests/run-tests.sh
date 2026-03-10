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

# ── Cleanup ──────────────────────────────────────────────────────────────────
rm -rf "$MOCK_DIR" "$TEST_HOME"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "=== Results: ${PASS}/${TOTAL} passed, ${FAIL} failed ==="
echo ""

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
