# Changelog

## 1.0.0 (2026-03-10)

### Added
- `/codex` skill — ask Codex anything via `codex exec`
- `/codex-review` skill — code review with uncommitted, branch, or commit targets
- `/codex-help` command — reference and configuration
- Session-start hook — verifies Codex CLI and shows status banner
- `codex-run.sh` wrapper — handles timeout, output capture, error handling
- Config cascade: plugin config → codex config.toml → defaults
- Debug logging with auto-rotation
- Test suite with mock codex

### Note
- Renamed from `claudes-codex-buddy` to `claudes-ai-buddies` for multi-engine support
- Gemini CLI integration planned
