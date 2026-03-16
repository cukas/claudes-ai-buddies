---
name: buddy-help
description: Reference for Claude's AI Buddies plugin
---

# AI Buddies v3 — Help & Reference

## Available Skills

| Skill | Engine | Description |
|-------|--------|-------------|
| `/codex "prompt"` | Codex | Ask Codex anything — brainstorm, delegate, second opinion |
| `/codex-review` | Codex | Code review via Codex (uncommitted, branch, commit) |
| `/gemini "prompt"` | Gemini | Ask Gemini anything — brainstorm, delegate, second opinion |
| `/gemini-review` | Gemini | Code review via Gemini (uncommitted, branch, commit) |
| `/brainstorm "topic"` | All | Multi-AI roundtable — all available buddies assess the task |
| `/forge "task" --fitness "cmd"` | All | Competitive build — buddies build, automated scoring picks winner |
| `/tribunal "question"` | 2+ | Adversarial debate — buddies argue opposite positions with evidence |
| `/leaderboard` | — | Show ELO ratings leaderboard |
| `/add-buddy` | — | Register a new AI CLI as a buddy |
| `/buddy-help` | — | This help reference |

## Dynamic Buddy Registry (v3)

Any CLI-based AI tool can become a buddy. Builtin buddies (Claude, Codex, Gemini) are auto-detected. Register custom buddies with `/add-buddy`:

```bash
/add-buddy --id aider --binary aider --display "Aider" --modes exec
```

Buddy definitions are stored as JSON:
- Builtin: `<plugin>/buddies/builtin/*.json`
- User: `~/.claudes-ai-buddies/buddies/*.json`

## Configuration

Config file: `~/.claudes-ai-buddies/config.json`

### General

| Key | Default | Description |
|-----|---------|-------------|
| `timeout` | `120` | Max seconds per call |
| `sandbox` | `full-auto` | Sandbox mode (`full-auto` or `suggest`) |
| `debug` | `false` | Enable debug logging |

### Engine overrides

| Key | Default | Description |
|-----|---------|-------------|
| `codex_model` | *(CLI default)* | Override Codex model |
| `gemini_model` | *(CLI default)* | Override Gemini model |
| `claude_model` | *(CLI default)* | Override Claude model |
| `codex_path` | *(auto-detected)* | Explicit path to codex binary |
| `gemini_path` | *(auto-detected)* | Explicit path to gemini binary |
| `claude_path` | *(auto-detected)* | Explicit path to claude binary |

### Forge

| Key | Default | Description |
|-----|---------|-------------|
| `forge_timeout` | `600` | Engine timeout in seconds |
| `forge_auto_accept_score` | `88` | Stage 1 auto-accept threshold |
| `forge_clear_winner_spread` | `8` | Points spread to skip synthesis |
| `forge_enable_synthesis` | `true` | Enable critique-based synthesis |
| `forge_max_critiques` | `3` | Max critique hunks per loser |
| `forge_starter_strategy` | `fixed` | `fixed` or `rotate` |
| `forge_fixed_starter` | `claude` | Default starter |
| `forge_require_baseline_check` | `true` | Run fitness on base before forging |

### Tribunal

| Key | Default | Description |
|-----|---------|-------------|
| `tribunal_rounds` | `2` | Cross-examination rounds |
| `tribunal_max_buddies` | `2` | Max debaters |

### ELO

| Key | Default | Description |
|-----|---------|-------------|
| `elo_enabled` | `true` | Enable ELO tracking |
| `elo_k_factor` | `32` | ELO K-factor (higher = more volatile) |

### Example config

```json
{
  "codex_model": "gpt-5.4-codex",
  "gemini_model": "gemini-2.5-pro",
  "timeout": "180",
  "sandbox": "full-auto",
  "debug": "false",
  "elo_enabled": "true"
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
- **jq** (required for registry, ELO, tribunal)
- **git** (required for review skills, forge, tribunal)

## Debug Logging

Enable debug mode:
```bash
mkdir -p ~/.claudes-ai-buddies
echo '{"debug": "true"}' > ~/.claudes-ai-buddies/config.json
```

Logs are written to `~/.claudes-ai-buddies/debug.log` (auto-rotated at 1MB).

## How It Works

```
User → Claude → /skill → Bash(wrapper.sh) → CLI call → output file → Claude reads → presents
```

All engines run in non-interactive/headless mode — stateless, no interactive prompts, no persistent state.
Output is captured to a temp file, which Claude reads and synthesizes.
