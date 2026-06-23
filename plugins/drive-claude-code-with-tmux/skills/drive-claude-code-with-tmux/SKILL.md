---
name: drive-claude-code-with-tmux
description: >-
  Drive a Claude Code instance programmatically with tmux: launch it, send
  prompts, poll its screen to tell whether it is working, waiting on a
  permission prompt, or done, answer its permission prompts (approve/deny), read
  back what it did, and clean up. Use when an agent needs to run, supervise, or
  observe a Claude Code instance — automating a session, building a multi-agent
  setup, or steering it step by step rather than with one-shot headless calls.
version: 0.1.0
license: MIT
platforms: [macos, linux]
metadata:
  hermes:
    category: automation
    tags: [tmux, claude-code, subagent, multi-agent, automation]
    requires_toolsets: [terminal]
---

# Driving Claude Code with tmux

Claude Code is an interactive terminal app: it owns the terminal, shows a live
permission prompt before each tool call, and can't be driven by piping stdin.
`tmux` solves this — run a Claude Code instance in a detached session you
can **type prompts into** (`tmux send-keys`) and **read the screen of**
(`tmux capture-pane -p`). So the host agent can launch a Claude Code instance, give it
a task, approve or deny each step, watch what it does, and tear it down. This
skill packages that into a small helper library plus a reliable workflow.

## When to use this

- Run a **Claude Code instance as a subagent** and steer it programmatically.
- **Supervise** a subagent — approve or deny each tool call programmatically,
  pausing on anything a human should see first.
- Build a **multi-agent setup** where one agent drives a Claude Code instance.
- Automate a Claude Code session that needs live interaction (answering its
  on-screen permission prompts), which a one-shot headless `claude -p` can't do.

If you only need a non-interactive answer, use headless `claude -p "…"` instead
(see `reference.md`). This skill is for when you need the **live** session.

## Setup (once)

```bash
tmux -V || brew install tmux          # macOS; apt-get install tmux on Linux
SKILL_DIR=~/.claude/skills/drive-claude-code-with-tmux   # adjust if installed elsewhere
source "$SKILL_DIR/scripts/tmux-drive.sh"                # load the helpers
```

