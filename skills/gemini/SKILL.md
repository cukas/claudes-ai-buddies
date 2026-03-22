---
name: gemini
description: Ask Google Gemini anything — brainstorm, delegate tasks, get a second opinion
---

# /gemini — Peer AI via Google Gemini CLI

You have access to Google's Gemini CLI as a peer AI. Use it to brainstorm, delegate tasks, get second opinions, or ask questions from a different AI perspective.

## How to invoke

Run the wrapper script via Bash:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gemini-run.sh" \
  --prompt "YOUR PROMPT HERE" \
  --cwd "/path/to/relevant/directory" \
  --mode exec
```

Then read the output file path it prints and present the results to the user.

## Step-by-step workflow

1. **Parse the user's request.** The user says `/gemini "some prompt"` or `/gemini` followed by a question.
2. **Determine the working directory.** Default to the current project root. If the user references a specific repo or directory, use that.
3. **Run gemini-run.sh** with `--mode exec` and the user's prompt via the Bash tool.
4. **Read the output file** using the Read tool. The script prints the output file path to stdout.
5. **Present the result** to the user. Frame it as "Gemini's perspective" or "Gemini says:" — make it clear this came from the peer AI.
6. **Synthesize if appropriate.** If the user asked for a comparison or second opinion, provide your own perspective alongside Gemini's.

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `--prompt` | (required) | The question or task for Gemini |
| `--cwd` | current dir | Working directory for Gemini |
| `--mode` | `exec` | Always `exec` for this skill |
| `--timeout` | from config (360s) | Max seconds to wait |
| `--model` | from config | Override the Gemini model |
| `--sandbox` | `full-auto` | Sandbox mode: `full-auto` or `suggest` |

## Example invocations

- `/gemini "What's the best way to implement a rate limiter in Go?"`
- `/gemini "Review this architecture: we have a React frontend calling a FastAPI backend with Redis caching"`
- `/gemini "Write a bash script that finds duplicate files by hash"`
- `/gemini "Debug this error: TypeError: Cannot read property 'map' of undefined"`

## Rules

- **Never pass secrets or API keys** in the prompt.
- **Respect timeouts** — if Gemini times out, tell the user and suggest a simpler prompt.
- **Frame the output clearly** — the user should always know which AI produced which response.
- **Don't modify files** based on Gemini's suggestions without user confirmation.
