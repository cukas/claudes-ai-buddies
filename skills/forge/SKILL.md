---
name: forge
description: Evolutionary multi-AI code forge — three AIs build, test, and cross-pollinate
---

# /forge — Evolutionary Multi-AI Code Forge (v2)

Three AI engines independently implement the same task, compete on automated fitness tests, then the best solution is refined through critique-based synthesis. Claude is a **pure orchestrator** — it dispatches, scores, and judges but never competes.

## How to invoke

**Direct forge** — user specifies a focused task:
```
/forge "Add NaN guard to scoring" --fitness "npx jest"
```

Optional flags:
- `--timeout SECS` — override the safety cap (default: 600s from config key `forge_timeout`)
- `--async` — run in background, continue conversation
- `--engines claude,codex` — limit which engines compete (default: all available)
- `--starter codex` — override which engine runs first

## Using forge inside existing planning workflows

`/forge` works as a **tool within any plan** — `/build-guard`, `/plan-guarded`, plan mode, or any task list.

### The `[forge]` tag

When building a plan, Claude can tag tasks:
- `[forge]` — algorithmic, tricky, multiple valid approaches
- No tag or `[direct]` — straightforward, Claude handles normally

### What to tag `[forge]`

- Algorithms, scoring logic, data transformations
- Race condition fixes, concurrency patterns
- Performance-critical code paths
- Anything with multiple valid approaches where three perspectives help

### What NOT to tag `[forge]`

- Types, imports, config, UI layout, wiring
- Boilerplate, glue code — one obvious answer
- Anything without a runnable fitness test

---

## Step-by-step workflow

### Phase 0: Setup

1. **Parse args.** Extract the task, `--fitness` command, optional `--timeout`, `--async`, `--engines`, `--starter`.
2. **Detect engines.** Source lib.sh and use the dynamic registry:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh"
AVAILABLE=$(ai_buddies_available_buddies)  # CSV: "claude,codex,gemini,aider,..."
FORGE_TIMEOUT=$(ai_buddies_forge_timeout)
```

Any registered buddy with an installed binary will participate.

3. **Create forge directory:**

```bash
FORGE_ID="$(date +%s)-${RANDOM}"
FORGE_DIR="/tmp/ai-buddies-${CLAUDE_SESSION_ID:-default}/forge-${FORGE_ID}"
mkdir -p "$FORGE_DIR"
```

4. **Tell the user** how many engines are available, which is the starter, the task, and what fitness will run.

### Phase 0.5: Speculative Test Generation (if no `--fitness`)

When `--fitness` is omitted, run the spectest pre-phase:

```bash
SPECTEST_RESULT=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/forge-spectest.sh" \
  --task "$TASK" --cwd "$(pwd)" --timeout "$FORGE_TIMEOUT")
```

Review proposals, pick best, present to user for approval. Once approved, set `--fitness`.

**Trust boundary:** If any proposal has `"needs_review": true`, the proposed test command is outside the safe allowlist. You MUST present the command to the user and get explicit approval before using it as `--fitness`. Never auto-accept unreviewed commands.

### Phase 1: Dispatch via forge-run.sh (staged escalation)

**Claude does NOT implement.** Claude dispatches ALL engines (including a Claude subprocess) through forge-run.sh.

**Before dispatching:** Use your judgment — if the conversation contains context that would help the engines (constraints, failed approaches, user preferences, key decisions), summarize it. If the task is self-contained, skip it. Include:
- The user's original ask and constraints ("must be backwards compatible")
- Key decisions ("user wants X, not Y")
- What was already tried and failed
- Keep under ~500 tokens — actionable facts only, not the full transcript

Store in `$CONVERSATION_CONTEXT` (empty string if no relevant context).

**Synchronous (default):**
```bash
MANIFEST_PATH=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/forge-run.sh" \
  --forge-dir "$FORGE_DIR" \
  --task "$TASK" \
  --fitness "$FITNESS_CMD" \
  --cwd "$(pwd)" \
  --timeout "$FORGE_TIMEOUT" \
  --conversation-context "$CONVERSATION_CONTEXT")
```

**IMPORTANT:** Set the Bash tool's `timeout` parameter to `600000` (10 minutes) for synchronous forge runs. The default Bash timeout (120s) will kill slow engines mid-execution.

**Important:** Always pass `--cwd` to bind the forge to the correct repository, especially in async/background mode.

**Async (when `--async` flag is set):**
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/forge-run.sh" \
  --forge-dir "$FORGE_DIR" \
  --task "$TASK" \
  --fitness "$FITNESS_CMD" \
  --cwd "$(pwd)" \
  --timeout "$FORGE_TIMEOUT" \
  --conversation-context "$CONVERSATION_CONTEXT"
```
Run via Bash tool with `run_in_background: true`.

#### How staged escalation works (inside forge-run.sh)

1. **Baseline preflight** — run fitness on untouched code. If it passes, warn user (fitness test is non-discriminating).
2. **Stage 1** — dispatch starter engine alone. Score it.
   - Auto-accept if: `pass=true`, `score >= 88`, `lint <= 2`, `style >= 90`
   - If accepted → skip to Phase 2 (read results)
3. **Stage 2** — dispatch remaining challengers in parallel. Score all.
   - Clear winner if spread >= 8 points → skip synthesis
