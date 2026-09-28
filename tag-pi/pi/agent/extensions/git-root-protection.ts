/**
 * Git Root Protection Extension
 *
 * Protects the filesystem by:
 * 1. Finding the git root directory (walking up from cwd)
 * 2. Allowing writes only within git root + pi-progress/ (temp dir at git root)
 * 3. Blocking writes outside this safe zone with user confirmation
 * 4. Remembering user decisions for the session (exact path or explicit prefix)
 * 5. Auto-detecting /tmp writes and suggesting pi-progress/session-name/ redirection
 *
 * Session memory has two flavors:
 * - "Allow this exact path" — single absolute path is allowed once and forever
 *   within the session. Useful for one-off escapes.
 * - "Allow a prefix" — user types/confirms an absolute prefix; every path under
 *   it passes silently for the rest of the session. Use when you'll touch many
 *   files in a sibling repo or shared dir.
 *
 * Edge cases:
 * - If no .git found, restricts to cwd + cwd/pi-progress/ only
 * - Trusts cwd without resolving symlinks
 * - Throws exception if cwd doesn't exist
 * - Auto-creates pi-progress/ directory when needed
 * - Lazy prompts for session context name on first /tmp write
 * - Uses existing session name or asks user with suggestions from existing dirs
 * - Prompts user for permission on blocked writes, remembers choice for session
 * - Prefix overrides refuse "/" and $HOME as too broad
 */

import { existsSync, mkdirSync, readdirSync } from "node:fs";
import { resolve, dirname, sep } from "node:path";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

interface ProtectionState {
	gitRoot: string | null;
	cwd: string;
	piProgressDir: string;
	allowedPaths: Set<string>;
	userOverrides: Map<string, boolean>; // path -> allowed decision
	prefixOverrides: string[]; // absolute, normalized prefixes allowed for the session
	bashOverrides: Set<string>; // signatures of bash concerns user has allowed for session
	sessionContextName: string | null; // lazy-loaded context name for /tmp redirects
	askedForContextName: boolean; // track if we've prompted user
}

interface BashConcern {
	kind: "clone" | "cd" | "write";
	signature: string; // stable key for override memory
	detail: string; // human-readable description
	targetPath?: string; // resolved absolute path the concern points to (when applicable)
}

function findGitRoot(startPath: string): string | null {
	let current = startPath;
	const root = dirname(startPath); // filesystem root check

	while (true) {
		if (existsSync(`${current}${sep}.git`)) {
			return current;
		}

		const parent = dirname(current);
		if (parent === current) {
			// Reached filesystem root
			return null;
		}

		current = parent;
	}
}

function expandHome(p: string): string {
	if (p === "~") return process.env.HOME ?? p;
	if (p.startsWith("~/")) return (process.env.HOME ?? "") + p.slice(1);
	return p;
}

function normalizePrefix(p: string): string {
	const abs = resolve(expandHome(p));
	// Strip trailing separator (except for filesystem root).
	if (abs.length > 1 && abs.endsWith(sep)) return abs.slice(0, -1);
	return abs;
}

function isCoveredByPrefix(absPath: string, state: ProtectionState): boolean {
	for (const prefix of state.prefixOverrides) {
		if (absPath === prefix || absPath.startsWith(prefix + sep)) return true;
	}
	return false;
}

/**
 * Add a prefix to session memory. Returns null on success or a reason string
 * when the prefix is rejected. Drops existing entries that become redundant.
 */
function addPrefixOverride(state: ProtectionState, raw: string): string | null {
	if (!raw || !raw.trim()) return "empty prefix";
	const prefix = normalizePrefix(raw);

	if (prefix === sep) return "refusing to allow filesystem root";
	const home = process.env.HOME ? normalizePrefix(process.env.HOME) : null;
	if (home && prefix === home) return "refusing to allow $HOME (too broad)";

	// Already covered by an existing prefix — nothing to do.
	if (isCoveredByPrefix(prefix, state)) return null;

	// New prefix supersedes any narrower existing entries.
	state.prefixOverrides = state.prefixOverrides.filter(
		(p) => !(p === prefix || p.startsWith(prefix + sep)),
	);
	state.prefixOverrides.push(prefix);
	return null;
}

