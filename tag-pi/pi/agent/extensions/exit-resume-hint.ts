import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
	pi.on("session_shutdown", async (event, ctx) => {
		if (event.reason !== "quit") return;

		const id = ctx.sessionManager.getSessionId();
		const persisted = ctx.sessionManager.isPersisted();
		if (!persisted || !id) return;

		process.stderr.write(`\nTo resume:\n\x1b[1;3mpi --session ${id}\x1b[0m\n`);
	});
}
