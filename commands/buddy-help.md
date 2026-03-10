---
name: buddy-help
description: Reference for Claude's AI Buddies plugin
---

# AI Buddies — Help & Reference

## Available Skills

| Skill | Engine | Description |
|-------|--------|-------------|
| `/codex "prompt"` | Codex | Ask Codex anything — brainstorm, delegate, second opinion |
| `/codex-review` | Codex | Code review via Codex (uncommitted, branch, commit) |
| `/gemini "prompt"` | Gemini | Ask Gemini anything — brainstorm, delegate, second opinion |
| `/gemini-review` | Gemini | Code review via Gemini (uncommitted, branch, commit) |
| `/brainstorm "topic"` | All | Multi-AI roundtable — Codex + Gemini + Claude perspectives |
| `/buddy-help` | — | This help reference |

## Configuration

Config file: `~/.claudes-ai-buddies/config.json`

| Key | Default | Description |
|-----|---------|-------------|
| `codex_model` | *(CLI default)* | Override Codex model (omit to use latest) |
| `gemini_model` | *(CLI default)* | Override Gemini model (omit to use latest) |
| `timeout` | `120` | Max seconds per call |
| `sandbox` | `full-auto` | Sandbox mode (`full-auto` or `suggest`) |
| `codex_path` | *(auto-detected)* | Explicit path to codex binary |
| `gemini_path` | *(auto-detected)* | Explicit path to gemini binary |
| `debug` | `false` | Enable debug logging |

### Example config

```json
{
  "codex_model": "gpt-5.4-codex",
  "gemini_model": "gemini-2.5-pro",
  "timeout": "180",
  "sandbox": "full-auto",
  "debug": "false"
}
```

## Review Targets

```
/codex-review                        # uncommitted changes (Codex)
/codex-review branch:main            # diff from main to HEAD
/gemini-review                       # uncommitted changes (Gemini)
/gemini-review commit:abc1234        # specific commit
```

## Requirements

- **Codex CLI** v0.100.0+ (`npm install -g @openai/codex`)
- **Gemini CLI** v0.30.0+ (`npm install -g @google/gemini-cli`)
- **Auth** — `codex auth login` / `gemini auth login` (or API key env vars)
- **jq** (optional, for config management)
- **git** (required for review skills)

## Debug Logging

Enable debug mode:
```bash
mkdir -p ~/.claudes-ai-buddies
echo '{"debug": "true"}' > ~/.claudes-ai-buddies/config.json
```

Logs are written to `~/.claudes-ai-buddies/debug.log` (auto-rotated at 1MB).

## How It Works

```
User → Claude → /codex or /gemini skill → Bash(wrapper.sh) → CLI call → output file → Claude reads → presents
```

Both engines run in non-interactive/headless mode — stateless, no interactive prompts, no persistent state.
Output is captured to a temp file, which Claude reads and synthesizes.
