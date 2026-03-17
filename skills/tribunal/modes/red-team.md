# Red-Team Mode

Both AIs attack the proposal from different angles. No defense. Pure offense. For poking holes in designs, plans, or implementations.

Fixed 2-round protocol. Round 1: independent attacks. Round 2: chain attacks from the other's findings.

## Attack vectors

- AI_A: **Reliability & Correctness** — bugs, race conditions, edge cases, data corruption, failure modes
- AI_B: **Security & Performance** — vulnerabilities, injection, resource leaks, bottlenecks, scaling
- AI_C (if available): **Maintainability & DX** — code smells, coupling, missing abstractions, documentation gaps

## Evidence format

```json
{"vulnerability":"...", "attack_type":"reliability|security|performance|maintainability", "file":"path", "lines":"N-M", "evidence":"quoted code", "severity":1-5, "exploit_scenario":"How this could be exploited or cause failure"}
```

## Judging (Risk Assessor role)

1. **Verify each vulnerability** — read the referenced code. Is the vulnerability real?
2. **Deduplicate** — remove findings that describe the same underlying issue.
3. **Map numeric severity to classification** (prompts use 1-5, output uses labels):
   - 5 → CRITICAL: Data loss, security breach, system crash in production
   - 4 → HIGH: Significant bug or vulnerability under normal usage
   - 3 → MEDIUM: Edge case failure or performance degradation under load
   - 2 → LOW: Code smell or minor issue unlikely to cause problems
   - 1 → INFO: Observation, not a vulnerability
4. **Score each AI** by unique verified findings weighted by severity.

## Output format

```markdown
## Red-Team Assessment: [target summary]

### Vulnerability Report

| # | Severity | Attack Type | Vulnerability | File:Lines | Found By |
|---|----------|------------|--------------|-----------|----------|
| 1 | CRITICAL | security | SQL injection in user input | api/users.ts:45-52 | Codex |
| 2 | HIGH | reliability | Race condition in cache update | cache/client.ts:88 | Gemini |

### Attack Chain (Round 2 findings)
- [Compound vulnerability: Finding X + Finding Y = Z]

### Risk Summary
- **Critical:** N findings
- **High:** N findings
- **Medium:** N findings
- **Low:** N findings

### Attacker Scores
| Buddy | Unique Findings | Avg Severity | Score |
|-------|----------------|-------------|-------|
| ... | N | X.X | Y |

### Recommended Mitigations
1. [Highest priority fix]
2. [Second priority fix]
```
