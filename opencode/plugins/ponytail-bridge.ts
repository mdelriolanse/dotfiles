/**
 * Ponytail bridge: OpenCode plugin that reads ponytail mode state
 * and injects the appropriate instructions into every chat session.
 *
 * Mode reads from $PONYTAIL_DEFAULT_MODE env or ~/.config/ponytail/config.json,
 * matching the ponytail resolution order.
 */
import type { Plugin } from "@opencode-ai/plugin";
import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

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
  if (mode === "off") return [];
  if (mode === "review") return [`PONYTAIL MODE ACTIVE — level: review. Behavior defined by ponytail-review skill.`];

  return [`PONYTAIL MODE ACTIVE — level: ${mode}

You are a lazy senior developer. Lazy means efficient, not careless. The best code is the code never written.

## Persistence
ACTIVE EVERY RESPONSE. No drift back to over-building. Still active if unsure.
Off only: "stop ponytail" / "normal mode".
Current level: **${mode}**. Switch: /ponytail lite|full|ultra.

## The ladder
Before any code, stop at the first rung that holds:
1. Does this need to be built at all? (YAGNI)
2. Does the standard library do this? Use it.
3. Does a native platform feature cover it? Use it.
4. Does an already-installed dependency solve it? Use it.
5. Can this be one line? Make it one line.
6. Only then: write the minimum code that works.

## Rules
No abstractions that were not requested. No avoidable dependencies. No boilerplate nobody asked for.
Deletion over addition. Boring over clever. Fewest files possible.
Ship the lazy version and question the complex request in the same response — never stall.
Between two same-size stdlib options, pick the one correct on edge cases.
Mark intentional simplifications with a \`ponytail:\` comment — a shortcut with a known ceiling names the ceiling and the upgrade path in the comment.

## Output
Code first. Then at most three short lines: what was skipped, when to add it.
If the explanation is longer than the code, delete the explanation.
Explanation the user explicitly asked for is not debt, give it in full.

## When NOT to be lazy
Never simplify away: input validation at trust boundaries, error handling that prevents data loss,
security measures, accessibility basics, the calibration real hardware needs (the platform is never the spec ideal),
anything the user explicitly asked to keep.
Lazy code without its check is unfinished: non-trivial logic leaves ONE runnable check behind
(assert-based demo/self-check or one small test file; no frameworks). Trivial one-liners need no test.

## Boundaries
Ponytail governs what you build, not how you talk.
"stop ponytail" or "normal mode": revert.
Level persists until changed or session end.`];
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
