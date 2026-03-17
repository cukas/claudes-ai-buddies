# Steelman Mode

Each AI builds the STRONGEST possible case for the position they may personally disagree with. Forces finding genuine merit. Produces more nuanced output than adversarial by filtering out weak strawman arguments.

Flexible rounds (default 2). Round 1: steelman arguments. Round 2+: challenge the other steelman.

## Evidence format

```json
{"claim":"...", "file":"path", "lines":"N-M", "evidence":"quoted code", "severity":1-5, "why_strongest":"Why this is the best version of this argument"}
```

## Judging (Calibrator role)

1. **Verify citations** — same rigor as adversarial mode (0-10 quality scale).
2. **Score steelman quality** — is this genuinely the strongest version? Or did the AI default to obvious/weak points?
   - 10: Non-obvious insight backed by strong evidence. A real advocate would make this argument.
   - 7-9: Solid point with good evidence, but somewhat expected.
   - 4-6: Valid but surface-level. Not truly steelmanning.
   - 1-3: Weak point dressed up as strong. Strawman in disguise.
3. **Present both steelmans side by side** so the user sees the best version of each position.

## Output format

```markdown
## Steelman Debate: [question summary]

### Strongest Case FOR ([buddy name]):
| Claim | File:Lines | Evidence Quality | Steelman Quality | Score |
|-------|-----------|-----------------|-----------------|-------|
| ... | path:N-M | X/10 | Y/10 | Z/100 |

### Strongest Case AGAINST ([buddy name]):
| Claim | File:Lines | Evidence Quality | Steelman Quality | Score |
|-------|-----------|-----------------|-----------------|-------|
| ... | path:N-M | X/10 | Y/10 | Z/100 |

### Calibration

**Strongest position: [FOR/AGAINST]** — Steelman score X vs Y.

[2-3 sentences: "The best case for X is genuinely strong because... The best case against is..."]

### Where even the steelman breaks
- [Weakness in the FOR steelman that Round 2 exposed]
- [Weakness in the AGAINST steelman that Round 2 exposed]
```
