#!/usr/bin/env node
// codex-companion.mjs — Lean JSONRPC client for Codex app-server protocol.
// Zero dependencies. Spawns `codex app-server` over stdio, speaks line-delimited JSONRPC.
// Subcommands: task, review, resume
// Falls back gracefully if app-server is unavailable (exit code 2 = not supported).

import { spawn, execSync } from "node:child_process";
import { createInterface } from "node:readline";
import { writeFileSync, readFileSync, mkdirSync, existsSync } from "node:fs";
import { join, resolve } from "node:path";

// ── Constants ───────────────────────────────────────────────────────────────────

const VERSION = "1.0.0";
const INIT_TIMEOUT_MS = 8000;
const TURN_TIMEOUT_MS = 600000; // 10 minutes max per turn
const CLIENT_NAME = "claudes-ai-buddies";

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

// ── JSONRPC Client ──────────────────────────────────────────────────────────────

class CodexAppServer {
  constructor(codexBin, cwd) {
    this.codexBin = codexBin;
    this.cwd = cwd;
    this.nextId = 1;
    this.pending = new Map(); // id -> { resolve, reject, timer }
    this.notifications = [];
    this.threadId = null;
    this.turnId = null;
    this.items = [];
    this.agentMessages = [];
    this.turnCompleted = null;
    this.turnError = null;
    this.proc = null;
    this.debug = process.env.AI_BUDDIES_DEBUG === "true";
  }

  log(...args) {
    if (this.debug) process.stderr.write(`[companion] ${args.join(" ")}\n`);
  }

  async start() {
    return new Promise((resolveStart, rejectStart) => {
      this.proc = spawn(this.codexBin, ["app-server"], {
        stdio: ["pipe", "pipe", "pipe"],
        cwd: this.cwd,
      });

      this.proc.on("error", (err) => {
        rejectStart(new Error(`Failed to spawn codex app-server: ${err.message}`));
      });

      this.proc.on("exit", (code) => {
        this.log(`app-server exited with code ${code}`);
        // Reject all pending requests
        for (const [id, p] of this.pending) {
          clearTimeout(p.timer);
          p.reject(new Error(`app-server exited (code ${code})`));
        }
        this.pending.clear();
      });

      // Ignore stderr (Codex logs debug info there)
      this.proc.stderr.on("data", (d) => {
        this.log("stderr:", d.toString().trim());
      });

      // Line-delimited JSONRPC parsing
      const rl = createInterface({ input: this.proc.stdout });
      rl.on("line", (line) => {
        if (!line.trim()) return;
        let msg;
        try {
          msg = JSON.parse(line);
        } catch {
          this.log("parse error:", line.substring(0, 200));
          return;
        }
        this._handleMessage(msg);
      });

      // Start with a short delay to let the process spin up
      setTimeout(() => resolveStart(), 100);
    });
  }

  _handleMessage(msg) {
    // Response to a request we sent
    if (msg.id !== undefined && this.pending.has(msg.id)) {
      const p = this.pending.get(msg.id);
      this.pending.delete(msg.id);
      clearTimeout(p.timer);
      if (msg.error) {
        p.reject(new Error(`RPC error ${msg.error.code}: ${msg.error.message}`));
      } else {
        p.resolve(msg.result);
      }
      return;
    }

    // Server notification
    if (msg.method) {
      this.notifications.push(msg);
      this._handleNotification(msg);
    }
  }

  _handleNotification(msg) {
    const { method, params } = msg;

    switch (method) {
      case "thread/started":
        this.log("thread started:", params?.thread?.id);
        break;

      case "turn/started":
        this.turnId = params?.turn?.id;
        this.log("turn started:", this.turnId);
        break;

      case "turn/completed":
        this.turnCompleted = params?.turn;
        this.log("turn completed:", params?.turn?.id, "status:", params?.turn?.status);
        break;

      case "item/started":
        this.log("item started:", params?.item?.type);
        break;

      case "item/completed":
        if (params?.item) {
          this.items.push(params.item);
          if (params.item.type === "agentMessage") {
            this.agentMessages.push(params.item.text);
          }
          if (params.item.type === "enteredReviewMode") {
            this.agentMessages.push(params.item.review);
          }
          this.log("item completed:", params.item.type);
        }
        break;

      case "error":
        this.turnError = params;
        this.log("error:", JSON.stringify(params));
        break;
    }
  }

