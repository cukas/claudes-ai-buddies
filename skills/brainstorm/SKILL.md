---
name: brainstorm
description: Multi-AI roundtable — get perspectives from Claude, Codex, and Gemini on any topic
---

# /brainstorm — Multi-AI Roundtable

Run a brainstorm with all available AI engines. Codex and Gemini respond in parallel, then you (Claude) synthesize all three perspectives into actionable output.

## How to invoke

The user says `/brainstorm "topic or question"`.

## Step-by-step workflow

1. **Parse the user's prompt.** Extract the topic/question from the user's message.
2. **Run both engines in parallel.** Use a single message with TWO Bash tool calls — one for Codex, one for Gemini. Both use `--mode exec`.

```bash
# Call 1 (parallel)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-run.sh" \
  --prompt "TOPIC_HERE" \
  --cwd "/path/to/project" \
  --mode exec

# Call 2 (parallel)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gemini-run.sh" \
  --prompt "TOPIC_HERE" \
  --cwd "/path/to/project" \
  --mode exec
```

3. **Read both output files** using the Read tool (parallel).
4. **Add your own perspective.** You are not just a moderator — contribute your own analysis.
5. **Present a structured roundtable** using the format below.

## Output format

```markdown
## Roundtable: [topic]

### Codex (OpenAI)
[Codex's response, summarized or quoted]

### Gemini (Google)
[Gemini's response, summarized or quoted]

### Claude (Anthropic)
[Your own perspective]

### Synthesis
[Where they agree, where they diverge, and your recommended approach]
```

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `--prompt` | (from user) | The brainstorm topic |
| `--cwd` | current dir | Working directory context |
| `--timeout` | from config (120s) | Max seconds per engine |

## Handling partial availability

- If only Codex is available: run Codex + Claude (skip Gemini section)
- If only Gemini is available: run Gemini + Claude (skip Codex section)
- If neither is available: tell the user and give your own answer solo
- If one engine times out: show the other's response + yours, note the timeout

## Example invocations

- `/brainstorm "Best approach for real-time notifications — SSE vs WebSockets vs polling?"`
- `/brainstorm "Should we use a monorepo or polyrepo for our microservices?"`
- `/brainstorm "Review our authentication strategy: JWT + refresh tokens + Redis session store"`
- `/brainstorm "Name ideas for a CLI tool that manages environment variables"`

## Rules

- **Never pass secrets or API keys** in the prompt.
- **Always run both engines in parallel** — never sequentially.
- **Contribute your own perspective** — don't just relay the other AIs' answers.
- **Be honest about disagreements** — if you think Codex or Gemini is wrong, say so.
- **Keep it concise** — summarize lengthy responses, don't dump walls of text.
