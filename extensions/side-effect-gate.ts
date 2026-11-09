// side-effect-gate: ask before shell commands that reach outside the working tree.
//
// Linked to ~/.omp/agent/extensions/side-effect-gate.ts by dot-omp's install.sh. It runs in
// every approval mode, yolo included, because a tool_call handler fires before approval.
// With a UI it asks once per command; without one (print mode, headless) it blocks and
// tells the model to ask the user with the `ask` tool instead.
//
// Why: a 2026-11-08 printer-debugging session on BladeRunner14 ran in yolo mode and sent
// nine print jobs, changed a queue URI and ran sudo 245 times without a prompt. The
// user's standing rules live in agent/AGENTS.md; this is the mechanical half.

type Verdict = { label: string; pattern: RegExp };

// Each entry names the category shown in the prompt and the command shape that trips it.
// Patterns run against each pipeline stage and each `;`/`&&`/`||` segment of the command.
export const GATES: Verdict[] = [
	{ label: "submit a print job", pattern: /^\s*(sudo\s+)?(lp|lpr)(\s|$)/ },
	{ label: "change a print queue", pattern: /^\s*(sudo\s+)?(lpadmin|cupsenable|cupsdisable|cupsaccept|cupsreject)(\s|$)/ },
	{ label: "control a system service", pattern: /^\s*(sudo\s+)?systemctl\s+(?!--user\b)(?!status|show|list|is-|cat)\S/ },
	{ label: "install or remove packages", pattern: /^\s*(sudo\s+)?(apt|apt-get|dpkg|snap|flatpak|pip3?|npm|cargo)\s+(install|remove|purge|uninstall|autoremove|-i)/ },
	{ label: "write as root", pattern: /^\s*sudo\s+(?!-n\s+true)(?!(cat|ls|grep|head|tail|stat|find|journalctl|lpstat|systemctl\s+(status|show|list|is-|cat)|cupsfilter|ipptool|strace|ss|lsof|dmesg)\b)\S/ },
];

export function splitSegments(command: string): string[] {
	return command
		.split(/\n|;|&&|\|\||\|/)
		.map((s) => s.trim())
		.filter(Boolean);
}

export function match(command: string): string | undefined {
	for (const seg of splitSegments(command)) {
		for (const g of GATES) if (g.pattern.test(seg)) return g.label;
	}
	return undefined;
}

export default function sideEffectGate(pi: any) {
	pi.on("tool_call", async (event: any, ctx: any) => {
		if (event.toolName !== "bash") return;
		const command = event.input?.command;
		if (typeof command !== "string") return;
		const label = match(command);
		if (!label) return;
		const reason =
			`This command would ${label}. The standing rules (AGENTS.md) require the user's ` +
			`consent first. Use the \`ask\` tool to ask, and run it only after a yes.`;
		if (!ctx?.hasUI || !ctx.ui?.confirm) return { block: true, reason };
		const ok = await ctx.ui.confirm(`Allow omp to ${label}?`, command);
		if (ok) return;
		return { block: true, reason: `The user declined to ${label}. ${reason}` };
	});
}
