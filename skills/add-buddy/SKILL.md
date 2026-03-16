---
name: add-buddy
description: Register a new AI CLI as a buddy — interactive wizard or one-liner
---

# /add-buddy — Register a New AI Buddy

Register any CLI-based AI tool as a buddy so it participates in `/forge`, `/brainstorm`, and `/tribunal`.

## How to invoke

**One-liner:**
```
/add-buddy --id aider --binary aider --display "Aider" --modes exec
```

**Interactive (just the name):**
```
/add-buddy aider
```

## Step-by-step workflow

### If args are complete (--id and --binary provided):

1. Run the registration script directly:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/buddy-register.sh" \
  --id "ID" \
  --binary "BINARY" \
  --display "DISPLAY_NAME" \
  --modes "MODES" \
  --install-hint "HINT" \
  --timeout SECS
```

2. Verify the buddy was registered:

```bash
cat "${HOME}/.claudes-ai-buddies/buddies/ID.json"
```

3. Check if the binary is available:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh"
ai_buddies_find_buddy "ID" && echo "Found" || echo "Not found"
```

4. Report the result.

### If interactive (only name/id provided):

1. Ask for the binary name (what to type on the command line to run it).
2. Ask for display name (defaults to the ID).
3. Ask which modes it supports: `exec` (run tasks), `review` (code review), or both.
4. Ask for install hint (optional — shown when the binary isn't found).
5. Ask for timeout (default 120s).
6. Run the registration script with gathered info.
7. Test if the binary exists on PATH.
8. Report success.

## Output format

```
Registered buddy 'aider':
  Binary: aider
  Display: Aider
  Modes: exec, review
  Status: FOUND on PATH (/usr/local/bin/aider)

The buddy will now appear in /forge, /brainstorm, and /tribunal.
```

If the binary isn't found:
```
  Status: NOT FOUND — install with: pip install aider-chat
  The buddy is registered but won't participate until the binary is available.
```

## Rules

- **ID must be alphanumeric** (plus hyphens/underscores). Reject anything else.
- **Don't overwrite builtin buddies** (claude, codex, gemini). Warn and ask for a different ID.
- **Test the binary** after registration. Report found/not-found status.
- **Never pass secrets** in registration.
