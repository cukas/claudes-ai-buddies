---
name: forge
description: Evolutionary multi-AI code forge — three AIs build, test, and cross-pollinate
---

# /forge — Evolutionary Multi-AI Code Forge

Three AI engines independently implement the same task, compete on automated fitness tests, then cross-pollinate improvements into one refined solution.

## How to invoke

The user says `/forge "task description" --fitness "test command"`.

Examples:
- `/forge "Add input validation to the signup form" --fitness "npm test"`
- `/forge "Refactor auth service to async/await" --fitness "npm test && npx tsc --noEmit"`
- `/forge "Fix the race condition in WebSocket reconnect" --fitness "pytest -x"`

## Step-by-step workflow

### Phase 0: Setup

1. **Parse args.** Extract the task description and `--fitness` command. If no `--fitness`, ask the user — the forge requires automated scoring.
2. **Detect available engines.** Source lib.sh helpers and check for binaries:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh"
CODEX_BIN=$(ai_buddies_find_codex 2>/dev/null) || CODEX_BIN=""
GEMINI_BIN=$(ai_buddies_find_gemini 2>/dev/null) || GEMINI_BIN=""
```

Count available engines. Adapt worktree count accordingly (Claude always participates).

3. **Create forge directory and git worktrees.** Use `--detach` to avoid branch name collisions. Run via Bash:

```bash
FORGE_ID="$(date +%s)-${RANDOM}"
FORGE_DIR="/tmp/ai-buddies-${CLAUDE_SESSION_ID:-default}/forge-${FORGE_ID}"
mkdir -p "$FORGE_DIR"

# Detached worktrees — no branches to leak or collide
git worktree add --detach "$FORGE_DIR/wt-claude" HEAD
[[ -n "$CODEX_BIN" ]]  && git worktree add --detach "$FORGE_DIR/wt-codex" HEAD
[[ -n "$GEMINI_BIN" ]] && git worktree add --detach "$FORGE_DIR/wt-gemini" HEAD
```

4. **Tell the user** what's happening: how many engines are competing, the task, and what fitness command will be used.

### Phase 1: Diverge (parallel implementation)

**Claude implements first** in `$FORGE_DIR/wt-claude/` using Edit and Write tools with absolute paths pointing into the worktree.

Then **send available engines in parallel** (single message, one Bash call per engine):

```bash
# Call 1 (parallel — only if CODEX_BIN is set)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-run.sh" \
  --prompt "IMPLEMENT_PROMPT_HERE" \
  --cwd "$FORGE_DIR/wt-codex" \
  --mode exec \
  --timeout 180

# Call 2 (parallel — only if GEMINI_BIN is set)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gemini-run.sh" \
  --prompt "IMPLEMENT_PROMPT_HERE" \
  --cwd "$FORGE_DIR/wt-gemini" \
  --mode exec \
  --timeout 180
```

**After each engine finishes**, read the output file it prints. Check the content:
- If it starts with `TIMEOUT:` — mark that engine as TIMEOUT in the scoreboard.
- If it starts with `ERROR:` — mark that engine as ERROR in the scoreboard.
- Otherwise, the engine implemented something — proceed to fitness.

**The implementation prompt** (replace TASK and FITNESS):

```
You are competing in a code forge against two other AI engines. Your goal: implement this task so it passes the fitness test. Best implementation wins.

TASK: {task description}
FITNESS TEST: {fitness command}

RULES:
- Write the actual code. Do not plan, do not ask questions — just implement.
- Modify only the files necessary.
- Follow existing code conventions and patterns.
- Make it pass the fitness test.
- Be thorough but minimal.
```

### Phase 2: Crucible (fitness testing)

**Stage and capture diffs** from each worktree. Use `git add -A` first to include new files:

```bash
cd "$FORGE_DIR/wt-claude" && git add -A && git diff --cached > "$FORGE_DIR/claude-patch.diff"
cd "$FORGE_DIR/wt-codex"  && git add -A && git diff --cached > "$FORGE_DIR/codex-patch.diff"
cd "$FORGE_DIR/wt-gemini" && git add -A && git diff --cached > "$FORGE_DIR/gemini-patch.diff"
```

Then **run fitness in parallel** (one Bash call per engine, all in a single message):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/forge-fitness.sh" \
  --dir "$FORGE_DIR/wt-claude" --cmd "FITNESS_CMD" --label claude --timeout 120

bash "${CLAUDE_PLUGIN_ROOT}/scripts/forge-fitness.sh" \
  --dir "$FORGE_DIR/wt-codex" --cmd "FITNESS_CMD" --label codex --timeout 120

bash "${CLAUDE_PLUGIN_ROOT}/scripts/forge-fitness.sh" \
  --dir "$FORGE_DIR/wt-gemini" --cmd "FITNESS_CMD" --label gemini --timeout 120
```

