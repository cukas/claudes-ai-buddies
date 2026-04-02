#!/usr/bin/env node
// gemini-companion.mjs — Structured output + session resume wrapper for Gemini CLI.
// Zero dependencies. Uses Gemini's --output-format json and --resume flags.
// Subcommands: task, review, resume
// Falls back gracefully if JSON output not available (exit code 2).

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
  const stateFile = join(dir, "gemini-sessions.json");
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
  const stateFile = join(dir, "gemini-sessions.json");
  try {
    return JSON.parse(readFileSync(stateFile, "utf8"));
  } catch {
    return null;
  }
}

// ── Find gemini binary ──────────────────────────────────────────────────────────

function findGeminiSync() {
  try {
    return execSync("which gemini", { encoding: "utf8", stdio: "pipe" }).trim();
  } catch {
    const paths = [
      join(process.env.HOME || "", ".local/bin/gemini"),
      "/usr/local/bin/gemini",
    ];
    for (const p of paths) {
      if (existsSync(p)) return p;
    }
    return null;
  }
}

// ── Run Gemini CLI ──────────────────────────────────────────────────────────────

function runGemini(geminiBin, cliArgs, cwd, timeoutMs) {
  return new Promise((resolve, reject) => {
    const proc = spawn(geminiBin, cliArgs, {
      cwd,
      stdio: ["pipe", "pipe", "pipe"],
      env: { ...process.env },
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
        reject(new Error(`Gemini exited with code ${code}: ${stderr}`));
      }
    });

    proc.on("error", (err) => {
      clearTimeout(timer);
      reject(err);
    });

    // Close stdin immediately — headless mode doesn't need input
    proc.stdin.end();
  });
}

// ── Parse Gemini JSON output ────────────────────────────────────────────────────

function parseGeminiOutput(stdout) {
  // Gemini JSON output may have non-JSON lines before the actual JSON
  // (e.g., "YOLO mode is enabled..." warnings on stderr, but sometimes on stdout too)
  const lines = stdout.split("\n");

  // Try to find the JSON object — it starts with '{'
  let jsonStr = "";
  let inJson = false;
  let braceCount = 0;

  for (const line of lines) {
    if (!inJson && line.trim().startsWith("{")) {
      inJson = true;
    }
    if (inJson) {
      jsonStr += line + "\n";
      braceCount += (line.match(/{/g) || []).length;
      braceCount -= (line.match(/}/g) || []).length;
      if (braceCount <= 0) break;
    }
  }

  if (jsonStr) {
    try {
      return JSON.parse(jsonStr);
    } catch {}
  }

  // Fallback: return raw text
  return { response: stdout, session_id: null, stats: null };
}

// ── Subcommands ─────────────────────────────────────────────────────────────────

async function cmdTask(args) {
  const prompt = args.prompt;
  if (!prompt) {
    process.stderr.write("ERROR: --prompt is required\n");
    process.exit(1);
  }

  const geminiBin = args["gemini-bin"] || findGeminiSync();
  if (!geminiBin) {
    process.stderr.write("ERROR: gemini CLI not found\n");
    process.exit(2);
  }

  const cwd = args.cwd || process.cwd();
  const timeout = parseInt(args.timeout || "360", 10) * 1000;

  const cliArgs = [
    "-p", prompt,
    "--output-format", "json",
    "--sandbox",
    "--approval-mode", "yolo",
  ];
  if (args.model) cliArgs.push("--model", args.model);

  try {
    const { stdout } = await runGemini(geminiBin, cliArgs, cwd, timeout);
    const parsed = parseGeminiOutput(stdout);

    const responseText = parsed.response || "";
    const sessionId = parsed.session_id || null;

    // Save session for potential resume
    if (sessionId) {
      saveSessionState(sessionId, {
        prompt: prompt.substring(0, 200),
        model: args.model,
      });
    }

    // Write output
    const outputFile = args.output;
    if (outputFile) {
      writeFileSync(outputFile, responseText);
      const metaFile = outputFile.replace(/\.md$/, ".meta.json");
      writeFileSync(
        metaFile,
        JSON.stringify(
          {
            sessionId,
            stats: parsed.stats || null,
          },
          null,
          2,
        ),
      );
      process.stdout.write(outputFile + "\n");
    } else {
      process.stdout.write(responseText + "\n");
    }
  } catch (err) {
    process.stderr.write(`ERROR: ${err.message}\n`);
    process.exit(1);
  }
}

async function cmdReview(args) {
  // Build review prompt — Gemini doesn't have native review like Codex,
  // but we can pass the review target info as part of the prompt
  const prompt = args.prompt || "Review the uncommitted changes for bugs, logic errors, and code quality issues.";
  args.prompt = prompt;
  return cmdTask(args);
}

async function cmdResume(args) {
  const prompt = args.prompt;
  if (!prompt) {
    process.stderr.write("ERROR: --prompt is required\n");
    process.exit(1);
  }

  const geminiBin = args["gemini-bin"] || findGeminiSync();
  if (!geminiBin) {
    process.stderr.write("ERROR: gemini CLI not found\n");
    process.exit(2);
  }

  const cwd = args.cwd || process.cwd();
  const timeout = parseInt(args.timeout || "360", 10) * 1000;

  const cliArgs = [
    "-p", prompt,
    "--output-format", "json",
    "--sandbox",
    "--approval-mode", "yolo",
    "--resume", "latest",
  ];
  if (args.model) cliArgs.push("--model", args.model);

  try {
    const { stdout } = await runGemini(geminiBin, cliArgs, cwd, timeout);
    const parsed = parseGeminiOutput(stdout);

    const responseText = parsed.response || "";
    const sessionId = parsed.session_id || null;

    if (sessionId) {
      saveSessionState(sessionId, {
        prompt: prompt.substring(0, 200),
        model: args.model,
        resumed: true,
      });
    }

    const outputFile = args.output;
    if (outputFile) {
      writeFileSync(outputFile, responseText);
      const metaFile = outputFile.replace(/\.md$/, ".meta.json");
      writeFileSync(
        metaFile,
        JSON.stringify({ sessionId, stats: parsed.stats || null }, null, 2),
      );
      process.stdout.write(outputFile + "\n");
    } else {
      process.stdout.write(responseText + "\n");
    }
  } catch (err) {
    process.stderr.write(`ERROR: ${err.message}\n`);
    process.exit(1);
  }
}

// ── Main ────────────────────────────────────────────────────────────────────────

const args = parseArgs(process.argv.slice(2));
const command = args._[0];

if (!command || args.help) {
  process.stderr.write(`gemini-companion v${VERSION} — Structured output + session resume for Gemini CLI

Usage: gemini-companion.mjs <command> [options]

Commands:
  task      Run a prompt as a new Gemini task (JSON structured output)
  review    Run a code review via Gemini
  resume    Resume the latest Gemini session with a new prompt

Options:
  --prompt TEXT         Prompt text (required for task/resume)
  --cwd DIR             Working directory (default: cwd)
  --output FILE         Write output to file (default: stdout)
  --model MODEL         Override Gemini model
  --timeout SECS        Max seconds to wait (default: 360)
  --gemini-bin PATH     Path to gemini binary

Exit codes:
  0  Success
  1  Runtime error
  2  Gemini CLI not available (caller should fall back)
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
