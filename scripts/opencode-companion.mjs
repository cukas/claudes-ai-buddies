#!/usr/bin/env node
// opencode-companion.mjs — Structured output + session resume wrapper for OpenCode CLI.
// Zero dependencies. Uses OpenCode's --format json, --continue, and --session flags.
// Subcommands: task, review, resume
// Falls back gracefully if not available (exit code 2).

import { execSync, spawn } from "node:child_process";
import { writeFileSync, readFileSync, mkdirSync, existsSync } from "node:fs";
import { join } from "node:path";

// ── Constants ───────────────────────────────────────────────────────────────────

const VERSION = "1.0.0";

// ── Arg parsing ─────────────────────────────────────────────────────────────────

function parseArgs(argv) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith("--")) {
      const key = argv[i].slice(2);
      const next = argv[i + 1];
      if (next && !next.startsWith("--")) {
        args[key] = next;
        i++;
      } else {
        args[key] = true;
      }
    } else {
      args._.push(argv[i]);
    }
  }
  return args;
}

// ── Session state persistence ───────────────────────────────────────────────────

function getSessionDir() {
  const sessionId = process.env.CLAUDE_SESSION_ID || "default";
  const dir = join("/tmp", `ai-buddies-${sessionId}`);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  return dir;
}

function saveSessionState(sessionId, meta) {
  const dir = getSessionDir();
  const stateFile = join(dir, "opencode-sessions.json");
  let state = {};
  try {
    state = JSON.parse(readFileSync(stateFile, "utf8"));
  } catch {}
  state.lastSessionId = sessionId;
  state.sessions = state.sessions || {};
  state.sessions[sessionId] = { ...meta, updatedAt: Date.now() };
  writeFileSync(stateFile, JSON.stringify(state, null, 2));
}

function loadSessionState() {
  const dir = getSessionDir();
  const stateFile = join(dir, "opencode-sessions.json");
  try {
    return JSON.parse(readFileSync(stateFile, "utf8"));
  } catch {
    return null;
  }
}

// ── Find opencode binary ────────────────────────────────────────────────────────

function findOpenCodeSync() {
  try {
    return execSync("which opencode", { encoding: "utf8", stdio: "pipe" }).trim();
  } catch {
    const paths = [
      join(process.env.HOME || "", ".local/bin/opencode"),
      "/usr/local/bin/opencode",
    ];
    for (const p of paths) {
      if (existsSync(p)) return p;
    }
    return null;
  }
}

// ── Run OpenCode CLI ────────────────────────────────────────────────────────────

function runOpenCode(opencodeBin, cliArgs, cwd, timeoutMs) {
  return new Promise((resolve, reject) => {
    const proc = spawn(opencodeBin, cliArgs, {
      cwd,
      stdio: ["pipe", "pipe", "pipe"],
      env: { ...process.env, NO_COLOR: "1" },
    });

    let stdout = "";
    let stderr = "";

    proc.stdout.on("data", (d) => (stdout += d.toString()));
    proc.stderr.on("data", (d) => (stderr += d.toString()));

    const timer = setTimeout(() => {
      proc.kill("SIGTERM");
      reject(new Error(`Timeout after ${timeoutMs}ms`));
    }, timeoutMs);

    proc.on("close", (code) => {
      clearTimeout(timer);
      if (code === 0) {
        resolve({ stdout, stderr });
      } else {
        reject(new Error(`OpenCode exited with code ${code}: ${stderr}`));
      }
    });

    proc.on("error", (err) => {
      clearTimeout(timer);
      reject(err);
    });

    proc.stdin.end();
  });
}

// ── Strip ANSI escape codes ─────────────────────────────────────────────────────

function stripAnsi(str) {
  // Strip CSI sequences (\e[...m) and OSC sequences (\e]...\a)
  return str
    .replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "")
    .replace(/\x1b\][^\x07]*\x07/g, "");
}

// ── Parse OpenCode JSON output ──────────────────────────────────────────────────

function parseOpenCodeOutput(stdout, isJsonFormat) {
  if (!isJsonFormat) {
    return { response: stripAnsi(stdout), sessionId: null };
  }

  // OpenCode JSON format emits newline-delimited JSON events:
  //   {"type":"text", "sessionID":"...", "part":{"text":"...", ...}}
  //   {"type":"step_start", ...}
  //   {"type":"step_finish", "part":{"tokens":{...}, "cost":...}}
  const lines = stdout.split("\n").filter((l) => l.trim());
  let sessionId = null;
  let messages = [];
  let tokens = null;
  let cost = null;

  for (const line of lines) {
    try {
      const event = JSON.parse(line);

      // Extract session ID from any event
      if (event.sessionID) sessionId = event.sessionID;

      // Extract text content
      if (event.type === "text" && event.part?.text) {
        messages.push(event.part.text);
      }

      // Extract token/cost stats from step_finish
      if (event.type === "step_finish" && event.part?.tokens) {
        tokens = event.part.tokens;
        cost = event.part.cost;
      }
    } catch {
      // Non-JSON line, skip
    }
  }

  const response = messages.length > 0 ? messages.join("\n\n") : stripAnsi(stdout);
  return { response, sessionId, tokens, cost };
}

// ── Subcommands ─────────────────────────────────────────────────────────────────

