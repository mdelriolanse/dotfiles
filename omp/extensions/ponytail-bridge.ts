/**
 * Ponytail bridge: omp extension that reads ponytail mode state
 * and injects the appropriate instructions into every agent turn.
 *
 * Mode reads from $PONYTAIL_DEFAULT_MODE env or ~/.config/ponytail/config.json,
 * matching the ponytail resolution order. The active-mode flag file at
 * ~/.claude/.ponytail-active is read/written for interoperability with other
 * tools (Claude Code, etc.) that share the same flag.
 *
 * Ported from the opencode plugin (~/.config/opencode/plugins/ponytail-bridge.ts)
 * to omp's ExtensionAPI:
 *   - opencode "chat.message"              -> omp pi.on("input")
 *   - opencode "experimental.chat.system.transform" -> omp pi.on("before_agent_start")
 *
 * The shared ponytail-instructions module at
 * ~/.config/opencode/ponytail/hooks/ponytail-instructions is loaded via
 * createRequire (Bun supports this). If that require fails at runtime, the
 * extension degrades gracefully (no system-prompt injection) rather than
 * crashing the session.
 */
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { createRequire } from "node:module";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

const require = createRequire(import.meta.url);

// Load the shared ponytail-instructions module. Wrapped in try/catch so a
// failure here does not prevent the extension from registering its handlers
// (the command-parse + flag-file behavior still works without it).
let getPonytailInstructions: ((mode: string) => string | null) | null = null;
try {
  const mod = require(
    join(homedir(), ".config/opencode/ponytail/hooks/ponytail-instructions"),
  );
  getPonytailInstructions = mod.getPonytailInstructions ?? null;
} catch {
  getPonytailInstructions = null;
}

const VALID_MODES = ["off", "lite", "full", "ultra", "review"] as const;
type PonytailMode = (typeof VALID_MODES)[number];

function getDefaultMode(): PonytailMode {
  // 1. Env var
  const env = process.env.PONYTAIL_DEFAULT_MODE?.toLowerCase();
  if (env && VALID_MODES.includes(env as PonytailMode)) return env as PonytailMode;
  // 2. Config file
  try {
    const xdg = process.env.XDG_CONFIG_HOME || join(homedir(), ".config");
    const configPath = join(xdg, "ponytail", "config.json");
    if (existsSync(configPath)) {
      const config = JSON.parse(readFileSync(configPath, "utf8"));
      const mode = config.defaultMode?.toLowerCase();
      if (mode && VALID_MODES.includes(mode as PonytailMode)) return mode as PonytailMode;
    }
  } catch {}
  return "full";
}

// Read the flag file written by ponytail hooks (Claude Code interoperability)
function getActiveMode(): PonytailMode | null {
  try {
    const flagPath = join(homedir(), ".claude", ".ponytail-active");
    if (existsSync(flagPath)) {
      const mode = readFileSync(flagPath, "utf8").trim().toLowerCase();
      if (mode && VALID_MODES.includes(mode as PonytailMode)) return mode as PonytailMode;
    }
  } catch {}
  return null;
}

function getEffectiveMode(): PonytailMode {
  return getActiveMode() ?? getDefaultMode();
}

// Detect /ponytail commands in user messages, update mode flag
function parsePonytailCommand(text: string): { type: "mode"; mode: PonytailMode } | { type: "ignore" } {
  const normalized = text.trim().toLowerCase();
  // Only match /ponytail as a mode toggle when followed by end-of-string or
  // whitespace + mode arg. A hyphen (e.g. /ponytail-audit) is a sub-command
  // owned by the ponytail-* skills, not a mode toggle — let it fall through.
  const match = normalized.match(/^\/ponytail(?:\s+(.*))?$/);
  if (!match) return { type: "ignore" };

  const arg = (match[1] ?? "").trim();
  if (VALID_MODES.includes(arg as PonytailMode)) {
    return { type: "mode", mode: arg as PonytailMode };
  }
  // Default: toggle to full if already off, otherwise keep current
  return { type: "mode", mode: "full" };
}

function getPonytailSystemPrompt(mode: PonytailMode): string[] {
  if (!getPonytailInstructions) return [];
  const instructions = getPonytailInstructions(mode);
  return instructions ? [instructions] : [];
}

export default function ponytailBridge(pi: ExtensionAPI) {
  // Module-level mode persists across the session.
  let currentMode = getEffectiveMode();

  // Parse /ponytail <mode> commands from user input; update the flag file
  // for interop with other tools.
  pi.on("input", async (event, _ctx) => {
    const text =
      typeof event.text === "string"
        ? event.text
        : Array.isArray(event.parts)
          ? event.parts
              .filter((p: any) => p.type === "text")
              .map((p: any) => p.text)
              .join("\n")
          : "";

    const parsed = parsePonytailCommand(text);
    if (parsed.type === "mode") {
      currentMode = parsed.mode;
      // Persist to flag file for interop with other tools
      const flagDir = join(homedir(), ".claude");
      try {
        mkdirSync(flagDir, { recursive: true });
      } catch {}
      try {
        writeFileSync(join(flagDir, ".ponytail-active"), parsed.mode);
      } catch {}
      console.log(`[ponytail-bridge] mode set to ${parsed.mode}`);
    }
  });

  // Inject ponytail system-prompt instructions before the agent starts a turn.
  // omp's before_agent_start may return a message object that is injected
  // into the conversation; we use a hidden custom message so it influences
  // the model without appearing in the visible transcript.
  pi.on("before_agent_start", async (_event, _ctx) => {
    const prompts = getPonytailSystemPrompt(currentMode);
    if (prompts.length === 0) return;
    return {
      message: {
        customType: "ponytail-system",
        content: prompts.map((text) => ({ type: "text", text })),
        display: "hidden",
        details: { mode: currentMode },
      },
    };
  });
}