  send(method, params) {
    const id = this.nextId++;
    const timeout = method === "initialize" ? INIT_TIMEOUT_MS : TURN_TIMEOUT_MS;

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Timeout waiting for response to ${method} (${timeout}ms)`));
      }, timeout);

      this.pending.set(id, { resolve, reject, timer });
      const msg = JSON.stringify({ jsonrpc: "2.0", id, method, params });
      this.log("send:", method);
      this.proc.stdin.write(msg + "\n");
    });
  }

  notify(method, params) {
    const msg = params
      ? JSON.stringify({ jsonrpc: "2.0", method, params })
      : JSON.stringify({ jsonrpc: "2.0", method });
    this.proc.stdin.write(msg + "\n");
  }

  async initialize() {
    const result = await this.send("initialize", {
      clientInfo: { name: CLIENT_NAME, title: "Claude's AI Buddies", version: VERSION },
      capabilities: null,
    });
    this.notify("initialized");
    this.log("initialized:", result.userAgent);
    return result;
  }

  async startThread(opts = {}) {
    const params = {
      cwd: opts.cwd || this.cwd,
      approvalPolicy: "never",
      sandbox: opts.sandbox || "workspace-write",
      ephemeral: opts.ephemeral !== false,
      model: opts.model || undefined,
      experimentalRawEvents: false,
      persistExtendedHistory: !opts.ephemeral,
    };
    const result = await this.send("thread/start", params);
    this.threadId = result.thread.id;
    this.log("thread:", this.threadId, "model:", result.model);
    return result;
  }

  async resumeThread(threadId, opts = {}) {
    const params = {
      threadId,
      cwd: opts.cwd || this.cwd,
      model: opts.model || undefined,
      persistExtendedHistory: true,
    };
    const result = await this.send("thread/resume", params);
    this.threadId = result.thread.id;
    this.log("resumed thread:", this.threadId);
    return result;
  }

  async startTurn(prompt, opts = {}) {
    // Reset per-turn state
    this.items = [];
    this.agentMessages = [];
    this.turnCompleted = null;
    this.turnError = null;
    this.turnId = null;

    const params = {
      threadId: this.threadId,
      input: [{ type: "text", text: prompt, text_elements: [] }],
    };
    if (opts.model) params.model = opts.model;
    if (opts.outputSchema) params.outputSchema = opts.outputSchema;

    const result = await this.send("turn/start", params);
    this.turnId = result?.id || this.turnId;
    return result;
  }

  async startReview(target, opts = {}) {
    // Reset per-turn state
    this.items = [];
    this.agentMessages = [];
    this.turnCompleted = null;
    this.turnError = null;

    const params = {
      threadId: this.threadId,
      target,
    };

    const result = await this.send("review/start", params);
    return result;
  }

  async waitForTurnComplete(timeoutMs) {
    const deadline = Date.now() + (timeoutMs || TURN_TIMEOUT_MS);
    return new Promise((resolve, reject) => {
      const check = () => {
        if (this.turnCompleted) {
          resolve(this.turnCompleted);
          return;
        }
        if (this.turnError) {
          reject(new Error(`Turn error: ${JSON.stringify(this.turnError)}`));
          return;
        }
        if (Date.now() > deadline) {
          // Try to interrupt the turn
          if (this.threadId && this.turnId) {
            this.send("turn/interrupt", {
              threadId: this.threadId,
              turnId: this.turnId,
            }).catch(() => {});
          }
          reject(new Error("Turn timed out"));
          return;
        }
        setTimeout(check, 100);
      };
      check();
    });
  }

  getOutput() {
    // Collect all agent messages as the primary output
    const text = this.agentMessages.join("\n\n");

    // Collect structured data from items
    const fileChanges = this.items
      .filter((i) => i.type === "fileChange")
      .map((i) => ({
        changes: i.changes,
        status: i.status,
      }));

    const commands = this.items
      .filter((i) => i.type === "commandExecution")
      .map((i) => ({
        command: i.command,
        exitCode: i.exitCode,
        output: i.aggregatedOutput,
      }));

    return { text, fileChanges, commands, threadId: this.threadId };
  }

  kill() {
    if (this.proc && !this.proc.killed) {
      try {
        // Kill process group to clean up all children
        process.kill(-this.proc.pid, "SIGTERM");
      } catch {
        this.proc.kill("SIGTERM");
      }
    }
  }
}

// ── Session state persistence ───────────────────────────────────────────────────

function getSessionDir() {
  const sessionId = process.env.CLAUDE_SESSION_ID || "default";
  const dir = join("/tmp", `ai-buddies-${sessionId}`);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  return dir;
}

function saveThreadState(threadId, meta) {
  const dir = getSessionDir();
  const stateFile = join(dir, "codex-threads.json");
  let state = {};
  try {
    state = JSON.parse(readFileSync(stateFile, "utf8"));
  } catch {}
  state.lastThreadId = threadId;
  state.threads = state.threads || {};
  state.threads[threadId] = { ...meta, updatedAt: Date.now() };
  writeFileSync(stateFile, JSON.stringify(state, null, 2));
}

function loadThreadState() {
  const dir = getSessionDir();
  const stateFile = join(dir, "codex-threads.json");
  try {
    return JSON.parse(readFileSync(stateFile, "utf8"));
  } catch {
    return null;
  }
}

// ── Find codex binary ───────────────────────────────────────────────────────────

function findCodexSync() {
  try {
    return execSync("which codex", { encoding: "utf8", stdio: "pipe" }).trim();
  } catch {
    // Search common paths
    const paths = [
      join(process.env.HOME || "", ".local/bin/codex"),
      "/usr/local/bin/codex",
    ];
    for (const p of paths) {
      if (existsSync(p)) return p;
    }
    return null;
  }
}

// ── Subcommands ─────────────────────────────────────────────────────────────────

async function cmdTask(args) {
  const prompt = args.prompt;
  if (!prompt) {
    process.stderr.write("ERROR: --prompt is required\n");
    process.exit(1);
  }

  const codexBin = args["codex-bin"] || findCodexSync();
  if (!codexBin) {
    process.stderr.write("ERROR: codex CLI not found\n");
    process.exit(2);
  }

  const cwd = args.cwd || process.cwd();
  const timeout = parseInt(args.timeout || "600", 10) * 1000;

  const server = new CodexAppServer(codexBin, cwd);
  try {
    await server.start();
    await server.initialize();

    const threadOpts = {
      cwd,
      model: args.model || undefined,
      sandbox: args.sandbox || "workspace-write",
      ephemeral: args.ephemeral !== "false",
    };
    await server.startThread(threadOpts);
    await server.startTurn(prompt);
    await server.waitForTurnComplete(timeout);

    const output = server.getOutput();

    // Save thread state for potential resume
    if (!threadOpts.ephemeral) {
      saveThreadState(output.threadId, {
        prompt: prompt.substring(0, 200),
        model: args.model,
      });
    }

    // Write output
    const outputFile = args.output;
    if (outputFile) {
      writeFileSync(outputFile, output.text);
      // Write structured data alongside
      const metaFile = outputFile.replace(/\.md$/, ".meta.json");
      writeFileSync(
        metaFile,
        JSON.stringify(
          {
            threadId: output.threadId,
            fileChanges: output.fileChanges,
            commands: output.commands,
          },
          null,
          2,
        ),
      );
      process.stdout.write(outputFile + "\n");
    } else {
      process.stdout.write(output.text + "\n");
    }
  } catch (err) {
    process.stderr.write(`ERROR: ${err.message}\n`);
    process.exit(1);
  } finally {
    server.kill();
  }
}

async function cmdReview(args) {
  const codexBin = args["codex-bin"] || findCodexSync();
  if (!codexBin) {
    process.stderr.write("ERROR: codex CLI not found\n");
    process.exit(2);
  }

  const cwd = args.cwd || process.cwd();
  const timeout = parseInt(args.timeout || "600", 10) * 1000;
  const reviewTarget = args["review-target"] || "uncommitted";

  // Parse review target
  let target;
  if (reviewTarget === "uncommitted") {
    target = { type: "uncommittedChanges" };
  } else if (reviewTarget.startsWith("branch:")) {
    target = { type: "baseBranch", branch: reviewTarget.slice(7) };
  } else if (reviewTarget.startsWith("commit:")) {
    target = { type: "commit", sha: reviewTarget.slice(7), title: null };
  } else if (reviewTarget.startsWith("custom:")) {
    target = { type: "custom", instructions: reviewTarget.slice(7) };
  } else {
    target = { type: "uncommittedChanges" };
  }

  const server = new CodexAppServer(codexBin, cwd);
  try {
    await server.start();
    await server.initialize();

    await server.startThread({
      cwd,
      model: args.model || undefined,
      sandbox: "read-only",
      ephemeral: true,
    });

    await server.startReview(target);
    await server.waitForTurnComplete(timeout);

    const output = server.getOutput();
    const outputFile = args.output;
    if (outputFile) {
      writeFileSync(outputFile, output.text);
      process.stdout.write(outputFile + "\n");
    } else {
      process.stdout.write(output.text + "\n");
    }
  } catch (err) {
    process.stderr.write(`ERROR: ${err.message}\n`);
    process.exit(1);
  } finally {
    server.kill();
  }
}

async function cmdResume(args) {
  const prompt = args.prompt;
  if (!prompt) {
    process.stderr.write("ERROR: --prompt is required\n");
    process.exit(1);
  }

  const codexBin = args["codex-bin"] || findCodexSync();
  if (!codexBin) {
    process.stderr.write("ERROR: codex CLI not found\n");
    process.exit(2);
  }

  const cwd = args.cwd || process.cwd();
  const timeout = parseInt(args.timeout || "600", 10) * 1000;

  // Find thread to resume
  let threadId = args["thread-id"];
  if (!threadId) {
    const state = loadThreadState();
    threadId = state?.lastThreadId;
    if (!threadId) {
      process.stderr.write("ERROR: No thread to resume. Use --thread-id or run a task first.\n");
      process.exit(1);
    }
  }

  const server = new CodexAppServer(codexBin, cwd);
  try {
    await server.start();
    await server.initialize();

    await server.resumeThread(threadId, {
      cwd,
      model: args.model || undefined,
    });

    await server.startTurn(prompt);
    await server.waitForTurnComplete(timeout);

    const output = server.getOutput();
    saveThreadState(output.threadId, {
      prompt: prompt.substring(0, 200),
      model: args.model,
      resumed: true,
    });

    const outputFile = args.output;
    if (outputFile) {
      writeFileSync(outputFile, output.text);
      process.stdout.write(outputFile + "\n");
    } else {
      process.stdout.write(output.text + "\n");
    }
  } catch (err) {
    process.stderr.write(`ERROR: ${err.message}\n`);
    process.exit(1);
  } finally {
    server.kill();
  }
}

// ── Main ────────────────────────────────────────────────────────────────────────

const args = parseArgs(process.argv.slice(2));
const command = args._[0];

if (!command || args.help) {
  process.stderr.write(`codex-companion v${VERSION} — Lean JSONRPC bridge for Codex app-server

Usage: codex-companion.mjs <command> [options]

Commands:
  task      Run a prompt as a new Codex task
  review    Run a native Codex code review
  resume    Resume a previous thread with a new prompt

Options:
  --prompt TEXT         Prompt text (required for task/resume)
  --cwd DIR             Working directory (default: cwd)
  --output FILE         Write output to file (default: stdout)
  --model MODEL         Override Codex model
  --timeout SECS        Max seconds to wait (default: 600)
  --sandbox MODE        Sandbox: read-only | workspace-write | danger-full-access
  --review-target TYPE  Review target: uncommitted | branch:NAME | commit:SHA | custom:TEXT
  --thread-id ID        Thread ID for resume (default: last used)
  --codex-bin PATH      Path to codex binary
  --ephemeral BOOL      Ephemeral thread (default: true, set false for resume support)

Exit codes:
  0  Success
  1  Runtime error
  2  Codex app-server not available (caller should fall back to codex exec)
`);
  process.exit(0);
}

// Check app-server support before doing anything
try {
  execSync("codex app-server --help", { stdio: "pipe", timeout: 5000 });
} catch {
  process.stderr.write("ERROR: codex app-server not available\n");
  process.exit(2);
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
