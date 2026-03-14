---
name: leaderboard
description: Show ELO ratings leaderboard — per task class or overall
---

# /leaderboard — ELO Ratings

Show the persistent ELO ratings leaderboard. Ratings are updated after each `/forge` run based on who wins and loses.

## How to invoke

```
/leaderboard              # show all task classes
/leaderboard algorithm    # show only algorithm class
/leaderboard bugfix       # show only bugfix class
```

## Step-by-step workflow

1. **Parse optional task class** from the user's message.
2. **Run the leaderboard formatter:**

```bash
# All classes
bash "${CLAUDE_PLUGIN_ROOT}/scripts/elo-show.sh"

# Specific class
bash "${CLAUDE_PLUGIN_ROOT}/scripts/elo-show.sh" --task-class "algorithm"
```

3. **Present the output** to the user. If no data exists yet, explain that ratings start building after the first `/forge` run.

## Task classes

Ratings are tracked per task class (auto-detected from the forge task description):

| Class | Keywords |
|-------|----------|
| `algorithm` | algorithm, sort, search, scoring, math, compute |
| `refactor` | refactor, rename, extract, simplify, reorganize |
| `bugfix` | fix, bug, error, crash, broken, regression |
| `feature` | add, implement, create, build, feature, new |
| `test` | test, spec, coverage, assert |
| `docs` | doc, readme, comment, changelog |
| `other` | (default) |

## How ELO works

- All buddies start at **1200**
- K-factor: **32** (configurable)
- Winner gains points, loser loses points (zero-sum)
- Ratings below 100 are floored
- **Provisional** status for < 10 games

## Configuration

| Key | Default | Description |
|-----|---------|-------------|
| `elo_enabled` | `true` | Enable/disable ELO tracking |
| `elo_k_factor` | `32` | ELO K-factor (higher = more volatile) |

## Rules

- **Read-only.** This skill only displays ratings, never modifies them.
- **Suggest /forge** if no data exists yet.
- **Keep it brief.** Just show the table, no analysis unless asked.
