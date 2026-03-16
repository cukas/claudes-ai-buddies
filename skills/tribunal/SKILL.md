---
name: tribunal
description: Adversarial debate — two AIs argue opposite positions with evidence, Claude judges
---

# /tribunal — Adversarial Debate

Two AI buddies argue opposite positions on a codebase question. Every claim requires FILE:LINE evidence. Claude judges based on evidence quality, not consensus.

## How to invoke

```
/tribunal "Should we refactor the auth middleware to use async/await?"
/tribunal "Is the current caching strategy causing the memory leak?"
/tribunal "Would switching from REST to gRPC improve our API latency?"
```

## Trigger modes

1. **Manual:** User types `/tribunal "question"`
2. **Forge close call:** Auto-triggered when forge scores are within 3 points — was the winner really better?
3. **Review disagreement:** Auto-triggered when `/codex-review` and `/gemini-review` give conflicting assessments

## Step-by-step workflow

### Phase 0: Setup

1. **Parse the question.** Extract the debatable claim from the user's message.
2. **Detect available buddies:**

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh"
AVAILABLE=$(ai_buddies_available_buddies)
```

3. Require at least 2 buddies. If only 1 is available, explain and offer alternatives.
4. **Tell the user** which buddies will debate and how many rounds.

### Phase 1: Dispatch adversarial debate

Run the tribunal orchestrator:

```bash
MANIFEST_PATH=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/tribunal-run.sh" \
  --question "THE_QUESTION" \
  --cwd "$(pwd)" \
  --rounds 2 \
  --timeout 600)
```

### Phase 2: Read and judge

Read `$MANIFEST_PATH` (tribunal-manifest.json). It contains:

```json
{
  "question": "...",
  "rounds": 2,
  "debaters": ["codex", "gemini"],
  "arguments": {
    "codex": { "round_1": "...", "round_2": "..." },
    "gemini": { "round_1": "...", "round_2": "..." }
  }
}
```

### Phase 3: Evidence-weighted judging

**Your most important job as judge:**

1. **Parse evidence objects** from each debater's arguments. Expected format:
   ```json
   {"claim":"...", "file":"path", "lines":"N-M", "evidence":"quoted code", "severity":1-5}
   ```

2. **Verify each citation.** Read the referenced file and line range. Score evidence quality 0-10:
   - 10: Exact quote matches, line numbers correct, directly supports claim
   - 7-9: Correct file, approximate lines, relevant evidence
   - 4-6: Right area but stretched interpretation
   - 1-3: Tangential or misquoted
   - 0: Fabricated or wrong file

3. **Score = evidence_quality (0-10) x severity (1-5).** Max 50 per claim.

4. **No-evidence claims score ZERO.** This is the key differentiator from brainstorm.

5. **Present the verdict** using the format below.

## Output format

```markdown
## Tribunal: [question summary]

### Arguments

**FOR ([buddy name]):**
| Claim | File:Lines | Evidence Quality | Severity | Score |
|-------|-----------|-----------------|----------|-------|
| ... | path:N-M | X/10 | Y/5 | Z/50 |

**AGAINST ([buddy name]):**
| Claim | File:Lines | Evidence Quality | Severity | Score |
|-------|-----------|-----------------|----------|-------|
| ... | path:N-M | X/10 | Y/5 | Z/50 |

### Verdict

**Winner: [FOR/AGAINST]** — Total score X vs Y.

[2-3 sentence summary of why, highlighting the strongest evidence from each side]

### Key findings
- [Bullet point of most impactful evidence found]
- [Bullet point of claims that had weak/no evidence]
```

## Configuration

| Key | Default | Description |
|-----|---------|-------------|
| `tribunal_rounds` | `2` | Cross-examination rounds |
| `tribunal_max_buddies` | `2` | Max debaters (2 is ideal for adversarial) |

## Rules

- **Evidence over eloquence.** A well-cited claim beats a persuasive paragraph.
- **Verify citations.** Always read the referenced files to confirm evidence.
- **No-evidence = zero.** Enforce strictly.
- **Claude is the judge, not a debater.** You evaluate, you don't argue.
- **Always clean up** worktrees after the debate.
- **Keep it focused.** Tribunal is for specific codebase questions, not general opinions.
