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
2. **Detect available engines:**

```bash
CODEX_OK=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-run.sh" --prompt "echo ok" --cwd /tmp --timeout 5 2>/dev/null && echo yes || echo no)
GEMINI_OK=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/gemini-run.sh" --prompt "echo ok" --cwd /tmp --timeout 5 2>/dev/null && echo yes || echo no)
```

Simpler: just check if the binary exists (source lib.sh patterns). Adapt the number of worktrees to available engines.

3. **Create forge directory and git worktrees.** Run via Bash:

```bash
FORGE_DIR="/tmp/ai-buddies-${CLAUDE_SESSION_ID:-default}/forge-$(date +%s)"
mkdir -p "$FORGE_DIR"

# Always create Claude's worktree
git worktree add "$FORGE_DIR/wt-claude" -b forge-claude-$$ HEAD

# Only if engine is available:
git worktree add "$FORGE_DIR/wt-codex" -b forge-codex-$$ HEAD
git worktree add "$FORGE_DIR/wt-gemini" -b forge-gemini-$$ HEAD
```

4. **Tell the user** what's happening: how many engines are competing, the task, and what fitness command will be used.

### Phase 1: Diverge (parallel implementation)

**Claude implements first** in `$FORGE_DIR/wt-claude/` using Edit and Write tools with absolute paths pointing into the worktree.

Then **send Codex + Gemini in parallel** (single message, two Bash calls):

```bash
# Call 1 (parallel)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-run.sh" \
  --prompt "IMPLEMENT_PROMPT_HERE" \
  --cwd "$FORGE_DIR/wt-codex" \
  --mode exec \
  --timeout 180

# Call 2 (parallel)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gemini-run.sh" \
  --prompt "IMPLEMENT_PROMPT_HERE" \
  --cwd "$FORGE_DIR/wt-gemini" \
  --mode exec \
  --timeout 180
```

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

**Capture diffs** from each worktree (parallel Bash calls):

```bash
cd "$FORGE_DIR/wt-claude" && git diff > "$FORGE_DIR/claude-patch.diff"
cd "$FORGE_DIR/wt-codex" && git diff > "$FORGE_DIR/codex-patch.diff"
cd "$FORGE_DIR/wt-gemini" && git diff > "$FORGE_DIR/gemini-patch.diff"
```

Then **run fitness in parallel** (up to 3 parallel Bash calls):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/forge-fitness.sh" \
  --dir "$FORGE_DIR/wt-claude" --cmd "FITNESS_CMD" --label claude

bash "${CLAUDE_PLUGIN_ROOT}/scripts/forge-fitness.sh" \
  --dir "$FORGE_DIR/wt-codex" --cmd "FITNESS_CMD" --label codex

bash "${CLAUDE_PLUGIN_ROOT}/scripts/forge-fitness.sh" \
  --dir "$FORGE_DIR/wt-gemini" --cmd "FITNESS_CMD" --label gemini
```

Read the JSON result files to get pass/fail, duration, files changed.

### Phase 3: Scoreboard

Present results to the user:

```markdown
## Forge Scoreboard: [task summary]

| | Claude | Codex | Gemini |
|---|---|---|---|
| Fitness | PASS/FAIL | PASS/FAIL | PASS/FAIL |
| Duration | Xs | Xs | Xs |
| Files changed | N | N | N |

**Winner:** [engine] — passed fitness with fewest changes in least time.
```

If only one passed, that's the winner. If multiple passed, prefer fewer files changed (simpler solution). If none passed, report all failures and ask the user how to proceed.

### Phase 4: Cross-pollinate (the magic)

Ask the user: "Run a refinement round? Each AI will see all three solutions and improve the winner."

If the user approves, **share all diffs + scores with each engine** and ask them to refine. Send to Codex + Gemini in parallel:

```
Three AIs independently implemented this task. Here are all three approaches with fitness results:

[Claude's diff] — {PASS/FAIL}, {N} files, {X}s
[Codex's diff] — {PASS/FAIL}, {N} files, {X}s
[Gemini's diff] — {PASS/FAIL}, {N} files, {X}s

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
- **Apply it:** `cd "$FORGE_DIR/wt-WINNER" && git diff HEAD | git -C ORIGINAL_REPO apply`
- **Cherry-pick specific parts:** Claude applies selected hunks via Edit tool
- **Discard:** Clean up and done

### Cleanup

Always clean up worktrees when done (whether user applies or discards):

```bash
git worktree remove "$FORGE_DIR/wt-claude" --force 2>/dev/null || true
git worktree remove "$FORGE_DIR/wt-codex" --force 2>/dev/null || true
git worktree remove "$FORGE_DIR/wt-gemini" --force 2>/dev/null || true
rm -rf "$FORGE_DIR"
```

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
- **Time budget:** Each engine gets max 180s per round. Two rounds max unless user requests more.
- **Report raw results.** Don't spin failures or inflate scores.
- **Never pass secrets or API keys** in prompts.
- **Diffs are the contract.** All collaboration happens through diffs and fitness scores — inspectable, reproducible, no hidden state.
