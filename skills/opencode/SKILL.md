---
name: opencode
description: Ask OpenCode anything — brainstorm, delegate tasks, get a second opinion
---

# /opencode — Peer AI via OpenCode CLI

You have access to OpenCode CLI as a peer AI. It supports multiple providers and models (MiniMax, Anthropic, Google, etc.). Use it to brainstorm, delegate tasks, get second opinions, or ask questions from a different AI perspective.

## How to invoke

Run the wrapper script via Bash. **IMPORTANT:** OpenCode can take 3-6 minutes depending on the model and task complexity. You MUST set the Bash tool's `timeout` parameter to `420000` (7 minutes) to prevent Claude Code from killing the process before OpenCode finishes.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/opencode-run.sh" \
  --prompt "YOUR PROMPT HERE" \
  --cwd "/path/to/relevant/directory" \
  --mode exec
```

Then read the output file path it prints and present the results to the user.

## Step-by-step workflow

1. **Parse the user's request.** The user says `/opencode "some prompt"` or `/opencode` followed by a question.
2. **Determine the working directory.** Default to the current project root. If the user references a specific repo or directory, use that.
3. **Run opencode-run.sh** with `--mode exec` and the user's prompt via the Bash tool.
4. **Read the output file** using the Read tool. The script prints the output file path to stdout.
5. **Present the result** to the user. Frame it as "OpenCode's perspective" or "OpenCode says:" — make it clear this came from the peer AI.
6. **Synthesize if appropriate.** If the user asked for a comparison or second opinion, provide your own perspective alongside OpenCode's.

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `--prompt` | (required) | The question or task for OpenCode |
| `--cwd` | current dir | Working directory for OpenCode |
| `--mode` | `exec` | Always `exec` for this skill |
| `--timeout` | from config (360s) | Max seconds to wait |
| `--model` | from config | Override the model (format: `provider/model`, e.g. `minimax/MiniMax-M2.5`) |

## Model configuration

**Default (zero config):** Uses `opencode/minimax-m2.5-free` — works without any API key.

**Custom model (persistent):** Set `opencode_model` in `~/.claudes-ai-buddies/config.json`:
```json
{ "opencode_model": "minimax/MiniMax-M2.5" }
```

**Per-invocation override:** Pass `--model` to the script:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/opencode-run.sh" \
  --prompt "..." --model "minimax/MiniMax-M2.7-highspeed"
```

**List available models:** `opencode models` or `opencode models minimax`

## Example invocations

- `/opencode "What's the best way to implement a rate limiter in Go?"`
- `/opencode "Review this architecture: we have a React frontend calling a FastAPI backend with Redis caching"`
- `/opencode --model minimax/MiniMax-M2.7 "Write a bash script that finds duplicate files by hash"`
- `/opencode "Debug this error: TypeError: Cannot read property 'map' of undefined"`

## Setup for new users

1. Install: `brew install opencode`
2. (Optional) Configure a provider: `opencode providers login -p minimax`
3. (Optional) Set default model in `~/.claudes-ai-buddies/config.json`

Without steps 2-3, the free `opencode/minimax-m2.5-free` model is used automatically.

## Rules

- **Never pass secrets or API keys** in the prompt.
- **Respect timeouts** — if OpenCode times out, tell the user and suggest checking their model with `opencode models`.
- **Frame the output clearly** — the user should always know which AI produced which response.
- **Don't modify files** based on OpenCode's suggestions without user confirmation.
