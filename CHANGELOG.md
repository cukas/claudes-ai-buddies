# Changelog

## 1.0.0 (2026-03-10)

### Added
- `/codex` skill — ask Codex anything via `codex exec`
- `/codex-review` skill — code review with uncommitted, branch, or commit targets
- `/gemini` skill — ask Gemini anything via `gemini -p`
- `/gemini-review` skill — code review via Gemini CLI
- `/codex-help` command — reference and configuration
- Session-start hook — detects available AI CLIs and shows status banner
- `codex-run.sh` + `gemini-run.sh` wrappers — timeout, output capture, error handling
- Config cascade: plugin config → engine config → defaults
- Debug logging with auto-rotation
- Test suite with mock engines
