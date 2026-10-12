/**
 * Persist the last-used model across sessions.
 *
 * On session end (quit or /new) it records the active model to a small state
 * file. When a fresh session starts it restores that model, so a new session
 * continues on whatever you last used instead of pi's built-in provider default.
 *
 * Nothing is hardcoded: the state file only holds whatever model was active
 * when the previous session ended. State lives outside settings.json so it
 * does not churn the dotfiles-tracked config.
 *
 * An explicit `pi --model ...` at launch wins and skips restoration.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const AGENT_DIR = process.env.PI_AGENT_DIR?.trim() || join(homedir(), ".pi", "agent");
const STATE_FILE = join(AGENT_DIR, "last-model.json");

type ModelRef = { provider: string; id: string };

function launchedWithExplicitModel(): boolean {
	return process.argv.some((arg) => arg === "--model" || arg === "-m" || arg.startsWith("--model="));
}

function readLast(): ModelRef | undefined {
	try {
		const data = JSON.parse(readFileSync(STATE_FILE, "utf8"));
		if (typeof data?.provider === "string" && typeof data?.id === "string") {
			return { provider: data.provider, id: data.id };
		}
	} catch {
		// No usable state yet.
	}
	return undefined;
}

function writeLast(model: ModelRef): void {
	try {
		mkdirSync(AGENT_DIR, { recursive: true });
		writeFileSync(STATE_FILE, `${JSON.stringify({ provider: model.provider, id: model.id }, null, 2)}\n`);
	} catch {
		// Best effort: never break shutdown over a persistence failure.
	}
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", async (event, ctx) => {
		if (event.reason !== "startup" && event.reason !== "new") return;
		if (launchedWithExplicitModel()) return;

		const last = readLast();
		if (!last) return;
		if (ctx.model && ctx.model.provider === last.provider && ctx.model.id === last.id) return;

		const model = ctx.modelRegistry.find(last.provider, last.id);
		if (!model || !ctx.modelRegistry.hasConfiguredAuth(model)) return;

		try {
			await pi.setModel(model);
		} catch {
			// Keep pi's resolved default if the stored model can't be selected.
		}
	});

	pi.on("session_shutdown", (_event, ctx) => {
		if (ctx.model) writeLast(ctx.model);
	});
}
