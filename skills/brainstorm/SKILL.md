---
name: brainstorm
description: Multi-AI confidence bid — each AI rates their confidence on a task, user picks who takes it
---

# /brainstorm — Multi-AI Confidence Bid

Each available AI engine assesses a task (implementation, bug fix, refactor, etc.), gives a realistic confidence rating, and proposes their approach. The user picks who takes it.

## How to invoke

The user says `/brainstorm "task description"`.

## Step-by-step workflow

1. **Parse the task.** Extract what the user wants done from their message.
2. **Build the assessment prompt.** Wrap the user's task with this framing for Codex and Gemini:

```
Assess this task honestly. You are bidding alongside other AI engines — the user will pick who handles it. Be realistic, not optimistic.

Respond in EXACTLY this format (no other text):

CONFIDENCE: [0-100]%
APPROACH: [2-3 sentences max — what you'd do, step by step]
RISKS: [1-2 key risks or unknowns that could trip you up]
NEEDS: [what you'd need from the user — files, context, access, clarification]

Task: USER_TASK_HERE
```

3. **Run both engines in parallel.** Single message, two Bash calls.

```bash
# Call 1 (parallel)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-run.sh" \
  --prompt "ASSESSMENT_PROMPT" \
  --cwd "/path/to/project" \
  --mode exec

# Call 2 (parallel)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gemini-run.sh" \
  --prompt "ASSESSMENT_PROMPT" \
  --cwd "/path/to/project" \
  --mode exec
```

4. **Read both output files** (parallel).
5. **Add your own assessment.** Same format — confidence, approach, risks, needs. Be honest. If you're the best fit, say so. If not, say that too.
6. **Present the bid table** using the format below.

## Output format

```markdown
## Task: [short task summary]

| | Claude (Anthropic) | Codex (OpenAI) | Gemini (Google) |
|---|---|---|---|
| Confidence | X% | Y% | Z% |
| Approach | ... | ... | ... |
| Risks | ... | ... | ... |
| Needs | ... | ... | ... |

**Recommendation:** [Who should take this and why — or "user's call" if it's close]
```

Keep the table cells short. If an engine gave a long response, summarize to 1-2 sentences per cell.

## Calibration — your most important job

Each engine has a different confidence calibration. An 80% from Codex and 80% from Gemini don't mean the same thing. You are the calibrator:

- **Read the approach, not just the number.** If an engine says 85% but the approach is vague or hand-wavy, adjust down.
- **Check risks vs confidence.** If an engine lists serious risks but still claims high confidence, that's inflated — call it out.
- **Show both raw and calibrated.** In the table, show what each engine reported. In the recommendation, explain your adjusted read.
- **Flag overconfidence explicitly.** "Codex says 80% but their approach skips error handling — realistic confidence ~60%."
- **Flag underconfidence too.** If an engine is conservative but has a solid approach, say so.

The recommendation must reflect your calibrated assessment, not raw numbers.

## Your confidence guidelines (Claude)

Be brutally honest:
- **90-100%:** You've seen this exact pattern, know the codebase, and can do it right now
- **70-89%:** Solid approach, but some unknowns to investigate first
- **50-69%:** Can probably do it, but need more context or it's outside your sweet spot
- **30-49%:** Risky — might work but significant chance of going wrong
- **0-29%:** Not the right tool for this job — say so

Do NOT inflate your confidence to "win" the bid. The user trusts honest assessments.

## Handling partial availability

- If only one engine is available: show 2-column table (Claude + that engine)
- If neither is available: give your solo assessment, note the others aren't available
- If one engine times out: show its column as "TIMEOUT" and note it

## Example invocations

- `/brainstorm "Fix the race condition in the WebSocket reconnection handler"`
- `/brainstorm "Implement OAuth2 PKCE flow for our React Native app"`
- `/brainstorm "Refactor the payment service from callbacks to async/await"`
- `/brainstorm "Add dark mode support to the settings page"`

## Rules

- **One parallel call, one table.** No multi-round discussions. No token-burning debate.
- **Claude is the orchestrator.** You collect, summarize, recommend — then the user decides.
- **Realistic confidence only.** Overpromising wastes the user's time when the chosen AI fails.
- **Never pass secrets or API keys** in the prompt.
- **Keep it tight.** The whole output should fit on one screen.