function commonAncestorDir(paths: string[]): string | null {
	if (paths.length === 0) return null;
	const split = paths.map((p) => p.split(sep));
	const first = split[0];
	const out: string[] = [];
	for (let i = 0; i < first.length; i++) {
		const seg = first[i];
		if (split.every((s) => s[i] === seg)) out.push(seg);
		else break;
	}
	if (out.length === 0) return null;
	const joined = out.join(sep);
	return joined === "" ? sep : joined;
}

function sanitizeName(input: string): string {
	return input
		.trim()
		.toLowerCase()
		.replace(/[^a-z0-9-]/g, "-") // Replace non-alphanumeric with dash
		.replace(/--+/g, "-") // Collapse multiple dashes
		.replace(/^-|-$/g, ""); // Remove leading/trailing dashes
}

function getExistingContextDirs(piProgressDir: string): string[] {
	try {
		if (!existsSync(piProgressDir)) {
			return [];
		}

		const entries = readdirSync(piProgressDir, { withFileTypes: true });
		return entries
			.filter((e) => e.isDirectory())
			.map((e) => e.name)
			.sort()
			.slice(0, 10); // Show last 10
	} catch (err) {
		return [];
	}
}

function resolveBashPath(p: string, baseCwd: string): string {
	return resolve(baseCwd, expandHome(p));
}

/**
 * Heuristic scan of a bash command string for filesystem-escape patterns.
 * Catches the common LLM-misuse cases (cd /tmp, git clone, redirects/writes
 * to absolute paths outside the safe zone). Not a sandbox — adversarial input
 * (eval, base64, variable indirection, heredocs) is out of scope.
 */
