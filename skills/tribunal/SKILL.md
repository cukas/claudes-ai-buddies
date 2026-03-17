---
name: tribunal
description: Multi-mode AI debate — adversarial, Socratic, steelman, red-team, synthesis, or postmortem with evidence
---

# /tribunal — Multi-Mode AI Debate

Two AI buddies engage on a codebase question using one of six modes. Every claim requires FILE:LINE evidence.

## Modes

| Mode | Flag | AIs do | Claude's role | Best for |
|------|------|--------|---------------|----------|
| adversarial | *(default)* | Argue FOR vs AGAINST | Judge — picks winner | Binary decisions, should/shouldn't |
| socratic | `--socratic` | Probe assumptions with questions | Synthesizer — surfaces insights | Early exploration, unclear framing |
| steelman | `--steelman` | Argue the OTHER side's strongest case | Calibrator — shows true strength of each side | Avoiding confirmation bias |
| red-team | `--red-team` | Attack from different angles, no defense | Risk assessor — prioritized vulnerability table | Poking holes in designs/plans |
| synthesis | `--synthesis` | Each proposes a solution, then hybridize | Merger — evaluates proposals + hybrid | Finding a third option |
| postmortem | `--postmortem` | Investigate failure from different angles | Investigator — unified timeline + root cause | Bug investigation, incident analysis |

## How to invoke

```
/tribunal "Should we refactor the auth middleware?"
/tribunal --socratic "Is our error handling resilient enough?"
/tribunal --steelman "Should we migrate to microservices?"
/tribunal --red-team "Review our new payment flow"
/tribunal --synthesis "How should we restructure the data layer?"
/tribunal --postmortem "Why did the deploy fail yesterday?"
/tribunal --mode red-team "Audit the new API endpoints"
```

## Step-by-step workflow

### Phase 0: Setup

1. **Parse the question and mode.** Check for mode flags (`--socratic`, `--steelman`, `--red-team`, `--synthesis`, `--postmortem`, or `--mode X`). Default: adversarial.
2. **Detect available buddies:**

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh"
AVAILABLE=$(ai_buddies_available_buddies)
```

3. Require at least 2 buddies.
4. **Tell the user** which buddies will participate, the mode, and round count.

### Phase 1: Dispatch

```bash
MANIFEST_PATH=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/tribunal-run.sh" \
  --question "THE_QUESTION" \
  --cwd "$(pwd)" \
  --mode MODE_NAME \
  --rounds 2 \
  --timeout 600)
```

### Phase 2: Read results

Read `$MANIFEST_PATH` (tribunal-manifest.json):

```json
{
  "question": "...",
  "mode": "adversarial|socratic|steelman|red-team|synthesis|postmortem",
  "rounds": 2,
  "debaters": ["codex", "gemini"],
  "arguments": { ... }
}
```

### Phase 3: Evaluate

**Read the mode-specific guide** for how to evaluate results and format output:

```
${CLAUDE_PLUGIN_ROOT}/skills/tribunal/modes/{mode}.md
```

Read the file matching the mode from the manifest, then follow its judging/synthesis instructions and output format.

## Round constraints

| Mode | Rounds | Reason |
|------|--------|--------|
| adversarial | Flexible (default 2) | More rounds = deeper rebuttals |
| steelman | Flexible (default 2) | Like adversarial but with reversed positions |
| socratic | Fixed 2 | Round 1 asks, Round 2 answers |
| red-team | Fixed 2 | Round 1 attacks, Round 2 chains attacks |
| synthesis | Fixed 2 | Round 1 proposes, Round 2 hybridizes |
| postmortem | Fixed 2 | Round 1 investigates, Round 2 cross-examines |

## Auto-triggers

1. **Forge close call:** When forge scores are within 3 points
2. **Review disagreement:** When `/codex-review` and `/gemini-review` conflict

## Configuration

| Key | Default | Description |
|-----|---------|-------------|
| `tribunal_rounds` | `2` | Default round count |
| `tribunal_max_buddies` | `3` | Max debaters |

## Rules

- **Evidence over eloquence.** Every claim needs file:line evidence.
- **Verify citations.** Always read referenced files to confirm.
- **No-evidence = zero.** Enforce in all modes.
- **Follow the mode guide.** Each mode has different judging criteria and output format.
- **Always clean up** worktrees after the session.