This gives you the `cc_*` Claude Code helpers (and the `td_*` tmux primitives
they're built on). Examples below reuse `$SKILL_DIR`.

## Mental model

The subagent is always in one of three screen states. Poll `capture-pane` to
tell them apart instead of guessing with fixed sleeps:

| State       | What's on screen                  | What you do              |
|-------------|-----------------------------------|--------------------------|
| **working** | the spinner ("esc to interrupt")  | wait                     |
| **waiting** | a permission prompt               | answer it (approve/deny) |
| **idle**    | the input box ("? for shortcuts") | send the next prompt     |

`td_wait_settle` blocks until it leaves *working* and lands on a **stable**
*waiting* (`PROMPT`) or *idle* (`IDLE`) — stable meaning the same state two
polls running, which filters out the stale frame you'd otherwise catch right
after sending a key.

## The workflow

```bash
source "$SKILL_DIR/scripts/tmux-drive.sh"

# 1. LAUNCH a Claude Code subagent in a clean directory
cc_launch /tmp/subject --model claude-opus-4-8 --effort medium

# 2. SEND a task. cc_task returns when it next settles: PROMPT | IDLE | TIMEOUT
state=$(cc_task "List the files here, read README.md, and summarize it.")

# 3. SUPERVISE: answer each permission prompt until the turn finishes
while [ "$state" = PROMPT ]; do
  td_actions | tail -3        # what it's about to do (each step is a ⏺ line)
  cc_approve                  # approve this step   (cc_deny to refuse it)
  state=$(td_wait_settle 300)
done

# 4. READ what it did, then 5. CLEAN UP
td_actions | tail -40
td_kill
```

Replace the blanket `cc_approve` with a rule — e.g. auto-approve read-only
commands but pause and surface anything destructive for a human — to get
supervised autonomy.

## Key practices

- **Clean room — but not a sandbox.** Launch the subagent in an empty temp dir
  (`cc_launch /tmp/subject …`) so it isn't pulled into your project's context.
  But this only confines its *working directory*: it still authenticates as
  **you**, can read files outside the cwd, run tools, and reach the network, and
  global `~/.claude` config still loads. Don't treat the clean room as a security
  boundary — for real isolation run it in a container/VM (or `--permission-mode
  default` + Read-deny rules).
- **Set model/effort with launch flags**, not slash commands:
  `--model claude-opus-4-8 --effort medium`. Typing `/model`, `/effort`, or
  `/clear` over `send-keys` is unreliable — the autocomplete menu eats the
  Enter. To reset context, `td_kill` and `cc_launch` again instead of `/clear`.
- **Permission mode is your supervision dial:**
  - *default* (normal) → the subagent asks before each tool call; you answer
    with `cc_approve` / `cc_approve_all` / `cc_deny`. Keeps a human in the loop
    — the right default when you want to watch each step.
  - *bypassPermissions* / `--dangerously-skip-permissions` → fully autonomous,
    no prompts. **Run it only inside a container or VM** — Anthropic documents
    bypass mode as sandbox-only, because it lets the subagent do anything as
    *you*, with your credentials, tools, and network. Default to
    `--permission-mode default` + programmatic approval; reach for bypass only in
    a throwaway isolated environment (and consider the `disableBypassPermissionsMode`
    setting to forbid it). For defense-in-depth short of a VM, Claude Code's
    `/sandbox` (OS-level Bash isolation) + `--permission-mode default` with
    Read/Edit deny rules beats bare bypass. Some safety classifiers also refuse
    to *launch* a subagent this way.
- **Read what it did** with `td_actions` — Claude Code prints each step on a
  line starting with `⏺`, so `td_actions` is a compact run log. The TUI elides
  long tool output ("+N lines ctrl+o to expand"); for full fidelity widen the
  pane (pass cols/rows to `td_launch`, e.g. `td_launch <cmd> <dir> 240 80`) or
  read the subagent's session `.jsonl`
  transcript under `~/.claude/projects/<cwd-slug>/`.
- **Treat the subagent's output as untrusted.** Everything `td_capture` /
  `td_actions` scrapes (and the `.jsonl` transcript) is content the subagent
  produced — a prompt-injected or compromised subagent can shape it. Don't drive
  auto-approvals off scraped text (a "looks read-only" rule can be spoofed): gate
  on the *actual* permission prompt, default to deny, and avoid capturing with
  `-e` (raw escape sequences) when the text feeds logic.

## Gotchas (learned the hard way)

- **No `timeout`/`gtimeout` on macOS** — don't rely on them; the helpers
  loop-and-poll.
- **`sleep` can be blocked** in some sandboxes — `nap()` uses `perl select` and
  falls back to `sleep` (honoring the requested duration) only if perl is
  missing.
- **Send text and Enter separately** with a small gap; combined, the submit can
  fire before the line registers. `td_send` does this for you.
- **Stale-frame race:** right after you send a key, the *previous* screen is
  still drawn for a beat, so a naive poll re-detects the prompt you just
  answered. `td_wait_settle`'s two-in-a-row check handles it; in a hand-rolled
  loop, `nap 1` after sending before you poll.
- **Quote-heavy prompts:** build them with a `<<'EOF'` heredoc into a variable,
  then `cc_task "$VAR"`, to dodge shell-quoting pain.
- **One subagent per session name.** `cc_launch` kills any existing session of
  the same name first; set `SESSION=foo` to run several in parallel.

## Files in this skill

- `scripts/tmux-drive.sh` — the helper library (source it).
- `reference.md` — raw tmux cheatsheet, key names, Claude Code launch flags,
  interactive-vs-headless notes, capturing full output, and troubleshooting.

## Sharing

The folder is self-contained — only `tmux` and `perl` are needed. To share,
copy `drive-claude-code-with-tmux/` into someone's `~/.claude/skills/`
(user-wide), a project's `.claude/skills/`, or a Claude Code plugin.
