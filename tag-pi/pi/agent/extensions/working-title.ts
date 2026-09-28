/**
 * Working Title Extension
 *
 * Updates the terminal (WezTerm) tab title to show:
 *   π (working)(subagents:N) - <session> - <cwd>
 *
 * - "(working)" appears while the agent is running a turn.
 * - "(subagents:N)" appears while N >= 1 agent_team steps are tracked as
 *   launched (across all active runs). N is read structurally from the
 *   agent_team "start" call's graph (or graphFile), not from result text.
 *
 * Runs are removed from tracking (dropping N back down) via, in order:
 *   1. pi-multiagent's own completion notice: a pi.sendMessage() with
 *      customType "agent_team.notice" and structured details.run.runId /
 *      details.run.terminal. Fires whenever a tracked run finishes, even if
 *      the model never checks on it.
 *   2. A fallback text scan of "run_status"/"step_result" results the model
 *      requests itself, matching a "Run: <id>" line plus "terminal=true".
 *   3. "cancel"/"cleanup" calls succeeding for a tracked runId.
 *   4. session_start/session_shutdown, which reset all tracking.
 *
 * The only other text lookup is extracting the assigned runId from a
 * "start" result, since agent_team only returns it as text.
 *
 * Auto-discovered from ~/.pi/agent/extensions/ — reload with /reload.
 */

import fs from "node:fs/promises";
import path from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

interface AgentTeamInput {
	action?: string;
	runId?: string;
	graph?: { steps?: unknown[] };
	graphFile?: string;
}

function countStepsFromGraph(input: AgentTeamInput): number | undefined {
	const steps = input.graph?.steps;
	return Array.isArray(steps) ? steps.length : undefined;
}

async function countStepsFromGraphFile(cwd: string, graphFile: string): Promise<number | undefined> {
	try {
		const raw = await fs.readFile(path.resolve(cwd, graphFile), "utf8");
		const parsed = JSON.parse(raw) as { steps?: unknown[] };
		return Array.isArray(parsed.steps) ? parsed.steps.length : undefined;
	} catch {
		return undefined;
	}
}

function extractRunId(text: string): string | undefined {
	return text.match(/\br[1-9][0-9]{0,6}\b/)?.[0];
}

// Fallback for run_status/step_result text the model requests itself:
// matches a "Run: <id>" line paired with a "terminal=true" flag anywhere
// in the same result.
function extractTerminalRunId(text: string): string | undefined {
	if (!/\bterminal=true\b/.test(text)) return undefined;
	return text.match(/\bRun:\s*(r[1-9][0-9]{0,6})\b/)?.[1];
}

function extractText(content: unknown): string {
	if (!Array.isArray(content)) return "";
	return content
		.map((part) => (part && typeof part === "object" && "text" in part ? String((part as { text: unknown }).text) : ""))
		.join("\n");
}

export default function (pi: ExtensionAPI) {
	// runId -> step count, for currently tracked (launched, not yet removed) agent_team runs.
	const activeRuns = new Map<string, number>();
	// toolCallId -> step count, captured at tool_call time, before the runId is known.
	const pendingStarts = new Map<string, number | undefined>();
	let isWorking = false;

	function subagentTotal(): number {
		let total = 0;
		for (const n of activeRuns.values()) total += n;
		return total;
	}

	function buildTitle(): string {
		const cwd = path.basename(process.cwd());
		const session = pi.getSessionName();
		const tail = session ? `${session} - ${cwd}` : cwd;

		const tags: string[] = [];
		if (isWorking) tags.push("(working)");
		const n = subagentTotal();
		if (n > 0) tags.push(`(subagents:${n})`);

		const head = tags.length ? `π ${tags.join("")}` : "π";
		return `${head} - ${tail}`;
	}

	function refresh(ctx: ExtensionContext) {
		ctx.ui.setTitle(buildTitle());
	}

	pi.on("session_start", async (_event, ctx) => {
		isWorking = false;
		activeRuns.clear();
		pendingStarts.clear();
		refresh(ctx);
	});

	pi.on("agent_start", async (_event, ctx) => {
		isWorking = true;
		refresh(ctx);
	});

	pi.on("agent_end", async (_event, ctx) => {
		isWorking = false;
		refresh(ctx);
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		isWorking = false;
		activeRuns.clear();
		pendingStarts.clear();
		refresh(ctx);
	});

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "agent_team") return;
		const input = event.input as AgentTeamInput;
		if (input.action !== "start") return;

		let steps = countStepsFromGraph(input);
		if (steps === undefined && input.graphFile) {
			steps = await countStepsFromGraphFile(ctx.cwd, input.graphFile);
		}
		pendingStarts.set(event.toolCallId, steps);
	});

	pi.on("tool_result", async (event, ctx) => {
		if (event.toolName !== "agent_team") return;
		const input = event.input as AgentTeamInput;

		if (input.action === "start") {
			const steps = pendingStarts.get(event.toolCallId);
			pendingStarts.delete(event.toolCallId);
			if (!event.isError) {
				const runId = extractRunId(extractText(event.content));
				if (runId) {
					activeRuns.set(runId, steps ?? 1);
					refresh(ctx);
				}
			}
			return;
		}

		if ((input.action === "cancel" || input.action === "cleanup") && !event.isError && input.runId) {
			if (activeRuns.delete(input.runId)) {
				refresh(ctx);
			}
			return;
		}

		if (input.action === "run_status" || input.action === "step_result") {
			const runId = extractTerminalRunId(extractText(event.content));
			if (runId && activeRuns.delete(runId)) {
				refresh(ctx);
			}
		}
	});

	pi.on("message_end", async (event, ctx) => {
		const message = event.message as { customType?: string; details?: { run?: { runId?: string; terminal?: boolean } } };
		if (message.customType !== "agent_team.notice") return;

		const run = message.details?.run;
		if (run?.terminal && run.runId && activeRuns.delete(run.runId)) {
			refresh(ctx);
		}
	});
}
