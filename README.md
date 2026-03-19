<div align="center">

<img src="assets/banner.svg" alt="Claude's AI Buddies" width="100%"/>

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-247%2B-brightgreen.svg)](#-testing)
[![Claude Code Plugin](https://img.shields.io/badge/Claude_Code-plugin-blueviolet.svg)](https://github.com/cukas/claude-plugins)

*Any AI can join. They compete. You ship.*

</div>

---

## Quick Start

```bash
# 1. Install the engines you want (one or more)
npm install -g @openai/codex        # OpenAI Codex
npm install -g @google/gemini-cli   # Google Gemini
brew install opencode               # OpenCode (MiniMax, Anthropic, Google, etc.)

# 2. Authenticate
codex auth login                    # uses your OpenAI account
gemini auth login                   # uses your Google account
opencode providers login            # optional — pick a provider (works without for free model)

# 3. Add the marketplace & install
claude plugin marketplace add cukas/claudes-ai-buddies
claude plugin install claudes-ai-buddies@cukas

# Done — start a new Claude Code session
```

> Works with any combination of Codex, Gemini, OpenCode, or any custom AI CLI you register.

---

## All Skills

| Command | What it does |
|---------|-------------|
| `/brainstorm "task"` | Confidence bid — available buddies assess the task, you pick who builds it |
| `/forge "task" --fitness "cmd"` | Competitive build with automated scoring |
| `/tribunal "question"` | Evidence-based debate — 6 modes (adversarial, socratic, steelman, red-team, synthesis, postmortem) |
| `/leaderboard` | Show ELO ratings from forge competitions |
| `/add-buddy` | Register any CLI as a new buddy |
| `/codex "prompt"` | Ask Codex anything — delegate, brainstorm, second opinion |
| `/gemini "prompt"` | Ask Gemini anything — different model, different perspective |
| `/opencode "prompt"` | Ask OpenCode anything — multi-provider, configurable model |
| `/codex-review` | Code review via Codex (uncommitted, branch, or commit) |
| `/gemini-review` | Code review via Gemini (uncommitted, branch, or commit) |
| `/opencode-review` | Code review via OpenCode (uncommitted, branch, or commit) |
| `/buddy-help` | Full reference, config, troubleshooting |

---

## Dynamic Buddy Registry

**v3 makes the engine roster dynamic.** Any CLI-based AI tool can become a buddy:

```
/add-buddy --id aider --binary aider --display "Aider" --modes exec
```

Registered buddies automatically participate in `/forge`, `/brainstorm`, and `/tribunal`. Buddy definitions are JSON capability contracts stored in `buddies/builtin/` (shipped) and `~/.claudes-ai-buddies/buddies/` (user-added).

---

## Brainstorm — Confidence Bid

<img src="assets/demo.gif" alt="Brainstorm demo — confidence bid in action" width="100%"/>

```
/brainstorm "Fix the race condition in the WebSocket reconnection handler"
```

Each available buddy assesses the task, rates their confidence, and proposes an approach. Claude calibrates the scores and recommends who should take it.

- **Dynamic roster** — table adapts to however many buddies are available
- **Three training sets catch blind spots** — disagreements are the most valuable signal
- **Other engines burn their tokens, not yours** — heavy thinking offloaded to peers
- **Claude calibrates the bids** — adjusts inflated/deflated scores based on approach quality

---

## Forge — Competitive Build

```
/forge "Add input validation to math utils" --fitness "npm test"
```

Available buddies independently implement the same task in isolated git worktrees. A staged pipeline scores them objectively — the best code wins.

```
## Forge Scoreboard

| | Claude | Codex | Gemini |
|---|---|---|---|
| Fitness | FAIL | PASS | PASS |
| Score | 0/100 | 82/100 | 89/100 |
| Duration | 4s | 12s | 8s |
| Lint warnings | 2 | 0 | 0 |

Winner: Gemini — score 89/100.
ELO updated: Gemini 1200→1216, Claude 1200→1184, Codex 1200→1184
```

- **Staged pipeline** — starter runs first; challengers only if needed; synthesis on close calls
- **Composite scoring** — diff size, lint, style, test pass, duration = objective 0-100 score
- **ELO tracking** — persistent ratings updated after each forge, per task class
- **Speculative tests** — omit `--fitness` and engines propose test suites
- **`--async`** — run in background, continue your conversation
- **Graceful degradation** — works with any number of engines (3, 2, or 1)

<details>
<summary><strong>How Forge works under the hood</strong></summary>

1. **Context** — detects languages, conventions, and candidate files from the task
2. **Stage 1: Starter** — one engine runs first. Auto-accepted if score >= 88 with clean lint
3. **Stage 2: Challengers** — remaining engines run in parallel if the starter didn't clear the bar
4. **Stage 3: Synthesis** — on close calls (spread < 8 pts), losers send critique hunks. Winner refines selectively
5. **Scoreboard** — composite scores (diff 30%, lint 15%, style 15%, files 10%, duration 5%, tests 25%)
6. **ELO** — winner gains rating vs each loser, per auto-detected task class
7. **Converge** — you approve the winning diff before it touches your working tree

**What to forge:** Algorithms, scoring logic, race conditions, performance-critical code — anything where multiple perspectives beat one.

**What NOT to forge:** Types, imports, config, UI layout — things with one obvious answer.

</details>

---

## Tribunal — Evidence-Based Debate

```
/tribunal "Should we refactor the auth middleware to use async/await?"
```

Two buddies debate with **evidence citations** (file:line). Claude judges based on evidence quality, not consensus. Auto-triggers on forge close calls or review disagreements.

<details>
<summary><strong>6 debate modes</strong></summary>

```
/tribunal "question"                  # adversarial (default)
/tribunal --socratic "question"       # probe assumptions
/tribunal --steelman "question"       # argue other side's best case
/tribunal --red-team "question"       # attack from all angles
/tribunal --synthesis "question"      # propose + hybridize
/tribunal --postmortem "question"     # investigate failure
```

| Mode | AIs do | Claude does | Best for |
|------|--------|-------------|----------|
| **adversarial** | FOR vs AGAINST | Judge — picks winner | Binary decisions |
| **socratic** | Probe assumptions | Synthesize insights | Early exploration |
| **steelman** | Argue other side's best case | Calibrate strength | Avoiding bias |
| **red-team** | Attack, no defense | Prioritize risks | Poking holes |
| **synthesis** | Propose, then hybridize | Evaluate + merge | Third option |
| **postmortem** | Investigate from angles | Timeline + root cause | Bug investigation |

</details>

---

## ELO Leaderboard

```
/leaderboard
/leaderboard algorithm
```

Persistent ELO ratings tracked per task class (algorithm, bugfix, refactor, feature, test, docs). Updated automatically after each forge.

---

## Direct Access & Code Reviews

**Ask anything:**
```
/codex "What's the best way to implement a rate limiter in Go?"
/gemini "Debug this: TypeError: Cannot read property 'map' of undefined"
/opencode "Review this architecture for scaling issues"
```

**Code reviews:**
```
/codex-review                                          # review uncommitted changes
/gemini-review                                         # review uncommitted changes
/opencode-review                                       # review uncommitted changes
/codex-review branch:main "focus on security"          # review branch diff with focus
```

---

## Using Forge in Your Planning Workflow

`/forge` plugs into your existing workflow (`/build-guard`, plan mode, or any task list). Tag tricky tasks with `[forge]`:

```
## Plan: Add retry logic to sidecar connection

1. Add RetryConfig type to shared types
2. [forge] Implement exponential backoff with jitter algorithm
3. Wire retry config into python-manager.ts
4. [forge] Add circuit breaker pattern for repeated failures
5. Add retry status to UI connection indicator
```

Claude handles the straightforward tasks directly. `[forge]` tasks trigger multi-way competition.

---

## Configuration

Optional — works out of the box. Config at `~/.claudes-ai-buddies/config.json`:

| Key | Default | Description |
|-----|---------|-------------|
| `codex_model` | *CLI default* | Codex model override |
| `gemini_model` | *CLI default* | Gemini model override |
| `opencode_model` | `opencode/minimax-m2.5-free` | OpenCode model (format: `provider/model`) |
| `timeout` | `120` | Max seconds per call (forge uses 600s) |
| `sandbox` | `full-auto` | `full-auto` or `suggest` |
| `debug` | `false` | Enable debug logging |
| `elo_enabled` | `true` | Track ELO ratings |
| `tribunal_rounds` | `2` | Tribunal cross-examination rounds |

---

## How It Works

```
┌──────────┐     ┌──────────────┐     ┌─────────────┐     ┌──────────────┐
│   User   │────>│  Claude Code  │────>│  Registry    │────>│  Any AI CLI   │
│          │     │  (orchestrator│     │  (buddy JSON │     │  (codex, gem  │
│          │<────│   + judge)    │<────│   + dispatch)│<────│   aider, ...) │
└──────────┘     └──────────────┘     └─────────────┘     └──────────────┘
```

- **Dynamic registry** — any CLI can become a buddy via JSON capability contract
- **No MCP servers** — direct CLI subprocess calls
- **No API keys in transit** — each engine uses its own auth
- **Parallel execution** — engines run simultaneously
- **Timeout-safe** — safety cap, engines self-exit when done

---

## Testing

```bash
bash tests/run-tests.sh
```

```
=== claudes-ai-buddies test suite ===
  ...
=== Results: 247+/247+ passed, 0 failed ===
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