async function cmdTask(args) {
  const prompt = args.prompt;
  if (!prompt) {
    process.stderr.write("ERROR: --prompt is required\n");
    process.exit(1);
  }

  const opencodeBin = args["opencode-bin"] || findOpenCodeSync();
  if (!opencodeBin) {
    process.stderr.write("ERROR: opencode CLI not found\n");
    process.exit(2);
  }

  const cwd = args.cwd || process.cwd();
  const timeout = parseInt(args.timeout || "360", 10) * 1000;
  const useJson = args["no-json"] !== true;

  // Build preamble to steer agent behavior
  const preamble =
    "You are a peer AI assistant. When given a specific response format, follow it exactly without performing other actions first. Only use tools if the task explicitly requires reading or modifying files.";
  const fullPrompt = preamble + "\n\n" + prompt;

  const cliArgs = ["run"];
  if (args.model) cliArgs.push("-m", args.model);
  if (useJson) cliArgs.push("--format", "json");
  cliArgs.push("--dir", cwd, fullPrompt);

  try {
    const { stdout } = await runOpenCode(opencodeBin, cliArgs, cwd, timeout);
    const parsed = parseOpenCodeOutput(stdout, useJson);

    if (parsed.sessionId) {
      saveSessionState(parsed.sessionId, {
        prompt: prompt.substring(0, 200),
        model: args.model,
      });
    }

    const outputFile = args.output;
    if (outputFile) {
      writeFileSync(outputFile, parsed.response);
      const metaFile = outputFile.replace(/\.md$/, ".meta.json");
      writeFileSync(
        metaFile,
        JSON.stringify({ sessionId: parsed.sessionId, tokens: parsed.tokens, cost: parsed.cost }, null, 2),
      );
      process.stdout.write(outputFile + "\n");
    } else {
      process.stdout.write(parsed.response + "\n");
    }
  } catch (err) {
    process.stderr.write(`ERROR: ${err.message}\n`);
    process.exit(1);
  }
}

async function cmdReview(args) {
  const prompt =
    args.prompt ||
    "Review the uncommitted changes for bugs, logic errors, and code quality issues.";
  args.prompt = prompt;
  return cmdTask(args);
}

async function cmdResume(args) {
  const prompt = args.prompt;
  if (!prompt) {
    process.stderr.write("ERROR: --prompt is required\n");
    process.exit(1);
  }

  const opencodeBin = args["opencode-bin"] || findOpenCodeSync();
  if (!opencodeBin) {
    process.stderr.write("ERROR: opencode CLI not found\n");
    process.exit(2);
  }

  const cwd = args.cwd || process.cwd();
  const timeout = parseInt(args.timeout || "360", 10) * 1000;
  const useJson = args["no-json"] !== true;

  // Find session to resume
  let sessionId = args["session-id"];
  if (!sessionId) {
    const state = loadSessionState();
    sessionId = state?.lastSessionId;
  }

  const cliArgs = ["run"];
  if (args.model) cliArgs.push("-m", args.model);
  if (useJson) cliArgs.push("--format", "json");

  if (sessionId) {
    cliArgs.push("--session", sessionId);
  } else {
    // No previous session — use --continue for latest
    cliArgs.push("--continue");
  }

  cliArgs.push("--dir", cwd, prompt);

  try {
    const { stdout } = await runOpenCode(opencodeBin, cliArgs, cwd, timeout);
    const parsed = parseOpenCodeOutput(stdout, useJson);

    const resolvedSessionId = parsed.sessionId || sessionId;
    if (resolvedSessionId) {
      saveSessionState(resolvedSessionId, {
        prompt: prompt.substring(0, 200),
        model: args.model,
        resumed: true,
      });
    }

    const outputFile = args.output;
    if (outputFile) {
      writeFileSync(outputFile, parsed.response);
      const metaFile = outputFile.replace(/\.md$/, ".meta.json");
      writeFileSync(
        metaFile,
        JSON.stringify({ sessionId: resolvedSessionId }, null, 2),
      );
      process.stdout.write(outputFile + "\n");
    } else {
      process.stdout.write(parsed.response + "\n");
    }
  } catch (err) {
    // Resume might fail if no session exists — signal with exit code 1
    process.stderr.write(`ERROR: ${err.message}\n`);
    process.exit(1);
  }
}

// ── Main ────────────────────────────────────────────────────────────────────────

const args = parseArgs(process.argv.slice(2));
const command = args._[0];

if (!command || args.help) {
  process.stderr.write(`opencode-companion v${VERSION} — Structured output + session resume for OpenCode CLI

Usage: opencode-companion.mjs <command> [options]

Commands:
  task      Run a prompt as a new OpenCode task (JSON structured output)
  review    Run a code review via OpenCode
  resume    Resume a previous OpenCode session with a new prompt

Options:
  --prompt TEXT         Prompt text (required for task/resume)
  --cwd DIR             Working directory (default: cwd)
  --output FILE         Write output to file (default: stdout)
  --model MODEL         Override model (format: provider/model)
  --timeout SECS        Max seconds to wait (default: 360)
  --session-id ID       Session ID for resume (default: last used)
  --opencode-bin PATH   Path to opencode binary
  --no-json             Disable JSON output format

Exit codes:
  0  Success
  1  Runtime error
  2  OpenCode CLI not available (caller should fall back)
`);
  process.exit(0);
}

switch (command) {
  case "task":
    await cmdTask(args);
    break;
  case "review":
    await cmdReview(args);
    break;
  case "resume":
    await cmdResume(args);
    break;
  default:
    process.stderr.write(`Unknown command: ${command}\n`);
    process.exit(1);
}
