# dot-omp

Shared configuration for [omp](https://omp.sh) (Oh My Pi, the terminal coding agent by can1357)
across Scott's machines. It's the omp counterpart of `dot-opencode` and follows the same idea:
shared, machine-agnostic config lives in the repo, and each machine's choices stay small and
per-machine.

omp is replacing OpenCode. Everything here was learned the hard way on the Windows box
(2026-08) and on the BladeRunner14 Linux install (2026-09); see "Gotchas".

## Layout

| Path | What it is | How it reaches omp |
|---|---|---|
| `models.yml` | Every provider: `dev-ai` (remote tier) and `llama.cpp` (local tier on Linux) | Symlinked (or copied) to `~/.omp/agent/models.yml` |
| `settings.conf` | Shared settings, such as `edit.mode replace` and the theme | Applied with `omp config set` |
| `machines/<host>-<os>.conf` | Per-machine settings, mainly `modelRoles` | Applied after `settings.conf` |
| `agent/AGENTS.md` | Standing rules for every session: consult okf-knowledge first, consent before side effects, check for the standard tool before writing one, findings file on disk | Linked to `~/.omp/agent/AGENTS.md` |
| `extensions/side-effect-gate.ts` | Asks before print jobs, queue changes, service control, package changes and root writes, in every approval mode | Linked into `~/.omp/agent/extensions/` |
| `tests/test-install.sh` | Checks `install.sh` against a stubbed `omp` and a throwaway agent dir | `tests/test-install.sh` |
| `bin/omp-local.sh` | Wrapper that starts the on-demand llama-server, runs omp, stops it after | Linked to `~/.local/bin/omp-local` (Linux/mac) |
| `tests/test-omp-local.sh` | Checks the wrapper against stubbed `systemctl`, `curl` and `omp` | `tests/test-omp-local.sh` |
| `install.sh` / `install.ps1` | Does the above; idempotent | Run after cloning and after each pull |

`~/.omp/agent/config.yml` is **not** in the repo. omp rewrites it itself (`omp config set`, the
TUI), so a symlinked copy would leave this checkout dirty. It's the same trap `dot-opencode` hit
with `package.json`. The repo holds the source of truth; `install.sh` pushes it through omp.

## Install

```bash
# omp itself (Linux, no Bun): prebuilt binary, checksum-verified
V=18.4.4; U=https://github.com/can1357/oh-my-pi/releases/download/v$V
cd /tmp && curl -fsSLO $U/omp-linux-x64 && curl -fsSLO $U/SHA256SUMS.txt
sha256sum -c --ignore-missing SHA256SUMS.txt && install -m755 omp-linux-x64 ~/.local/bin/omp

# this repo
cd ~/workspace/dot-omp && ./install.sh --dry-run && ./install.sh
omp config get modelRoles; omp config get edit.mode        # verify
```

Windows, from **pwsh 7** (Windows PowerShell 5.1 strips the quotes out of the `modelRoles` JSON
on its way to `omp.exe`): `pwsh -File .\install.ps1 -DryRun`, then `pwsh -File .\install.ps1`
(copies `models.yml`; `-Link` needs Developer Mode).

The machine file is picked as `<short hostname>-<os>`, lowercased (`bladerunner14-linux`,
`bladerunner14-windows`). Override with `--machine NAME` or `-Machine NAME`. A new machine starts
by copying the closest file in `machines/`.

## Tiers

| Tier | Provider | Where | Notes |
|---|---|---|---|
| local | `llama.cpp` | Linux laptop, `127.0.0.1:8080` | On demand: `omp-local` starts it (see below). Qwen3.6-35B-A3B MTP, about 46 t/s |
| local | `lm-studio` (built in) | Windows, `localhost:1234` | Auto-discovered; no entry needed. `qwen/qwen2.5-coder-7b` @ 32K |
| remote | `dev-ai` | `dev-ai.local:11434/v1` | The `workhorse:latest` alias. Never name a concrete dev-ai model |
| cloud | `anthropic` (built in) | Claude | `/login` in the TUI (OAuth). Not an API key |

## Standing rules and the side-effect gate

On 2026-11-08 an omp session on BladeRunner14, pointed at dev-ai and asked to fix a printer,
ran for two hours in the default `yolo` approval mode with no rules file loaded (it started in
`/tmp`, and there was no user-level `AGENTS.md`). It found the real bug by reading CUPS source,
then submitted nine print jobs as diagnostics, changed the queue's device URI without asking
and ran `sudo` 245 times, none of it prompted. About fifty pages of garbage came out of the
printer. The model's reasoning was fine; the harness had no gate. Three things changed here.

1. **`tools.approvalMode write`** in `settings.conf`. Reads run free; writes, edits and shell
   commands ask. In print mode (`omp -p`) a command that needs approval is refused with a
   message, so scripted runs such as the smoke test pass `--auto-approve` or
   `--approval-mode yolo` explicitly, and so should a session that is editing code inside a
   git repo where every change is reversible.
2. **`extensions/side-effect-gate.ts`**, a `tool_call` hook. It inspects each `bash` command
   segment for the verbs that cost the most in that session (`lp`/`lpr`, `lpadmin` and friends,
   `systemctl` on system units, package installs and removals, `sudo` with anything but a
   read-only command) and asks once per command. Without a UI it blocks and tells the model to
   use the `ask` tool. It fires before approval, so it holds in `yolo` too. Verified against
   dev-ai in print mode: `lp -d nowhere /etc/hostname` came back blocked with the reason text,
   `ls /etc/cups` ran.
3. **`agent/AGENTS.md`**, linked to `~/.omp/agent/AGENTS.md`, so it reaches sessions started
   outside any project. It carries the consent rules the gate enforces, the consult-before-acting
   rule from the ops knowledge base, and three habits for investigations: check for the standard
   tool before writing a client (that session spent fifteen minutes on a hand-written IPP encoder
   while `ipptool` was installed), keep a findings file on disk because compaction drops detail,
   and when a cause looks found, name the confirming test and ask before exploring further.

Also from that session: `compaction.handoffSaveToDisk true`, so the summaries a long session
produces can be read afterwards. Every role on the Linux machine stays local or on dev-ai;
omp is the offline tier here, and escalation to Claude happens by handing a Claude Code
session the omp transcript, outside omp. Windows is not wired yet: `install.ps1` does not
link `AGENTS.md` or the extension.
## Local tier on Linux: `omp-local`

The `llama-qwen36` user service is stopped by default and nothing starts it at login. That is
deliberate: running, it holds the dGPU, about 6.7 GB of VRAM and 23 GB of RAM, and drains the
battery. Plain `omp` with the default `llama.cpp/...` role therefore fails until the server is up.
`omp-local` is the switch:

```bash
omp-local                 # start the server if needed, run omp, stop the server when omp exits
omp-local -p "pong?"      # any omp arguments pass straight through
omp-local up              # start and wait for /health (about 10 s warm), then leave it running
omp-local down            # stop it
omp-local status          # exit 0 if the server answers
OMP_LOCAL_KEEP=1 omp-local   # leave the server running after omp exits
```

Because the machine's default role is dev-ai, which is unreachable offline, the wrapper passes
`--model llama.cpp/qwen3.6-35b-a3b-mtp` unless the arguments already carry a `--model`
(`OMP_LOCAL_MODEL` changes the default). A server that was already running when `omp-local`
started is left alone afterwards. The
manual equivalents are `systemctl --user start|stop llama-qwen36` and
`curl -sf http://127.0.0.1:8080/health`; the unit's log is `journalctl --user -u llama-qwen36`.
The wrapper is a shell script rather than an omp extension because omp discovers providers
before any extension could start a server, and because stopping the server after omp exits
needs a process outside omp.

## Gotchas

1. **`edit.mode replace` is essential** with Qwen-family models. The default `hashline` syntax had
   11 of 20 edits rejected with Qwen3.6. With `replace`: 0 of 4 failed, 14 turns instead of 36,
   165 s instead of 260 s. The 2026-09-29 smoke test on the internal Linux install passed 28/28
   with 0 edit rejections.
2. **`modelRoles` is a record.** `omp config set modelRoles.default X` fails with "Unknown
   setting"; set the whole thing as JSON, which is what the machine files do.
3. **Don't name a provider `ollama`.** An explicit `ollama` entry replaces omp's built-in ollama
   discovery, and in 17.2.9 it silently discovered zero models. The old Windows fix was the
   `OLLAMA_BASE_URL` user env var. `dev-ai` here is an explicit `openai-completions` provider
   with its one model listed, so it needs neither discovery nor the env var. Verified from Linux,
   2026-09-30: `omp -p --no-tools --model dev-ai/workhorse:latest` answered in 2.3 s.
4. **Clients name `workhorse:latest`, never a concrete model** (okf-knowledge
   `infra/ai-stack.md`). `qwen3.6:35b-a3b` disappeared from dev-ai, which broke both OpenCode's
   and omp's defaults; the alias prevents a repeat.
5. **`contextWindow` must match the server.** llama.cpp: `--ctx-size` (131072). dev-ai: the
   alias's `num_ctx` (131072).
6. **Claude Code's auto mode will not launch omp with `--auto-approve`**, even with approval;
   run such commands yourself (`! omp ...` inside Claude Code).
7. omp's agent tried `python` before `python3` on Ubuntu: `sudo apt install python-is-python3`.
   Tests need `python3-pytest` on a fresh install.
8. On an 8 GB GPU, size local context so real VRAM stays under about 7.5 GB; LM Studio's
   estimate runs low (gemma-3-4b was 1.8 GB over).

9. **omp's approval default is `yolo`.** A fresh install runs every tool call unprompted. The
   `write` mode and the side-effect gate above exist because of the 2026-11-08 printer session.
10. **A session started in `~` or `/tmp` loads no project `AGENTS.md`.** Only the user-level
    file at `~/.omp/agent/AGENTS.md` reaches it, which is why this repo ships one.
11. **Cache reads show as zero against dev-ai's vLLM.** vLLM 0.30 returns
    `prompt_tokens_details: null`, so omp cannot see prefix-cache hits and its token display
    says nothing was cached. The server's own counters (`:8000/metrics`,
    `vllm:prefix_cache_hits_total` over `vllm:prefix_cache_queries_total`) showed a 91.5 % hit
    rate on 2026-11-08. Read omp's zero as a reporting gap, not as re-prefilling 77 K tokens a
    call.
12. **No JS runtime on BladeRunner14 outside omp's bundled Bun**, so the extension has no unit
    tests; `tests/test-install.sh` checks the wiring and the live check above is the functional
    test.

## Smoke test

```bash
mkdir -p /tmp/omp-smoke && cd /tmp/omp-smoke && git init -q
omp -p --mode json --auto-approve --no-session --no-title --max-time 20m \
  "Write iso_duration.py with a parse(s) -> int seconds function and pytest tests, then run the tests and fix any failures." > ../omp-smoke.jsonl
python3 -m pytest -q
```
