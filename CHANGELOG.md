# Changelog

## 2.0.0 (2026-03-12)

*Forge was born from a `/brainstorm` session — Claude, Codex, and Gemini designed the concept, picked the name, and shaped the architecture together. The feature they planned is built by the engines that imagined it.*

### Added
- **`/forge`** — Evolutionary multi-AI code forge. Three engines independently implement the same task in isolated git worktrees. Automated fitness tests and composite scoring determine the winner
- **Claude as pure orchestrator** — Claude dispatches, scores, and judges but never competes. All engines (including Claude) run as subprocesses via `claude-run.sh`, `codex-run.sh`, `gemini-run.sh`
- **Staged escalation** — Starter engine runs first; challengers only dispatch if starter doesn't auto-accept (score >= 88). Saves time and tokens
- **Critique-based synthesis** — On close calls (spread < 8), losers send targeted critique hunks against the winner's diff. Winner refines selectively. Better than brute-force cross-pollination
- **Speculative test generation** — Omit `--fitness` and engines propose test suites. You pick the best, then forge proceeds
- **Spectest trust boundary** — Command allowlist validates proposed test commands. Unknown commands flagged `needs_review: true` for explicit user approval. Shell metacharacters rejected
- **Baseline preflight** — Fitness runs on untouched code first. If it passes, warns user that the test is non-discriminating
- **Composite scoring** — `forge-score.sh` runs available linters (ESLint, Ruff, ShellCheck, Clippy) + style checks. `ai_buddies_compute_forge_score()` produces 0-100 score: diff size 30%, lint 15%, style 15%, files 10%, duration 5%, test pass 25%
- **Project context** — `ai_buddies_project_context()` reads CLAUDE.md/README, recent commits, language/conventions. Injected into forge prompts
- **Task-scoped context** — `ai_buddies_task_context()` injects only candidate files + conventions (lighter than full project context for engine prompts)
- **`--async`** — Run peer engines in background, continue conversation. `ai_buddies_forge_status()` checks progress
- **Compressed prompts** — Structured TASK/FITNESS/CONSTRAINTS format replaces verbose prose
- New scripts: `forge-run.sh`, `forge-fitness.sh`, `forge-score.sh`, `forge-spectest.sh`, `forge-synthesize.sh`, `claude-run.sh`
- New config keys: `forge_timeout`, `forge_auto_accept_score`, `forge_clear_winner_spread`, `forge_enable_synthesis`, `forge_max_critiques`, `forge_starter_strategy`, `forge_fixed_starter`, `forge_require_baseline_check`
- 140 tests covering all scripts, scoring, trust boundary, and integration scenarios

## 1.0.0 (2026-03-10)

### Added
- `/brainstorm` skill — multi-AI confidence bid: each engine rates confidence %, approach, risks, and needs on any task. User picks who builds it
- `/codex` skill — ask Codex anything via `codex exec`
- `/codex-review` skill — code review with uncommitted, branch, or commit targets
- `/gemini` skill — ask Gemini anything via `gemini -p`
- `/gemini-review` skill — code review via Gemini CLI
- `/buddy-help` command — reference and configuration
- Session-start hook — detects available AI CLIs and shows status banner
- `codex-run.sh` + `gemini-run.sh` wrappers — timeout, output capture, error handling
- Config cascade: plugin config → engine config → defaults
- Debug logging with auto-rotation
- Test suite (41 tests) with mock engines
- Works with any engine combination — Codex only, Gemini only, or both

### Fixed
- Gemini `--sandbox` flag: was passing string value to a boolean flag, causing timeouts in headless mode
