---
name: campfire
description: Open multi-AI conversation — all buddies think together on a topic, no competition, just talk
aliases: [think, talk]
---

# /campfire — Open Multi-AI Conversation

All available AI buddies respond to a topic together. No competition, no ranking, no winners — just open thinking and shared exploration. Each buddy speaks in their own voice.

## How to invoke

The user says `/campfire "topic"` or `/think "topic"` or `/talk "topic"`.

## Step-by-step workflow

1. **Parse the topic.** Extract what the user wants to discuss. Can be anything — a technical question, architecture idea, "what if" scenario, code review, or just a thought.

2. **Build conversation context.** Use your judgment — if the conversation has context the buddies would benefit from, summarize it. If the topic is standalone, skip it.

3. **Build the campfire prompt.** Wrap the user's topic with this framing:

```
CAMPFIRE

Topic: USER_TOPIC_HERE

Rules:
- This is a campfire — no competition, no ranking, no winners.
- Think freely. Share ideas, perspectives, "what if" scenarios.
- Be honest. Say "I'm not sure" if you're not sure.
- Build on the topic. Be interesting, not just useful.
- Keep it concise — 3-5 paragraphs max.
- Speak naturally in your own voice.
```

4. **Detect available buddies and dispatch ALL in parallel.**

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh"
AVAILABLE=$(ai_buddies_available_buddies)  # CSV: "claude,codex,gemini,opencode,..."
```

For each available buddy (excluding claude — you ARE claude), dispatch in parallel using their run scripts. **No timeout** — let them respond when ready:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-run.sh" \
  --prompt "$CAMPFIRE_PROMPT" --cwd "$(pwd)" --mode exec --timeout 0

bash "${CLAUDE_PLUGIN_ROOT}/scripts/gemini-run.sh" \
  --prompt "$CAMPFIRE_PROMPT" --cwd "$(pwd)" --mode exec --timeout 0

bash "${CLAUDE_PLUGIN_ROOT}/scripts/opencode-run.sh" \
  --prompt "$CAMPFIRE_PROMPT" --cwd "$(pwd)" --mode exec --timeout 0
```

**Run ALL buddy calls in parallel** using multiple Bash tool calls in a single message. Set the Bash tool `timeout` to `600000` (10 minutes) to give them plenty of room. If the user says "stop" or "cancel", interrupt the calls.

5. **Read ALL output files** in parallel.

6. **Present each response verbatim.** Show every buddy's raw words — don't summarize, don't paraphrase. Use this format:

```markdown
## Campfire: [topic summary]

---

**Codex:**
> [their full response, verbatim]

---

**Gemini:**
> [their full response, verbatim]

---

**OpenCode:**
> [their full response, verbatim]

---

**Claude:**
> [your own thoughts on the topic — same rules, think freely]
```

7. **Always add your own voice last.** You're part of the campfire too — share your genuine thoughts. Don't just summarize what others said.

## Handling availability

- Show whoever responds. If a buddy times out, skip them with a note: "*[Buddy] didn't make it to the campfire this time.*"
- Even with just one buddy available, the campfire works — it's you and them thinking together.
- If no buddies are available, it's just you — still respond thoughtfully.

## Example invocations

- `/campfire "What's the best way to handle auth in a microservices architecture?"`
- `/think "Is our current database schema going to scale?"`
- `/talk "What would you change about this codebase if you could start over?"`
- `/campfire "The future of AI-assisted development"`
- `/think "Should we use SSR or CSR for this project?"`

## Rules

- **No competition.** This is not brainstorm (bidding), tribunal (debate), or forge (builds). It's just thinking together.
- **Raw voices only.** Show each buddy's actual words in blockquotes. Never paraphrase or summarize their responses.
- **You participate.** Claude is not just the moderator — you're around the campfire too. Share your own thoughts.
- **Keep it light.** Short timeout (120s), concise responses. This is a conversation, not an essay contest.
- **Conversation context flows naturally.** If the discussion builds on prior conversation, include context. If it's a fresh topic, don't.
- **Never pass secrets or API keys** in the prompt.
