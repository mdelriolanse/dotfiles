/**
 * Ponytail bridge: OpenCode plugin that reads ponytail mode state
 * and injects the appropriate instructions into every chat session.
 *
 * Mode reads from $PONYTAIL_DEFAULT_MODE env or ~/.config/ponytail/config.json,
 * matching the ponytail resolution order.
 */
import type { Plugin } from "@opencode-ai/plugin";
import { createRequire } from "node:module";
import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

const require = createRequire(import.meta.url);
const { getPonytailInstructions } = require(
  join(homedir(), ".config/opencode/ponytail/hooks/ponytail-instructions"),
);

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
  const match = normalized.match(/^\/ponytail\s*(.*)/);
  if (!match) return { type: "ignore" };

  const arg = match[1].trim();
  if (VALID_MODES.includes(arg as PonytailMode)) {
    return { type: "mode", mode: arg as PonytailMode };
  }
  // Default: toggle to full if already off, otherwise keep current
  return { type: "mode", mode: "full" };
}

function getPonytailSystemPrompt(mode: PonytailMode): string[] {
  const instructions = getPonytailInstructions(mode);
  return instructions ? [instructions] : [];
}

export const PonytailBridge: Plugin = async () => {
  let currentMode = getEffectiveMode();

  return {
    "chat.message": async (input, output) => {
      const text = output.parts
        .filter((p) => p.type === "text")
        .map((p: any) => p.text)
        .join("\n");

      const parsed = parsePonytailCommand(text);
      if (parsed.type === "mode") {
        currentMode = parsed.mode;
        // Persist to flag file for interop with other tools
        const { writeFileSync, mkdirSync } = await import("node:fs");
        const flagDir = join(homedir(), ".claude");
        try { mkdirSync(flagDir, { recursive: true }); } catch {}
        try { writeFileSync(join(flagDir, ".ponytail-active"), parsed.mode); } catch {}
        console.log(`[ponytail-bridge] mode set to ${parsed.mode}`);
      }
    },

    "experimental.chat.system.transform": async (_input, output) => {
      const prompts = getPonytailSystemPrompt(currentMode);
      if (prompts.length > 0) {
        output.system.push(...prompts);
      }
    },
  };
};

export default PonytailBridge;
