# Changelog

## 2.0.0 (2026-03-11)

### Added
- **F1: `forge-run.sh`** — Shell orchestrator for forge. Creates peer worktrees, dispatches engines in parallel, runs fitness + quality scoring, writes `manifest.json`. SKILL.md now delegates orchestration to this script
- **F2: Async/Background Forge** — `--async` flag runs peer engines via `run_in_background`, lets you continue conversation. `ai_buddies_forge_status()` checks progress
- **F3: Speculative Test Generation** — `forge-spectest.sh` sends "propose fitness tests" to each engine when `--fitness` is omitted. Claude reviews proposals, user approves, then forge proceeds
- **F4: Context Summary** — `ai_buddies_project_context()` reads CLAUDE.md/README, recent commits, language detection, and conventions. Injected into forge prompts automatically
- **F5: Richer Scoring** — `forge-score.sh` runs available linters (ESLint, Ruff, ShellCheck, Clippy) on changed files, checks style (trailing whitespace, line length). `ai_buddies_compute_forge_score()` produces composite 0-100 score: diff size 30%, lint 15%, style 15%, files 10%, duration 5%, test pass 25%
- New lib.sh functions: `ai_buddies_forge_timeout()`, `ai_buddies_build_forge_prompt()`, `ai_buddies_build_spectest_prompt()`, `ai_buddies_forge_manifest()`, `ai_buddies_forge_status()`, `ai_buddies_compute_forge_score()`, `ai_buddies_project_context()`
- 47 new tests (105 total), covering all new scripts and functions

### Changed
- `forge-fitness.sh` now includes `lint_warnings`, `style_score`, and `composite_score` in output JSON (backward compatible — new fields only)
- `skills/forge/SKILL.md` rewritten around `forge-run.sh` orchestration. Prompts sourced from lib.sh, timeouts from config
- Scoreboard now shows composite scores, lint warnings, style scores, and flags close calls (within 5 points)

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
