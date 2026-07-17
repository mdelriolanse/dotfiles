/**
 * Inject VDI-forwarded SSH_AUTH_SOCK into omp shell executions.
 * Logic lives in ~/.ssh/agent-env.sh (shared with bashrc / BASH_ENV).
 *
 * Ported from the opencode plugin (~/.config/opencode/plugins/ssh-agent-bridge.ts).
 * opencode's "shell.env" hook has no omp equivalent; instead we resolve the
 * socket once at session_start and set process.env.SSH_AUTH_SOCK. Every
 * subsequent `bash` tool call inherits the process env, producing the same
 * effect as opencode's per-shell injection.
 */
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

const AGENT_ENV = join(homedir(), ".ssh/agent-env.sh");

function resolveAgentSock(): string | undefined {
  if (!existsSync(AGENT_ENV)) return process.env.SSH_AUTH_SOCK;
  try {
    const sock = execFileSync(
      "bash",
      ["-c", `. "${AGENT_ENV}" && printf '%s' "$SSH_AUTH_SOCK"`],
      {
        encoding: "utf8",
        env: process.env,
      },
    ).trim();
    return sock || undefined;
  } catch {
    return process.env.SSH_AUTH_SOCK;
  }
}
export default function sshAgentBridge(pi: ExtensionAPI) {
  pi.on("session_start", async (_event, _ctx) => {
    const sock = resolveAgentSock();
    if (sock) process.env.SSH_AUTH_SOCK = sock;
  });
}