function analyzeBashCommand(cmd: string, state: ProtectionState): BashConcern[] {
	const concerns: BashConcern[] = [];
	const seen = new Set<string>();

	const push = (c: BashConcern) => {
		if (seen.has(c.signature)) return;
		seen.add(c.signature);
		concerns.push(c);
	};

	// 1. git clone — always flag (heavy op, destination is implicit cwd)
	if (/\bgit\s+clone\b/.test(cmd)) {
		push({ kind: "clone", signature: "git-clone", detail: "git clone" });
	}

	// 2. cd <path> — flag when target resolves outside safe zone
	for (const m of cmd.matchAll(/\bcd\s+(['"]?)([^\s'";&|]+)\1/g)) {
		const raw = m[2];
		// Ignore cd -, cd with no arg, cd into safe zone
		if (!raw || raw === "-") continue;
		const target = resolveBashPath(raw, state.cwd);
		if (!isPathAllowed(target, state) && !isCoveredByPrefix(target, state)) {
			push({ kind: "cd", signature: `cd:${target}`, detail: `cd ${target}`, targetPath: target });
		}
	}

	// 3. Redirections > / >> / tee to absolute paths outside safe zone
	for (const m of cmd.matchAll(/(?:>>?|\|\s*tee(?:\s+-a)?)\s+(['"]?)(\/[^\s'";&|]+)\1/g)) {
		const target = resolveBashPath(m[2], state.cwd);
		if (target === "/dev/null") continue;
		if (!isPathAllowed(target, state) && !isCoveredByPrefix(target, state)) {
			push({ kind: "write", signature: `write:${target}`, detail: `redirect → ${target}`, targetPath: target });
		}
	}

	// 4. Common write-side commands with absolute targets outside safe zone
	const writePatterns: Array<{ re: RegExp; label: string }> = [
		{ re: /\b(?:cp|mv|rsync)\s+[^|;&\n]*?(?<=\s)(\/[^\s'";&|]+)(?=\s|$)/g, label: "cp/mv/rsync to" },
		{ re: /\b(?:mkdir|touch|rm)\s+(?:-\S+\s+)*(\/[^\s'";&|]+)/g, label: "create/remove" },
		{ re: /\bcurl\s+[^|;&\n]*?-o\s+(['"]?)(\/[^\s'";&|]+)\1/g, label: "curl -o" },
		{ re: /\bwget\s+[^|;&\n]*?-O\s+(['"]?)(\/[^\s'";&|]+)\1/g, label: "wget -O" },
		{ re: /\btar\s+[^|;&\n]*?-C\s+(['"]?)(\/[^\s'";&|]+)\1/g, label: "tar -C" },
		{ re: /\bunzip\s+[^|;&\n]*?-d\s+(['"]?)(\/[^\s'";&|]+)\1/g, label: "unzip -d" },
		{ re: /\bdd\s+[^|;&\n]*?of=(['"]?)(\/[^\s'";&|]+)\1/g, label: "dd of=" },
	];

	for (const { re, label } of writePatterns) {
		for (const m of cmd.matchAll(re)) {
			const path = m[m.length - 1];
			if (!path) continue;
			const target = resolveBashPath(path, state.cwd);
			if (target === "/dev/null") continue;
			if (!isPathAllowed(target, state) && !isCoveredByPrefix(target, state)) {
				push({ kind: "write", signature: `write:${target}`, detail: `${label} ${target}`, targetPath: target });
			}
		}
	}

	return concerns;
}

function isPathAllowed(
	targetPath: string,
	state: ProtectionState,
): boolean {
	const absTarget = resolve(targetPath);

	// Check user overrides first (exact paths the user explicitly allowed).
	if (state.userOverrides.has(absTarget)) {
		return state.userOverrides.get(absTarget) ?? false;
	}

	// Session-wide prefix grants.
	if (isCoveredByPrefix(absTarget, state)) {
		return true;
	}

	// Allow pi-progress directory
	if (
		absTarget.startsWith(state.piProgressDir + sep) ||
		absTarget === state.piProgressDir
	) {
		return true;
	}

	// Allow git root and its subdirectories
	if (state.gitRoot) {
		const absGitRoot = resolve(state.gitRoot);
		if (
			absTarget.startsWith(absGitRoot + sep) ||
			absTarget === absGitRoot
		) {
			return true;
		}
	}

	// Allow cwd if no git root found
	if (!state.gitRoot) {
		const absCwd = resolve(state.cwd);
		if (absTarget.startsWith(absCwd + sep) || absTarget === absCwd) {
			return true;
		}
	}

	return false;
}

function ensurePiProgressDir(state: ProtectionState): void {
	try {
		if (!existsSync(state.piProgressDir)) {
			mkdirSync(state.piProgressDir, { recursive: true });
		}
	} catch (err) {
		console.error(
			`Warning: Could not create pi-progress directory: ${err instanceof Error ? err.message : err}`,
		);
	}
}

export default function (pi: ExtensionAPI) {
	let state: ProtectionState | null = null;

	pi.on("session_start", async (_event, ctx) => {
		// Verify cwd exists
		if (!existsSync(ctx.cwd)) {
			ctx.ui.notify(
				`Error: CWD does not exist: ${ctx.cwd}`,
				"error",
			);
			return;
		}

		// Initialize protection state
		const gitRoot = findGitRoot(ctx.cwd);
		const piProgressDir = gitRoot
			? resolve(gitRoot, "pi-progress")
			: resolve(ctx.cwd, "pi-progress");

		state = {
			gitRoot,
			cwd: ctx.cwd,
			piProgressDir,
			allowedPaths: new Set(),
			userOverrides: new Map(),
			prefixOverrides: [],
			bashOverrides: new Set(),
			sessionContextName: null,
			askedForContextName: false,
		};

		// Auto-create pi-progress directory
		ensurePiProgressDir(state);

		// Display status
		const rootDisplay = gitRoot
			? `git root: ${gitRoot}`
			: `cwd: ${ctx.cwd} (no .git found)`;
		const tempDirDisplay = gitRoot
			? `${gitRoot}/pi-progress`
			: `${ctx.cwd}/pi-progress`;
		const msg = `✅ Write protection active\n${rootDisplay}\n📁 Temp dir: ${tempDirDisplay}`;
		ctx.ui.notify(msg, "success");
	});

	pi.on("tool_call", async (event, ctx) => {
		if (!state) return;

		// Bash: scan for filesystem-escape patterns before letting the shell run.
		if (event.toolName === "bash") {
			const cmd = (event.input.command as string) ?? "";
			if (!cmd) return;

			const allConcerns = analyzeBashCommand(cmd, state);
			const concerns = allConcerns.filter(
				(c) => !state!.bashOverrides.has(c.signature),
			);
			if (concerns.length === 0) return;

			const summary = concerns.map((c) => `  • ${c.detail}`).join("\n");

			if (!ctx.hasUI) {
				return {
					block: true,
					reason:
						`Bash blocked — filesystem-escape patterns detected:\n${summary}\n` +
						`Safe zone: ${state.gitRoot ?? state.cwd} (+ pi-progress/)`,
				};
			}

			const safeZoneDesc = state.gitRoot
				? `within ${state.gitRoot} or ${state.piProgressDir}`
				: `within ${state.cwd} or ${state.piProgressDir} (no git root)`;

			const choice = await ctx.ui.select(
				`⚠️ Bash command leaves safe zone\n\n${summary}\n\nCommand:\n  ${cmd}\n\nAllowed: ${safeZoneDesc}\n\nAllow this command?`,
				[
					"✓ Yes, allow (once)",
					"✗ No, block",
					"⊕ Allow & remember exact paths for session",
					"⊕ Allow a prefix & remember for session",
				],
			);

			if (choice === "⊕ Allow & remember exact paths for session") {
				for (const c of concerns) state.bashOverrides.add(c.signature);
				return;
			}

			if (choice === "⊕ Allow a prefix & remember for session") {
				const pathConcerns = concerns.filter((c) => c.targetPath);
				if (pathConcerns.length === 0) {
					// Nothing path-shaped to base a prefix on (e.g. only `git clone`).
					// Fall back to per-signature memory.
					for (const c of concerns) state.bashOverrides.add(c.signature);
					ctx.ui.notify(
						"No path-shaped concerns to prefix; remembered signatures instead.",
						"info",
					);
					return;
				}
				const dirs = pathConcerns.map((c) => dirname(c.targetPath!));
				const suggested = commonAncestorDir(dirs) ?? dirs[0];
				const input = await ctx.ui.input(
					"Allow which prefix for the session?",
					{
						defaultValue: suggested,
						placeholder: "/absolute/path/prefix",
						description:
							"Everything at or under this path will pass silently for the rest of the session. Refuses / and $HOME.",
					},
				);
				if (!input) {
					return { block: true, reason: `Bash blocked by user:\n${summary}` };
				}
				const err = addPrefixOverride(state, input);
				if (err) {
					return { block: true, reason: `Bash blocked (bad prefix: ${err}):\n${summary}` };
				}
				ctx.ui.notify(`🔓 Session prefix added: ${normalizePrefix(input)}`, "success");
				return;
			}

			if (choice !== "✓ Yes, allow (once)") {
				return {
					block: true,
					reason: `Bash blocked by user:\n${summary}`,
				};
			}
			return;
		}

		if (event.toolName !== "write" && event.toolName !== "edit") {
			return;
		}

		const targetPath = event.input.path as string;
		const absPath = resolve(targetPath);

		// Check if allowed FIRST - paths inside cwd/git root are fine even if under /tmp
		if (isPathAllowed(targetPath, state)) {
			return;
		}

		// Detect /tmp writes and suggest pi-progress redirection (lazy)
		if (absPath.startsWith("/tmp") && !state.askedForContextName && ctx.hasUI) {
			state.askedForContextName = true;

			// Try to get existing session name or ask user
			let contextName = pi.getSessionName();

			if (!contextName) {
				// No session name set - ask user with suggestions
				const existingDirs = getExistingContextDirs(state.piProgressDir);
				const suggestions = existingDirs.length > 0
					? existingDirs
					: ["temp-work", "investigation", "debugging"];

				const choice = await ctx.ui.input(
					`Name this job for pi-progress tracking`,
					{
						defaultValue: suggestions[0] ?? "work",
						placeholder: "e.g., refactor-auth, fix-bug, investigate-issue",
						description: suggestions.length > 0
							? `Suggestions: ${suggestions.join(", ")}`
							: "Enter a name for this work session",
					},
				);

				if (choice) {
					contextName = sanitizeName(choice);
					pi.setSessionName(contextName);
				}
			}

			if (contextName) {
				state.sessionContextName = sanitizeName(contextName);
				const sessionDir = resolve(state.piProgressDir, state.sessionContextName);
				try {
					mkdirSync(sessionDir, { recursive: true });
					ctx.ui.notify(
						`📁 Using pi-progress/${state.sessionContextName}/ for temp work`,
						"info",
					);
				} catch (err) {
					console.error(`Failed to create session context dir: ${err}`);
				}
			}
		}

		// Redirect /tmp writes to pi-progress session dir
		if (
			absPath.startsWith("/tmp")
			&& state.sessionContextName
			&& (event.toolName === "write" || event.toolName === "edit")
		) {
			const relPath = absPath.slice("/tmp".length).replace(/^\//, "");
			const redirectPath = resolve(state.piProgressDir, state.sessionContextName, relPath);
			event.input.path = redirectPath;
			ctx.ui.notify(
				`📝 Redirected /tmp → pi-progress/${state.sessionContextName}/${relPath}`,
				"info",
			);
			return;
		}

		// Blocked - prompt for permission
		if (!ctx.hasUI) {
			// No UI - block by default in non-interactive mode
			return {
				block: true,
				reason: `Write blocked (outside safe zone): ${absPath}`,
			};
		}

		// Show confirmation dialog
		const safeZoneDesc = state.gitRoot
			? `within ${state.gitRoot} or ${state.piProgressDir}`
			: `within ${state.cwd} or ${state.piProgressDir} (no git root)`;

		const choice = await ctx.ui.select(
			`⚠️ Write outside safe zone\n\nTarget: ${absPath}\n\nAllowed: ${safeZoneDesc}\n\nAllow this write?`,
			[
				"✓ Yes, allow (once)",
				"✗ No, block",
				"⊕ Allow this exact path & remember for session",
				"⊕ Allow a prefix & remember for session",
			],
		);

		if (choice === "⊕ Allow this exact path & remember for session") {
			state.userOverrides.set(absPath, true);
			return;
		}

		if (choice === "⊕ Allow a prefix & remember for session") {
			const suggested = dirname(absPath);
			const input = await ctx.ui.input(
				"Allow which prefix for the session?",
				{
					defaultValue: suggested,
					placeholder: "/absolute/path/prefix",
					description:
						"Everything at or under this path will pass silently for the rest of the session. Refuses / and $HOME.",
				},
			);
			if (!input) {
				return { block: true, reason: `Write blocked by user: ${absPath}` };
			}
			const err = addPrefixOverride(state, input);
			if (err) {
				return { block: true, reason: `Write blocked (bad prefix: ${err}): ${absPath}` };
			}
			ctx.ui.notify(`🔓 Session prefix added: ${normalizePrefix(input)}`, "success");
			return;
		}

		if (choice !== "✓ Yes, allow (once)") {
			return {
				block: true,
				reason: `Write blocked by user: ${absPath}`,
			};
		}
	});
}
