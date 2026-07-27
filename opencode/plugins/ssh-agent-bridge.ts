/**
 * Inject VDI-forwarded SSH_AUTH_SOCK into OpenCode shell executions.
 * Logic lives in ~/.ssh/agent-env.sh (shared with bashrc / BASH_ENV).
 */
import type { Plugin } from "@opencode-ai/plugin";
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

const AGENT_ENV = join(homedir(), ".ssh/agent-env.sh");

function resolveAgentSock(): string | undefined {
  if (!existsSync(AGENT_ENV)) return process.env.SSH_AUTH_SOCK;
  try {
    const sock = execFileSync("bash", ["-c", `. "${AGENT_ENV}" && printf '%s' "$SSH_AUTH_SOCK"`], {
      encoding: "utf8",
      env: process.env,
    }).trim();
    return sock || undefined;
  } catch {
    return process.env.SSH_AUTH_SOCK;
  }
}

export const SshAgentBridge: Plugin = async () => ({
  "shell.env": async (_input, output) => {
    const sock = resolveAgentSock();
    if (sock) output.env.SSH_AUTH_SOCK = sock;
  },
});

export default SshAgentBridge;
