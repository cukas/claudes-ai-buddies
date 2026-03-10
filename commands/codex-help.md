---
name: codex-help
description: Reference for Claude's AI Buddies plugin
---

# AI Buddies — Help & Reference

## Available Skills

| Skill | Description |
|-------|-------------|
| `/codex "prompt"` | Ask Codex anything — brainstorm, delegate, second opinion |
| `/codex-review` | Code review via Codex (uncommitted, branch, commit) |
| `/codex-help` | This help reference |

## Configuration

Config file: `~/.claudes-ai-buddies/config.json`

| Key | Default | Description |
|-----|---------|-------------|
| `codex_model` | *(from ~/.codex/config.toml)* | Override Codex model |
| `timeout` | `120` | Max seconds per call |
| `sandbox` | `full-auto` | Sandbox mode (`full-auto` or `suggest`) |
| `codex_path` | *(auto-detected)* | Explicit path to codex binary |
| `debug` | `false` | Enable debug logging |

### Example config

```json
{
  "codex_model": "gpt-5.4-codex",
  "timeout": "180",
  "sandbox": "full-auto",
  "debug": "false"
}
```

## Review Targets

```
/codex-review                        # uncommitted changes
/codex-review branch:main            # diff from main to HEAD
/codex-review commit:abc1234         # specific commit
/codex-review "focus on security"    # with extra instructions
```

## Requirements

- **Codex CLI** v0.100.0+ (`npm install -g @openai/codex`)
- **OpenAI auth** — either `codex auth login` (account) or `OPENAI_API_KEY` env var
- **jq** (optional, for config management)
- **git** (required for `/codex-review`)

## Debug Logging

Enable debug mode:
```bash
mkdir -p ~/.claudes-ai-buddies
echo '{"debug": "true"}' > ~/.claudes-ai-buddies/config.json
```

Logs are written to `~/.claudes-ai-buddies/debug.log` (auto-rotated at 1MB).

## How It Works

```
User → Claude → /codex skill → Bash(codex-run.sh) → codex exec → output file → Claude reads → presents
```

Codex runs in `--ephemeral --full-auto` mode — stateless, no interactive prompts, no persistent state.
Output is captured to a temp file via `-o`, which Claude reads and synthesizes.
