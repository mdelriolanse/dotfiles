/**
 * Wiki hooks: omp port of the Claude Code wiki hooks in claude/settings.json.
 * Runs the same scripts (claude/hooks/wiki-*.sh), feeding them Claude-shaped JSON:
 *   UserPromptSubmit      -> before_agent_start   wiki-objection.sh (related ADRs/incidents)
 *   UserPromptExpansion   -> input + before_agent_start   wiki-context.sh (user typed /review etc.)
 *   PreToolUse[Skill]     -> tool_result on read skill://<review>   wiki-context.sh
 *   Stop                  -> session_stop   wiki-capture.sh (nag to log decisions)
 * The scripts no-op outside repos with docs/INDEX.md.
 */
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { realpathSync } from "node:fs";
import { join } from "node:path";

// extensions/ is symlinked from ~/.omp/agent; resolve back into the dotfiles repo.
const HOOKS = join(realpathSync(import.meta.dir), "../../claude/hooks");
const REVIEW = /^(?:[\w-]+:)?(code-review|review|review-graph|dev-graph|deep-review|resolve-review)$/;

async function run(script: string, payload: object, timeoutMs: number): Promise<any> {
	try {
		const p = Bun.spawn(["bash", join(HOOKS, script)], {
			stdin: new Blob([JSON.stringify(payload)]),
			stdout: "pipe",
			stderr: "ignore",
			timeout: timeoutMs,
		});
		const out = (await new Response(p.stdout).text()).trim();
		await p.exited;
		return out ? JSON.parse(out) : null;
	} catch {
		return null;
	}
}

function text(msg: any): string {
	const c = msg?.content;
	if (typeof c === "string") return c;
	return Array.isArray(c) ? c.filter((p: any) => p.type === "text").map((p: any) => p.text).join("\n") : "";
}

export default function wikiHooks(pi: ExtensionAPI) {
	let typed: string | undefined; // raw user input; before_agent_start only sees the skill-expanded text

	pi.on("input", async (event) => {
		typed = event.text;
	});

	pi.on("before_agent_start", async (event, ctx) => {
		const raw = typed ?? event.prompt;
		typed = undefined;
		const notes: string[] = [];

		const obj = await run("wiki-objection.sh", { prompt: raw, cwd: ctx.cwd }, 5_000);
		if (obj?.hookSpecificOutput?.additionalContext) notes.push(obj.hookSpecificOutput.additionalContext);

		const cmd = raw.trim().match(/^\/(?:skill:)?(\S+)/)?.[1];
		if (cmd && REVIEW.test(cmd)) {
			const r = await run("wiki-context.sh", { hook_event_name: "UserPromptExpansion", command_name: cmd, cwd: ctx.cwd }, 10_000);
			if (r?.hookSpecificOutput?.additionalContext) notes.push(r.hookSpecificOutput.additionalContext);
		}

		if (!notes.length) return;
		return {
			message: {
				customType: "wiki-context",
				content: notes.map((t) => ({ type: "text" as const, text: t })),
				display: "hidden",
			},
		};
	});

	// The model loads a skill by reading skill://<name>; append the wiki to a review skill's body.
	pi.on("tool_result", async (event, ctx) => {
		if (event.toolName !== "read" || event.isError) return;
		const skill = String(event.input.path ?? "").match(/^skill:\/\/([^/\s]+)\/?$/)?.[1];
		if (!skill || !REVIEW.test(skill)) return;
		const r = await run("wiki-context.sh", { hook_event_name: "PreToolUse", tool_input: { skill }, cwd: ctx.cwd }, 10_000);
		const add = r?.hookSpecificOutput?.additionalContext;
		if (add) return { content: [...event.content, { type: "text", text: add }] };
	});

	pi.on("session_stop", async (event, ctx) => {
		const last = text(event.last_assistant_message);
		if (!last) return;
		const r = await run(
			"wiki-capture.sh",
			{ stop_hook_active: event.stop_hook_active, cwd: ctx.cwd, last_assistant_message: last },
			60_000,
		);
		if (r?.decision === "block") return { decision: "block", reason: r.reason };
	});
}
