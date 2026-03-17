# Postmortem Mode

Both AIs investigate a failure from different angles, like a real incident postmortem. Claude builds a unified timeline and identifies root cause.

Fixed 2-round protocol. Round 1: independent investigation. Round 2: cross-examine and identify root cause.

## Investigation angles

- AI_A: **Execution Investigator** — code paths, function calls, state mutations, logic divergence
- AI_B: **Environment Investigator** — config, deployment, dependencies, external factors, recent changes
- AI_C (if available): **Dependency Investigator** — third-party libraries, API contracts, upstream/downstream services

## Evidence format

```json
{"finding_id":"F1", "category":"execution|config|dependency|external", "finding":"...", "file":"path", "lines":"N-M", "evidence":"quoted code or config", "timeline_order":1, "is_root_cause":false, "is_contributing_factor":true}
```

## Judging (Investigator role)

1. **Verify each finding** — read referenced files, confirm the evidence.
2. **Build unified timeline** — merge both investigators' timelines chronologically.
3. **Identify root cause** — where do the execution and environment timelines intersect?
4. **Separate root cause from contributing factors.**
5. **Score each AI** by investigation quality:
   - Depth (0-10): How deep did they dig?
   - Accuracy (0-10): Were citations correct?
   - Root cause proximity (0-10): How close did they get to the actual root cause?

## Output format

```markdown
## Postmortem: [incident summary]

### Unified Timeline
| Order | Time/Sequence | Finding | Category | Evidence | Found By |
|-------|--------------|---------|----------|----------|----------|
| 1 | [first event] | ... | execution | file:lines | Codex |
| 2 | [second event] | ... | config | file:lines | Gemini |

### Root Cause
**[One sentence root cause statement]**

[2-3 sentences explaining how the execution path and environment factors combined to cause the failure]

### Contributing Factors
- [Factor 1 — how it made the failure worse or more likely]
- [Factor 2]

### Investigation Quality
| Buddy | Depth | Accuracy | Root Cause Proximity | Score |
|-------|-------|---------|---------------------|-------|
| ... | X/10 | X/10 | X/10 | X/30 |

### Recommended Fix
1. **Immediate:** [fix the root cause]
2. **Preventive:** [prevent recurrence]
3. **Detective:** [add monitoring/alerting to catch this earlier]
```