Read the JSON result files. Each contains: `pass`, `timed_out`, `exit_code`, `duration_sec`, `files_changed`, `diff_lines`.

### Phase 3: Scoreboard

Present results to the user:

```markdown
## Forge Scoreboard: [task summary]

| | Claude | Codex | Gemini |
|---|---|---|---|
| Fitness | PASS/FAIL/TIMEOUT | PASS/FAIL/TIMEOUT | PASS/FAIL/TIMEOUT |
| Duration | Xs | Xs | Xs |
| Files changed | N | N | N |
| Diff size | N lines | N lines | N lines |

**Winner:** [engine] — passed fitness with fewest changes in least time.
```

If `timed_out` is true, show TIMEOUT. If only one passed, that's the winner. If multiple passed, prefer fewer files changed (simpler solution). If none passed, report all failures and ask the user how to proceed.

### Phase 4: Cross-pollinate (the magic)

Ask the user: "Run a refinement round? Each AI will see all three solutions and improve the winner."

If the user approves, **share all diffs + scores with each engine** and ask them to refine. Send to available engines in parallel:

```
Three AIs independently implemented this task. Here are all three approaches with fitness results:

[Claude's diff] — {PASS/FAIL/TIMEOUT}, {N} files, {X}s
[Codex's diff] — {PASS/FAIL/TIMEOUT}, {N} files, {X}s
[Gemini's diff] — {PASS/FAIL/TIMEOUT}, {N} files, {X}s

The current winner is {WINNER}. Your job: improve the winning implementation by taking the best ideas from ALL three. Focus on:
1. What the winner got right — keep it
2. What the other solutions caught that the winner missed
3. Edge cases none of them handled
4. Make it pass: {fitness command}

Apply your improvements directly to the code.
```

Claude also does its own refinement pass using Edit tools in its worktree.

Run fitness again on all refined versions. Present updated scoreboard.

### Phase 5: Converge

**Always ask the user before applying anything to their working tree.**

Show the winning diff. Let the user:
- **Apply it:** Claude reads the winning worktree's diff and applies changes to the user's main working tree using the Edit tool (safer than `git apply` which can fail on shifted line numbers).
- **Cherry-pick specific parts:** Claude applies only selected changes via Edit tool.
- **Discard:** Clean up and done.

### Cleanup

**Always clean up**, whether the user applies, discards, or if an error occurs mid-forge. Run this at the end of every forge, regardless of outcome:

```bash
git worktree remove "$FORGE_DIR/wt-claude" --force 2>/dev/null || true
git worktree remove "$FORGE_DIR/wt-codex" --force 2>/dev/null || true
git worktree remove "$FORGE_DIR/wt-gemini" --force 2>/dev/null || true
rm -rf "$FORGE_DIR"
```

If an error interrupts the forge before cleanup, still attempt cleanup before reporting the error to the user. Worktree and temp file cleanup is mandatory — never leave orphaned worktrees.

## Graceful degradation

- **3 engines (Claude + Codex + Gemini):** Full forge — three-way competition + cross-pollination.
- **2 engines (Claude + one peer):** Two-way forge — still valuable. Show 2-column scoreboard.
- **1 engine (Claude solo):** Solo forge — Claude implements, runs fitness, self-reviews in a loop. No cross-pollination but still useful for the test-driven workflow.
- **Engine timeout:** Mark as TIMEOUT in scoreboard. Continue with remaining engines.
- **Engine error:** Mark as ERROR in scoreboard. Continue. Never block on a failed engine.

Adapt the number of worktrees and parallel calls to match available engines. Skip any step that references an unavailable engine.

## Rules

- **Always require `--fitness`.** The forge is meaningless without automated scoring.
- **Never modify the user's main working tree** until Phase 5 with explicit approval.
- **Worktrees are disposable.** Always clean up, even on error.
- **Time budget:** Each engine gets max 180s for implementation, 120s for fitness. Two rounds max unless user requests more.
- **Report raw results.** Don't spin failures or inflate scores.
- **Never pass secrets or API keys** in prompts.
- **Diffs include new files.** Always `git add -A` before `git diff --cached` to capture new/untracked files.
- **Check engine output for errors.** After each codex-run.sh / gemini-run.sh call, read the output file and check if it starts with `TIMEOUT:` or `ERROR:` before proceeding.
