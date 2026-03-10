<div align="center">

<img src="assets/banner.svg" alt="Claude's AI Buddies" width="100%"/>

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-41%2F41-brightgreen.svg)](#-testing)
[![Claude Code Plugin](https://img.shields.io/badge/Claude_Code-plugin-blueviolet.svg)](https://github.com/cukas/claude-plugins)

*Three AI engines. One decision. You pick who builds it.*

</div>

---

## The Idea

What if you could pitch a task to three AI engines at once — and pick the one that's most confident?

**AI Buddies** connects Claude Code to peer AI CLIs. Ask a question, get a code review, or run a **confidence bid** where Claude, Codex, and Gemini each assess a task honestly. You see who's confident, who's hesitant, and why — then you pick who does the work.

```
You → /brainstorm "fix the auth bug" → Claude + Codex + Gemini each bid → You pick → Winner builds it
```

> Install only the engines you want. Works with just Codex, just Gemini, or both.

---

## Confidence Bid — the headline feature

```
/brainstorm "Fix the race condition in the WebSocket reconnection handler"
```

Each available engine assesses the task and gives a realistic confidence rating:

```
| | Claude (Anthropic) | Codex (OpenAI) | Gemini (Google) |
|---|---|---|---|
| Confidence | 85% | 70% | 60% |
| Approach | Trace reconnect flow, | Add mutex lock on | Use exponential backoff |
| | find state leak | shared connection | with jitter |
| Risks | Might miss edge case | Could deadlock if | Doesn't fix root cause, |
| | in retry logic | not scoped right | just masks it |
| Needs | Access to WS module | Connection manager | Full error logs |

Recommendation: Claude — highest confidence, already knows the codebase
```

**Why this works:**
- ~400 tokens total — cheaper than Claude reasoning through it alone
- Three different training sets catch blind spots the others miss
- Disagreements are the most valuable signal — when one AI says 40% and the others say 80%, that's worth investigating
- Zero wasted compute — only the winner does the actual work

---

## Quick Start

```bash
# 1. Install the engines you want (one or both)
npm install -g @openai/codex        # OpenAI Codex
npm install -g @google/gemini-cli   # Google Gemini

# 2. Authenticate
codex auth login                    # uses your OpenAI account
gemini auth login                   # uses your Google account

# 3. Add the marketplace & install
claude plugin marketplace add github:cukas/claudes-ai-buddies
claude plugin install claudes-ai-buddies
```

Start a new Claude Code session:

```
[AI Buddies] Ready — Codex codex-cli 0.101.0 (gpt-5.4-codex) Gemini 0.32.1 (gemini-2.5-pro)
Available: /codex, /codex-review, /gemini, /gemini-review, /brainstorm
```

---

## All Skills

| Command | Engines | What it does |
|---------|---------|-------------|
| `/brainstorm "task"` | All available | Confidence bid — each AI rates the task, you pick who builds it |
| `/codex "prompt"` | Codex | Ask Codex anything — delegate, brainstorm, second opinion |
| `/gemini "prompt"` | Gemini | Ask Gemini anything — different model, different perspective |
| `/codex-review` | Codex | Code review via Codex (uncommitted, branch, or commit) |
| `/gemini-review` | Gemini | Code review via Gemini (uncommitted, branch, or commit) |
| `/buddy-help` | — | Full reference, config, troubleshooting |

---

## Examples

**Confidence bid — who should take this?**
```
/brainstorm "Implement OAuth2 PKCE flow for our React Native app"
```

**Delegate to Codex:**
```
/codex "What's the best way to implement a rate limiter in Go?"
```

**Get Gemini's take:**
```
/gemini "Debug this: TypeError: Cannot read property 'map' of undefined"
```

**Code review uncommitted changes:**
```
/codex-review
/gemini-review
```

**Review a branch diff with focus:**
```
/codex-review branch:main "focus on security and SQL injection"
```

**Review a specific commit:**
```
/gemini-review commit:a1b2c3d
```

---

## Supported Engines

| Engine | CLI | Model | Status |
|--------|-----|-------|--------|
| **OpenAI Codex** | `codex` | latest (or override) | Fully supported |
| **Google Gemini** | `gemini` | latest (or override) | Fully supported |

> Install only what you need. The plugin auto-detects at session start. `/brainstorm` works with one engine or both — Claude always participates.

---

## How It Works

```
┌──────────┐     ┌──────────────┐     ┌─────────────┐     ┌──────────────┐
│   User   │────▶│  Claude Code  │────▶│  Wrapper.sh  │────▶│  Peer AI CLI  │
│          │     │  (orchestrator│     │  (timeout,   │     │  (codex exec  │
│          │◀────│   + judge)    │◀────│   capture)   │◀────│   gemini -p)  │
└──────────┘     └──────────────┘     └─────────────┘     └──────────────┘
                  reads output file    writes to temp file   runs headless
```

- **No MCP servers** — direct CLI subprocess calls
- **No API keys in transit** — each engine uses its own auth
- **Stateless** — every call is ephemeral, no persistent state
- **Parallel execution** — engines run simultaneously, not sequentially
- **Timeout-safe** — configurable timeout with graceful handling

---

## Configuration

Optional — works out of the box. Config at `~/.claudes-ai-buddies/config.json`:

```json
{
  "codex_model": "gpt-5.4-codex",
  "gemini_model": "gemini-3.0-pro",
  "timeout": "120",
  "sandbox": "full-auto",
  "debug": "false"
}
```

| Key | Default | Description |
|-----|---------|-------------|
| `codex_model` | *CLI default* | Codex model override |
| `gemini_model` | *CLI default* | Gemini model override |
| `timeout` | `120` | Max seconds per call |
| `sandbox` | `full-auto` | `full-auto` or `suggest` |
| `codex_path` | *auto-detected* | Explicit codex binary path |
| `gemini_path` | *auto-detected* | Explicit gemini binary path |
| `debug` | `false` | Enable debug logging |

> Models are optional. When not set, each CLI uses its own latest default.

---

## Testing

```bash
bash tests/run-tests.sh
```

```
=== claudes-ai-buddies test suite ===
  ...
=== Results: 41/41 passed, 0 failed ===
```

---

## Part of the cukas Plugin Ecosystem

| Plugin | Description |
|--------|-------------|
| [**Remembrall**](https://github.com/cukas/remembrall) | Never lose work to context limits |
| [**Patrol**](https://github.com/cukas/patrol) | ESLint for Claude Code |
| **AI Buddies** | You are here |

All available via the [claude-plugins](https://github.com/cukas/claude-plugins) monorepo.

---

MIT License
