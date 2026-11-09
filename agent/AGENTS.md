# Standing rules for omp sessions on Scott's machines

This file is linked to `~/.omp/agent/AGENTS.md` by dot-omp's `install.sh`, so it reaches every
session, including one started in `/tmp` or `~` where no project file exists. Project-level
`AGENTS.md` files add to it; they do not replace it.

## Before changing anything on a host or service

Consult the ops knowledge base first. On the LAN the `okf-knowledge` bundle is served by the
`kb-mcp` MCP server at `mini.local:8094/mcp`; the checkout on this machine is
`~/workspace/okf-knowledge` (look under `infra/`, especially `infra/runbooks/`). A runbook may
already describe the thing you are about to debug and why it is set up the way it is.

When you learn or change something about a host, write it back: a note in the relevant bundle
page, or at least a dated entry in `infra/log.md`. Session-only knowledge is lost.

## Actions that need the user's consent, every time

Ask with the `ask` tool and wait for a yes before any of these. A one-line task description is
not consent for side effects it did not name.

- Submitting a print job in any form, including test pages and "diagnostic" prints. Never pipe
  text into `lp` or `lpr`.
- Changing a print queue's device URI, PPD, or default status.
- Stopping, disabling, restarting, or masking a system service.
- Installing or removing packages.
- Editing files under `/etc`, or anything else that needs `sudo` to write.
- Deleting files you did not create in this session.

Back up a configuration file before you change it, with a dated suffix, and say where the
backup is.

## How to investigate

- Before writing a client, encoder, or parser for a protocol, check whether the standard tool
  is installed (`ipptool` for IPP, `cupsfilter` for CUPS filter chains, `dbus-send` and
  `busctl` for D-Bus, `ss` for sockets, and so on). Writing your own is the last resort.
- Keep a findings file on disk from the start of any investigation longer than a few minutes.
  Append each confirmed fact as you confirm it, with the command that confirmed it. Context
  compaction will drop detail; the file will not.
- When you find a plausible root cause, stop and say so. State the single intervention that
  would confirm it, ask whether to run it, and run that before opening another line of inquiry.
- Separate what you have confirmed from what you suspect. Say "I have not verified this" when
  you have not.
- If twenty minutes pass without a confirmed cause, stop and report: what is certain, the
  ranked hypotheses, and the next test for each. Let the user choose.

## Writing

Plain prose. No em-dashes. Do not narrate your own edits in a document; state what is.
