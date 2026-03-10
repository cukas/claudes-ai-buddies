# Claude's AI Buddies

Use peer AI CLIs directly from Claude Code — brainstorm, delegate tasks, get code reviews.

## What it does

Spawns peer AI CLIs as subprocesses, captures the output, and presents it back through Claude. No MCP servers, no flaky connections — just direct CLI calls.

```
User → Claude → /codex or /gemini → CLI exec → output → Claude presents
```

## Skills

| Skill | Engine | Description |
|-------|--------|-------------|
| `/codex "prompt"` | Codex | Ask Codex anything — brainstorm, delegate, second opinion |
| `/codex-review` | Codex | Code review (uncommitted, branch, commit) |
| `/gemini "prompt"` | Gemini | Ask Gemini anything — brainstorm, delegate, second opinion |
| `/gemini-review` | Gemini | Code review (uncommitted, branch, commit) |
| `/codex-help` | — | Reference and configuration |

## Supported Engines

| Engine | CLI | Install | Auth |
|--------|-----|---------|------|
| OpenAI Codex | `codex` | `npm i -g @openai/codex` | `codex auth login` |
| Google Gemini | `gemini` | `npm i -g @google/gemini-cli` | `gemini auth login` |

You only need to install the engines you want to use. The plugin detects what's available at session start.

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
  "gemini_model": "gemini-2.5-pro",
  "timeout": "120",
  "sandbox": "full-auto",
  "debug": "false"
}
```

## Examples

```
/codex "What's the best way to implement a rate limiter in Go?"
/gemini "Debug this error: Cannot read property 'map' of undefined"
/codex-review
/gemini-review branch:main
/codex-review commit:a1b2c3d "focus on security"
```

## Testing

```bash
bash tests/run-tests.sh
```

## License

MIT
