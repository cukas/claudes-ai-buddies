# Changelog

## 3.1.0 (2026-03-17)

*Six tribunal modes — adversarial, Socratic, steelman, red-team, synthesis, postmortem.*

### Added
- **6 tribunal modes** via `--mode` flag or shorthand flags:
  - `adversarial` (default, unchanged) — FOR vs AGAINST, Claude judges
  - `--socratic` — probe assumptions with questions, Claude synthesizes
  - `--steelman` — argue the other side's strongest case, Claude calibrates
  - `--red-team` — attack from multiple angles (reliability, security, performance), Claude assesses risk
  - `--synthesis` — each proposes a solution, Round 2 hybridizes, Claude merges
  - `--postmortem` — investigate failure from execution/environment angles, Claude builds timeline
- **Mode-specific prompt builders** — `_ai_buddies_build_steelman_prompt()`, `_ai_buddies_build_redteam_prompt()`, `_ai_buddies_build_synthesis_prompt()`, `_ai_buddies_build_postmortem_prompt()`
- **Split mode documentation** — each mode has its own guide at `skills/tribunal/modes/{mode}.md` with evidence format, judging criteria, and output template
- **Round constraints** — socratic, red-team, synthesis, postmortem enforce exactly 2 rounds
- **Mode validation** — invalid `--mode` values rejected with error listing valid options

### Changed
- **tribunal-run.sh** — multi-mode positions, shorthand flags, mode validation, manifest includes `mode` field
- **lib.sh** — `ai_buddies_build_tribunal_prompt()` dispatches to mode-specific helpers (backward-compatible)
- **SKILL.md** — rewritten as slim dispatcher with mode table, delegates to per-mode docs
- **README.md** — tribunal section shows all 6 modes with comparison table
- **buddy-help.md** — all modes listed in skills table

## 3.0.0 (2026-03-14)

*Multi-AI Darwinism — the buddy roster is now dynamic. Any CLI can join the arena.*

### Added
- **Dynamic Buddy Registry** — JSON-based capability contracts for each buddy. Builtin buddies (`buddies/builtin/*.json`) + user-registered buddies (`~/.claudes-ai-buddies/buddies/*.json`). Generic `ai_buddies_find_buddy()`, `ai_buddies_available_buddies()`, `ai_buddies_dispatch_buddy()` replace hardcoded engine detection and case-statement dispatch
- **`/add-buddy`** — Register any CLI-based AI tool as a buddy. One-liner or interactive wizard
- **`/tribunal`** — Adversarial debate. Two buddies argue opposite positions with evidence citations (FILE:LINE). Claude judges based on evidence quality, not consensus. Configurable rounds
- **`/leaderboard`** — Persistent ELO ratings. Updated after each `/forge` run. Per-task-class tracking (algorithm, bugfix, refactor, feature, test, docs)
- **`buddy-run.sh`** — Generic wrapper for non-builtin buddies. Prompt via temp file, captures output
- **`buddy-register.sh`** — CLI helper to create buddy JSON definitions
- **`tribunal-run.sh`** — Adversarial debate orchestrator with multi-round cross-examination
- **`elo-update.sh`** — Pure awk/jq ELO calculator with provisional status
- **`elo-show.sh`** — Formatted leaderboard display
- New config keys: `tribunal_rounds`, `tribunal_max_buddies`, `elo_enabled`, `elo_k_factor`
- ~85 new tests (registry, tribunal, ELO, dispatch)

### Changed
- **Backward-compatible wrappers** — `ai_buddies_find_codex()`, `ai_buddies_codex_version()`, etc. are now thin wrappers around the generic registry functions
- **forge-run.sh** — uses `ai_buddies_available_buddies()` for detection, `ai_buddies_dispatch_buddy()` for dispatch, auto-updates ELO after scoring
- **forge-synthesize.sh** — critique and synthesis dispatch via generic `ai_buddies_dispatch_buddy()`
- **forge-spectest.sh** — engine detection and dispatch via registry
- **session-start.sh** — dynamic engine loop, shows `/tribunal`, `/leaderboard`, `/add-buddy` in banner
- **brainstorm SKILL.md** — dynamic buddy selection, top N cap
- **forge SKILL.md** — dynamic buddies, ELO integration docs
- **buddy-help.md** — new skills, config keys, registry docs

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
