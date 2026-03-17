# Adversarial Mode

Two AIs argue FOR vs AGAINST. Claude judges based on evidence quality.

## Evidence format

```json
{"claim":"...", "file":"path", "lines":"N-M", "evidence":"quoted code", "severity":1-5}
```

## Judging

1. **Verify each citation.** Read the referenced file and line range. Score evidence quality 0-10:
   - 10: Exact quote matches, line numbers correct, directly supports claim
   - 7-9: Correct file, approximate lines, relevant evidence
   - 4-6: Right area but stretched interpretation
   - 1-3: Tangential or misquoted
   - 0: Fabricated or wrong file

2. **Score = evidence_quality (0-10) x severity (1-5).** Max 50 per claim.

3. **No-evidence claims score ZERO.**

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

[2-3 sentence summary highlighting the strongest evidence from each side]

### Key findings
- [Most impactful evidence found]
- [Claims with weak/no evidence]
```
