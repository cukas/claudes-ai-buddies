# Claude's AI Buddies

Use peer AI CLIs directly from Claude Code — brainstorm, delegate tasks, get code reviews.

## What it does

Spawns peer AI CLIs as subprocesses, captures the output, and presents it back through Claude. No MCP servers, no flaky connections — just direct CLI calls.

```
User → Claude → /codex skill → codex exec → output → Claude presents
```

## Skills

| Skill | Description |
|-------|-------------|
| `/codex "prompt"` | Ask Codex anything — brainstorm, delegate, second opinion |
| `/codex-review` | Code review via Codex (uncommitted, branch, commit) |
| `/codex-help` | Reference and configuration |

## Supported Engines

| Engine | CLI | Status |
|--------|-----|--------|
| OpenAI Codex | `codex` | Available |
| Google Gemini | `gemini` | Planned |

## Requirements

- [Codex CLI](https://github.com/openai/codex) v0.100.0+ (`npm install -g @openai/codex`)
- OpenAI authentication (`codex auth login` or `OPENAI_API_KEY` env var)
- Claude Code with plugin support

## Installation

```bash
# From the plugin directory
claude plugin install /path/to/claudes-ai-buddies

# Or via the monorepo
claude plugin install /path/to/claude-plugins/plugins/claudes-ai-buddies
```

## Configuration

Optional config at `~/.claudes-ai-buddies/config.json`:

```json
{
  "codex_model": "gpt-5.4-codex",
  "timeout": "120",
  "sandbox": "full-auto",
  "debug": "false"
}
```

Falls back to `~/.codex/config.toml` for model selection.

## Examples

```
/codex "What's the best way to implement a rate limiter in Go?"
/codex "Debug this error: Cannot read property 'map' of undefined"
/codex-review
/codex-review branch:main
/codex-review commit:a1b2c3d "focus on security"
```

## Testing

```bash
bash tests/run-tests.sh
```

## License

MIT
