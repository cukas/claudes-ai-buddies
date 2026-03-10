<div align="center">

```
   _____ _                 _      _        ___  ___   ____            _     _ _
  / ____| |               | |    ( )      / _ \|_ _| | __ ) _   _  __| | __| (_) ___  ___
 | |    | | __ _ _   _  __| | ___|/___   / /_\ \| |  |  _ \| | | |/ _` |/ _` | |/ _ \/ __|
 | |    | |/ _` | | | |/ _` |/ _ \ / __| |  _  || |  | |_) | |_| | (_| | (_| | |  __/\__ \
 | |____| | (_| | |_| | (_| |  __/ \__ \ | | | || |  |____/ \__,_|\__,_|\__,_|_|\___||___/
  \_____|_|\__,_|\__,_|\__,_|\___| |___/ \_| |_/___|
```

**Give Claude a buddy. Or two.**

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-39%2F39-brightgreen.svg)](#testing)
[![Claude Code Plugin](https://img.shields.io/badge/Claude_Code-plugin-blueviolet.svg)](https://github.com/cukas/claude-plugins)

*Spawn peer AI CLIs directly from Claude Code. No MCP. No flaky connections. Just direct CLI calls.*

</div>

---

## 💡 The Idea

What if Claude could phone a friend?

**AI Buddies** lets Claude Code call other AI CLIs as peer assistants — brainstorm together, get second opinions, delegate tasks, or cross-check code reviews. Each AI brings its own strengths to the table.

```
You → Claude → /codex "how would you solve this?" → Codex thinks → Claude presents both perspectives
```

## 🚀 Quick Start

```bash
# 1. Install the engines you want
npm install -g @openai/codex        # OpenAI Codex
npm install -g @google/gemini-cli   # Google Gemini

# 2. Authenticate
codex auth login                    # uses your OpenAI account
gemini auth login                   # uses your Google account

# 3. Install the plugin
claude plugin install /path/to/claudes-ai-buddies
```

That's it. Start a new Claude Code session and you'll see:

```
[AI Buddies] Ready — Codex codex-cli 0.101.0 (gpt-5.4-codex) Gemini 0.32.1 (gemini-2.5-pro)
Available: /codex, /codex-review, /gemini, /gemini-review
```

## 🎯 Skills

### Ask anything

| Command | Engine | What it does |
|---------|--------|-------------|
| `/codex "prompt"` | OpenAI Codex | Brainstorm, delegate, get a second opinion |
| `/gemini "prompt"` | Google Gemini | Same — different AI, different perspective |

### Code reviews

| Command | Engine | What it does |
|---------|--------|-------------|
| `/codex-review` | OpenAI Codex | Review uncommitted changes, branches, commits |
| `/gemini-review` | Google Gemini | Same — fresh eyes from a different model |

### Help

| Command | What it does |
|---------|-------------|
| `/codex-help` | Full reference, config options, troubleshooting |

## 🤖 Supported Engines

| Engine | CLI | Model | Status |
|--------|-----|-------|--------|
| **OpenAI Codex** | `codex` | gpt-5.4-codex | ✅ Fully supported |
| **Google Gemini** | `gemini` | gemini-2.5-pro | ✅ Fully supported |

> Install only what you need. The plugin auto-detects available engines at session start.

## 📖 Examples

**Brainstorm with Codex:**
```
/codex "What's the best way to implement a rate limiter in Go?"
```

**Get Gemini's take on an error:**
```
/gemini "Debug this: TypeError: Cannot read property 'map' of undefined"
```

**Code review your uncommitted changes:**
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

## ⚙️ Configuration

Optional — works out of the box. Config at `~/.claudes-ai-buddies/config.json`:

```json
{
  "codex_model": "gpt-5.4-codex",
  "gemini_model": "gemini-2.5-pro",
  "timeout": "120",
  "sandbox": "full-auto",
  "debug": "false"
}
```

| Key | Default | Description |
|-----|---------|-------------|
| `codex_model` | *from ~/.codex/config.toml* | Codex model override |
| `gemini_model` | `gemini-2.5-pro` | Gemini model override |
| `timeout` | `120` | Max seconds per call |
| `sandbox` | `full-auto` | `full-auto` or `suggest` |
| `codex_path` | *auto-detected* | Explicit codex binary path |
| `gemini_path` | *auto-detected* | Explicit gemini binary path |
| `debug` | `false` | Enable debug logging |

## 🏗️ How It Works

```
┌──────────┐     ┌──────────────┐     ┌─────────────┐     ┌──────────────┐
│   User   │────▶│  Claude Code  │────▶│  Wrapper.sh  │────▶│  Peer AI CLI  │
│          │     │  (/codex or   │     │  (timeout,   │     │  (codex exec  │
│          │◀────│   /gemini)    │◀────│   capture)   │◀────│   gemini -p)  │
└──────────┘     └──────────────┘     └─────────────┘     └──────────────┘
                  reads output file    writes to temp file   runs headless
```

- **No MCP servers** — direct CLI subprocess spawn
- **No API keys in transit** — engines use their own auth
- **Stateless** — every call is ephemeral, no persistent state
- **Timeout-safe** — configurable timeout with graceful handling

## 🧪 Testing

```bash
bash tests/run-tests.sh
```

```
=== claudes-ai-buddies test suite ===
  ...
=== Results: 39/39 passed, 0 failed ===
```

## 📦 Part of the cukas Plugin Ecosystem

| Plugin | Description |
|--------|-------------|
| [**Remembrall**](https://github.com/cukas/remembrall) | Never lose work to context limits |
| [**Patrol**](https://github.com/cukas/patrol) | ESLint for Claude Code |
| **AI Buddies** | You are here |

All available via the [claude-plugins](https://github.com/cukas/claude-plugins) monorepo.

## 📄 License

MIT
