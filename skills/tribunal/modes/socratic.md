# Socratic Mode

Two AIs probe assumptions with code-grounded questions, then cross-answer. Claude synthesizes exposed assumptions.

Fixed 2-round protocol: Round 1 asks, Round 2 answers.

## Question types

- ASSUMPTION — What is taken for granted?
- CLARIFYING — What is ambiguous or undefined?
- EVIDENCE — What lacks proof?
- VIEWPOINT — What would a different perspective reveal?
- CONSEQUENCE — What follows if this is true/false?
- META — Is this the right question to ask?

## Evidence format

Round 1 (questions):
```json
{"question_id":"Q1", "type":"ASSUMPTION", "question":"...", "file":"path", "lines":"N-M", "evidence":"...", "why_it_matters":"..."}
```

Round 2 (answers):
```json
{"question_id":"Q1", "original_question":"...", "answer_status":"ANSWERED|UNANSWERABLE", "answer":"...", "file":"path", "lines":"N-M", "evidence":"...", "deeper_question":"...", "confidence":"HIGH|MEDIUM|LOW"}
```

## Synthesis

1. Verify evidence for both questions and answers.
2. Score question quality per buddy (0-10 each): specificity, evidence, actionability, novelty.
3. Do NOT pick a winner. Synthesize what was learned.

## Output format

```markdown
## Socratic Inquiry: [topic summary]

### Assumptions Exposed
| # | Assumption | Exposed By | Evidence | Status |
|---|-----------|-----------|----------|--------|
| 1 | [hidden assumption] | [buddy] | file:lines | CONFIRMED RISK / UNRESOLVED / SAFE |

### Key Questions Answered
| Question | Answer | Confidence | Evidence |
|----------|--------|-----------|----------|
| ... | ... | HIGH/MED/LOW | file:lines |

### Remaining Open Questions
- [Questions neither AI could answer]
- [Deeper questions from Round 2]

### Question Quality
| Buddy | Specificity | Evidence | Actionability | Novelty | Score |
|-------|-----------|----------|--------------|---------|-------|
| ... | X/10 | X/10 | X/10 | X/10 | X/40 |

### Recommended Next Steps
1. Investigate [open question] before deciding
2. The premise assumes [X] — verify with [method]
```
