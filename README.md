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
| local | `llama.cpp` | Linux laptop, `127.0.0.1:8080` | On demand: `systemctl --user start llama-qwen36`. Qwen3.6-35B-A3B MTP, about 46 t/s |
| local | `lm-studio` (built in) | Windows, `localhost:1234` | Auto-discovered; no entry needed. `qwen/qwen2.5-coder-7b` @ 32K |
| remote | `dev-ai` | `dev-ai.local:11434/v1` | The `workhorse:latest` alias. Never name a concrete dev-ai model |
| cloud | `anthropic` (built in) | Claude | `/login` in the TUI (OAuth). Not an API key |

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

## Smoke test

```bash
mkdir -p /tmp/omp-smoke && cd /tmp/omp-smoke && git init -q
omp -p --mode json --auto-approve --no-session --no-title --max-time 20m \
  "Write iso_duration.py with a parse(s) -> int seconds function and pytest tests, then run the tests and fix any failures." > ../omp-smoke.jsonl
python3 -m pytest -q
```