4. **Stage 3** — if close call (spread < 8, >= 2 passed):
   - Losers send max 3 critique hunks (JSON) against winner's diff
   - Winner refines from critiques in fresh worktree
   - Re-score refined version; keep only if improved

### Phase 2: Read Results

Read `$FORGE_DIR/manifest.json`. It contains:

```json
{
  "forge_id": "...",
  "forge_dir": "...",
  "engines": ["claude","codex","gemini"],
  "task": "...",
  "starter": "claude",
  "baseline_passes": false,
  "stage1_accepted": false,
  "engines_dispatched": 3,
  "results": {
    "<engine>": {
      "pass": true,
      "score": 85,
      "diff_lines": 27,
      "files_changed": 1,
      "duration_sec": 12,
      "lint_warnings": 0,
      "style_score": 95
    }
  },
  "patches": { "<engine>": "path/to/patch.diff" },
  "winner": "codex",
  "close_call": false,
  "synthesis": {
    "pass": true,
    "score": 91,
    "wins": true,
    "patch": "path/to/synth-patch.diff",
    "original_winner_score": 85
  }
}
```

### Phase 3: Scoreboard

Present to user — columns for available engines only:

```markdown
## Forge Scoreboard: [task summary]

| | Engine 1 | Engine 2 | Engine 3 |
|---|---|---|---|
| Fitness | PASS/FAIL/TIMEOUT | ... | ... |
| Score | 85/100 | ... | ... |
| Duration | Xs | ... | ... |
| Files changed | N | ... | ... |
| Diff size | N lines | ... | ... |
| Lint warnings | N | ... | ... |
| Style score | N/100 | ... | ... |

**Starter:** [engine] (stage 1)
**Engines dispatched:** N
**Winner:** [engine] — score X/100.
```

If `baseline_passes` is true, **warn the user**: "Fitness test passes on untouched code — results may be unreliable. Consider a more specific test." Do NOT auto-apply.
If `stage1_accepted` is true, note: "Auto-accepted in Stage 1 (score >= 88)."
If `close_call` is true, note: "Close call — synthesis was attempted."
If `synthesis.wins` is true, note: "Synthesis improved score from X to Y." The `winner` field becomes `"synthesis"` and the final patch is at `patches.synthesis`.

If no engine passed: show all as `[UNVERIFIED]`, report highest scorer, ask user.

### Phase 4: Converge

**Ask user before applying.** Show winning diff (or synthesis diff if synthesis won). Options:
- **Apply:** Claude reads winning diff and applies via Edit tool.
- **Cherry-pick:** Claude applies selected changes only.
- **Discard:** Clean up.

### Cleanup

**Always run**, regardless of outcome:

```bash
for engine in claude codex gemini baseline synth; do
  git worktree remove "$FORGE_DIR/wt-$engine" --force 2>/dev/null || true
done
rm -rf "$FORGE_DIR"
```

## Graceful degradation

- **3 engines:** Full three-way staged forge.
- **2 engines:** Starter + 1 challenger. Synthesis if close.
- **1 engine (solo):** Single engine + fitness loop. No synthesis.
- **Timeout/error:** Mark in scoreboard, continue with remaining engines.

## Configuration

All config via `~/.claudes-ai-buddies/config.json`:

| Key | Default | Description |
|---|---|---|
| `forge_enabled_engines` | `claude,codex,gemini` | Which engines can compete |
| `forge_starter_strategy` | `fixed` | `fixed` or `rotate` |
| `forge_fixed_starter` | `claude` | Default starter when strategy=fixed |
| `forge_auto_accept_score` | `88` | Stage 1 auto-accept threshold |
| `forge_clear_winner_spread` | `8` | Points spread to skip synthesis |
| `forge_enable_synthesis` | `true` | Enable critique-based synthesis |
| `forge_max_critiques` | `3` | Max critique hunks per loser |
| `forge_require_baseline_check` | `true` | Run fitness on base before forging |
| `forge_timeout` | `600` | Engine timeout in seconds |
| `elo_enabled` | `true` | Track ELO ratings after each forge |
| `elo_k_factor` | `32` | ELO K-factor |

## ELO Integration (v3)

After scoring, forge automatically updates ELO ratings:
- Winner gains points vs each loser (per task class)
- Task class is auto-detected from the task description (algorithm, bugfix, refactor, feature, test, docs, other)
- View ratings with `/leaderboard`

## Rules

- **Claude is a pure orchestrator.** Never implement directly. Dispatch all work to engine subprocesses.
- **Require `--fitness`** (or run spectest pre-phase to generate one).
- **Never touch user's working tree** until Phase 4 with explicit approval.
- **Always clean up** worktrees, even on error.
- **Baseline check:** If fitness passes on untouched code, warn user before proceeding.
- **Stage before diffing:** `git add -A` then `git diff --cached` to capture new files.
- **Prompts from lib.sh:** Use `ai_buddies_build_forge_prompt()` — never inline prompt text.
- **No-op guard:** If an engine's diff is empty, it gets score 0 regardless of fitness.
- **Deterministic tiebreaker:** score > lint(fewer) > style(higher) > diff(fewer) > files(fewer) > duration(less) > stable engine order.
