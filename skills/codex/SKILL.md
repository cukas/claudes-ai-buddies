---
name: codex
description: Ask OpenAI Codex anything — brainstorm, delegate tasks, get a second opinion
---

# /codex — Peer AI via OpenAI Codex

You have access to OpenAI's Codex CLI as a peer AI. Use it to brainstorm, delegate tasks, get second opinions, or ask questions from a different AI perspective.

## How to invoke

Run the wrapper script via Bash. **IMPORTANT:** Codex regularly takes 3-6 minutes for non-trivial tasks. You MUST set the Bash tool's `timeout` parameter to `420000` (7 minutes) to prevent Claude Code from killing the process before Codex finishes.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-run.sh" \
  --prompt "YOUR PROMPT HERE" \
  --cwd "/path/to/relevant/directory" \
  --mode exec
```

Then read the output file path it prints and present the results to the user.

## Step-by-step workflow

1. **Parse the user's request.** The user says `/codex "some prompt"` or `/codex` followed by a question.
2. **Determine the working directory.** Default to the current project root. If the user references a specific repo or directory, use that.
3. **Run codex-run.sh** with `--mode exec` and the user's prompt via the Bash tool.
4. **Read the output file** using the Read tool. The script prints the output file path to stdout.
5. **Show Codex's raw response directly.** Use this format — show their actual words, don't paraphrase or summarize:

```
🔵 **Codex:**
> [their full response here, verbatim, as a blockquote]
```

6. **Add your own take only if asked.** If the user wants a comparison or synthesis, add it after Codex's response. Otherwise, let Codex's voice stand on its own.

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `--prompt` | (required) | The question or task for Codex |
| `--cwd` | current dir | Working directory for Codex |
| `--mode` | `exec` | Always `exec` for this skill |
| `--timeout` | from config (360s) | Max seconds to wait |
| `--model` | from config | Override the Codex model |
| `--sandbox` | `full-auto` | Sandbox mode: `full-auto` or `suggest` |

## Example invocations

- `/codex "What's the best way to implement a rate limiter in Go?"`
- `/codex "Review this architecture: we have a React frontend calling a FastAPI backend with Redis caching"`
- `/codex "Write a bash script that finds duplicate files by hash"`
- `/codex "Debug this error: TypeError: Cannot read property 'map' of undefined"`

## Rules

- **Always use `--ephemeral` and `--full-auto`** — these are hardcoded in the wrapper, never override them.
- **Never pass secrets or API keys** in the prompt.
- **Respect timeouts** — if Codex times out, tell the user and suggest a simpler prompt.
- **Frame the output clearly** — the user should always know which AI produced which response.
- **Don't modify files** based on Codex's suggestions without user confirmation.
