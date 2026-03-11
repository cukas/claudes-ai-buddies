---
name: forge
description: Evolutionary multi-AI code forge — three AIs build, test, and cross-pollinate
---

# /forge — Evolutionary Multi-AI Code Forge

Three AI engines independently implement the same task, compete on automated fitness tests, then cross-pollinate improvements into one refined solution.

## How to invoke

**Direct forge** — user specifies a focused task:
```
/forge "Add NaN guard to scoring" --fitness "npx jest"
```

Optional: `--timeout SECS` to override the safety cap (default: 600s). Engines self-exit when done — the timeout is just a safety net, not a target.

## Using forge inside existing planning workflows

`/forge` works as a **tool within any plan** — `/build-guard`, `/plan-guarded`, plan mode, or any task list. It is NOT a separate planning system.

### The `[forge]` tag

When building a plan (in any workflow), Claude can tag tasks:
- `[forge]` — algorithmic, tricky, multiple valid approaches → three-way competition
- No tag or `[direct]` — straightforward → Claude handles normally

Example plan (from `/build-guard`, plan mode, or anywhere):
```
1. Add RetryConfig type to shared types
2. [forge] Implement exponential backoff with jitter algorithm
3. Wire retry config into python-manager.ts
4. [forge] Add circuit breaker pattern for repeated failures
5. Add retry status to UI connection indicator
```

### During execution

When Claude reaches a `[forge]` task, it runs the full forge workflow below (setup → diverge → fitness → scoreboard → converge), then continues with the next task in the plan.

**Between forge tasks**, commit the working state so each forge starts from a clean base.

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

## Step-by-step workflow (single forge)

### Phase 0: Setup

1. **Parse args.** Extract the task, `--fitness` command, and optional `--timeout` (default 600s). If no `--fitness`, ask the user.
2. **Detect engines.** Source lib.sh and check binaries:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh"
CODEX_BIN=$(ai_buddies_find_codex 2>/dev/null) || CODEX_BIN=""
GEMINI_BIN=$(ai_buddies_find_gemini 2>/dev/null) || GEMINI_BIN=""
```

3. **Create forge directory and detached worktrees** (one per available engine):

```bash
FORGE_ID="$(date +%s)-${RANDOM}"
FORGE_DIR="/tmp/ai-buddies-${CLAUDE_SESSION_ID:-default}/forge-${FORGE_ID}"
mkdir -p "$FORGE_DIR"

ENGINES=(claude)
git worktree add --detach "$FORGE_DIR/wt-claude" HEAD
[[ -n "$CODEX_BIN" ]]  && ENGINES+=(codex)  && git worktree add --detach "$FORGE_DIR/wt-codex" HEAD
[[ -n "$GEMINI_BIN" ]] && ENGINES+=(gemini) && git worktree add --detach "$FORGE_DIR/wt-gemini" HEAD
```

4. **Tell the user** how many engines are competing, the task, and what fitness will run.

### Phase 1: Diverge (parallel implementation)

**Claude implements first** in `$FORGE_DIR/wt-claude/` using Edit/Write tools with absolute paths.

Then **send available peer engines in parallel** (one Bash call per engine, single message):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/{codex,gemini}-run.sh" \
  --prompt "IMPLEMENT_PROMPT" \
  --cwd "$FORGE_DIR/wt-{engine}" \
  --mode exec --timeout $FORGE_TIMEOUT  # default 600s — engines self-exit when done
```

**Implementation prompt** (replace TASK and FITNESS):

```
You are competing in a code forge against other AI engines. Implement this task so it passes the fitness test. Best implementation wins.

TASK: {task description}
FITNESS TEST: {fitness command}

RULES:
- Write the actual code — do not plan or ask questions.
- Modify only files necessary. Follow existing conventions.
- After implementing, RUN the fitness test yourself. If it fails, fix and retry until it passes.
- Exit when you're confident the fitness test passes. Take the time you need.
- Be thorough but minimal. Fewest lines changed wins ties.
```

**After each engine finishes**, read the output file. If it starts with `TIMEOUT:` or `ERROR:`, mark that engine accordingly in the scoreboard and continue.

### Phase 2: Crucible (fitness testing)

**Stage, diff, and score each engine** — run fitness calls in parallel (single message):

```bash
for engine in "${ENGINES[@]}"; do
  wt="$FORGE_DIR/wt-$engine"
  (cd "$wt" && git add -A && git diff --cached > "$FORGE_DIR/$engine-patch.diff")

  bash "${CLAUDE_PLUGIN_ROOT}/scripts/forge-fitness.sh" \
    --dir "$wt" --cmd "FITNESS_CMD" --label "$engine" --timeout 120
done
```

Read JSON results. Each contains: `pass`, `timed_out`, `exit_code`, `duration_sec`, `files_changed`, `diff_lines`.

### Phase 3: Scoreboard

Present to user — columns for available engines only:

```markdown
## Forge Scoreboard: [task summary]

| | Engine 1 | Engine 2 | Engine 3 |
|---|---|---|---|
| Fitness | PASS/FAIL/TIMEOUT | ... | ... |
| Duration | Xs | ... | ... |
| Files changed | N | ... | ... |
| Diff size | N lines | ... | ... |

**Winner:** [engine] — reason.
```

Winner: passed fitness with fewest changes. If none passed, report failures and ask user.

### Phase 4: Cross-pollinate (optional)

Ask user: "Run a refinement round?" If yes, share all diffs + scores with each engine:

```
Three implementations with fitness results:
{each engine's diff and score}

Improve the winner by taking the best from all three. Make it pass: {fitness command}.
```

Claude refines its worktree. Send peers in parallel. Run fitness again.

### Phase 5: Converge

**Ask user before applying.** Show winning diff. Options:
- **Apply:** Claude reads winning diff and applies via Edit tool (safer than `git apply`).
- **Cherry-pick:** Claude applies selected changes only.
- **Discard:** Clean up.

### Cleanup

**Always run**, regardless of outcome:

```bash
for engine in "${ENGINES[@]}"; do
  git worktree remove "$FORGE_DIR/wt-$engine" --force 2>/dev/null || true
done
rm -rf "$FORGE_DIR"
```

## Graceful degradation

- **3 engines:** Full three-way forge.
- **2 engines:** Two-way forge. 2-column scoreboard.
- **1 engine (solo):** Claude implements + fitness loop. No cross-pollination.
- **Timeout/error:** Mark in scoreboard, continue with remaining engines.

## Rules

- **Require `--fitness`.** No automated scoring = no forge.
- **Never touch user's working tree** until Phase 5 with explicit approval.
- **Always clean up** worktrees, even on error.
- **Time budget:** Default 600s safety cap per engine (user can override with `--timeout`). Engines self-exit when done. 120s for fitness. Two rounds max.
- **Check engine output** for `TIMEOUT:`/`ERROR:` markers before proceeding.
- **Stage before diffing:** `git add -A` then `git diff --cached` to capture new files.
