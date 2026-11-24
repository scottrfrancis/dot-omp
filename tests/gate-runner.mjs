// Case table for extensions/side-effect-gate.ts, run by tests/test-install.sh.
//
// Runtime-agnostic on purpose: BladeRunner14 has bun, the macOS boxes have node. Both can
// import the TypeScript gate (bun natively; node >= 22.6 with --experimental-strip-types),
// so the expectations live in one place instead of a `bun -e` line per case that silently
// skips wherever bun is missing.
//
// GATE_TS must point at the gate source. Exit 0 = every case matched its expectation.
// Prints one line per case so a failure names the verb that regressed.

const gate = await import(process.env.GATE_TS);
const { match } = gate;

// [command, expected: "gate" (must be caught) | "free" (must not be caught)]
const cases = [
	// The 2026-11-08 printer session, unchanged expectations.
	["lp -d nowhere /etc/hostname", "gate"],
	["lpadmin -p Nowhere -E -v socket://10.0.0.9", "gate"],
	["systemctl restart cups", "gate"],
	["systemctl status cups", "free"],
	["sudo apt install wl-clipboard", "gate"],
	["ls /etc/cups", "free"],
	// ssh is auto-approved by bash.patterns, so the payload is what gets judged.
	["ssh mini sudo reboot", "gate"],
	["ssh studio systemctl restart cups", "gate"],
	["ssh mini systemctl --user restart kb", "free"],
	["ssh mini git status && git log -1", "free"],
	["ssh studio brew install gh", "gate"],
	// Package managers on both families; AGENTS.md requires consent for install/remove.
	["brew install postgresql", "gate"],
	["brew upgrade gh", "gate"],
	["brew uninstall gh", "gate"],
	["brew list --versions", "free"],
	["uv pip install httpx", "gate"],
	["uv run pytest -q", "free"],
	["npm install -g pnpm", "gate"],
	["pip3 install --user serial", "gate"],
	["cargo build --release", "free"],
	// macOS service control is the launchd half of the systemctl rule.
	["launchctl bootout gui/501/com.scott.omlx", "gate"],
	["launchctl kickstart -k gui/501/com.symless.synergy3", "gate"],
	["launchctl list | grep omlx", "free"],
	["launchctl print gui/501/com.scott.omlx", "free"],
];

let bad = 0;
for (const [command, want] of cases) {
	const label = match(command);
	const got = label ? "gate" : "free";
	if (got === want) {
		console.log(`ok   ${command}`);
	} else {
		bad++;
		console.log(`FAIL ${command} -- expected ${want}, got ${got}${label ? ` (${label})` : ""}`);
	}
}
console.log(`${cases.length - bad}/${cases.length} gate cases correct`);
process.exit(bad ? 1 : 0);
