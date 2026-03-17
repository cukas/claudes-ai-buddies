# Synthesis Mode

Each AI proposes a different solution to the same problem. Round 2: each creates a hybrid combining the best of both approaches.

Fixed 2-round protocol. Round 1: independent proposals. Round 2: hybridize.

## Evidence format

Round 1 (proposals):
```json
{"approach_name":"...", "summary":"...", "changes":[{"file":"path", "lines":"N-M", "change":"what to do"}], "trade_offs":"...", "complexity":"LOW|MEDIUM|HIGH", "strengths":"..."}
```

Round 2 (hybrids):
```json
{"hybrid_name":"...", "take_from_own":"...", "take_from_other":"...", "changes":[...], "trade_offs":"...", "why_better":"Why this hybrid beats either proposal alone"}
```

## Judging (Merger role)

1. **Evaluate each proposal** (Round 1):
   - Concreteness (0-10): Does it reference actual files and code?
   - Feasibility (0-10): Can this realistically be implemented?
   - Completeness (0-10): Does it address the full problem?

2. **Evaluate each hybrid** (Round 2):
   - Integration quality (0-10): Do the combined parts work together?
   - Improvement (0-10): Is the hybrid genuinely better than either original?

3. **Present all options** — both originals and both hybrids — so the user has four choices.

## Output format

```markdown
## Synthesis: [problem summary]

### Proposal A ([buddy name])
- **Approach:** [summary]
- **Changes:** [file list]
- **Complexity:** LOW/MEDIUM/HIGH
- **Strengths:** [what it does best]
- **Trade-offs:** [what it sacrifices]
- **Score:** Concreteness X + Feasibility Y + Completeness Z = N/30

### Proposal B ([buddy name])
- **Approach:** [summary]
- **Changes:** [file list]
- **Complexity:** LOW/MEDIUM/HIGH
- **Strengths:** [what it does best]
- **Trade-offs:** [what it sacrifices]
- **Score:** Concreteness X + Feasibility Y + Completeness Z = N/30

### Best Hybrid
**[hybrid name]** — Takes [X] from A and [Y] from B.

[2-3 sentence rationale for why this combination works]

| Aspect | From Proposal A | From Proposal B |
|--------|----------------|----------------|
| ... | ... | ... |

### Recommendation
[Which option (A, B, hybrid A, hybrid B) Claude recommends and why]
```
