# Reference — driving Claude Code with tmux

Raw building blocks behind `scripts/tmux-drive.sh`, key names, Claude Code
launch flags, capturing full output, and troubleshooting.

## Raw tmux commands

```bash
# launch a Claude Code subagent detached, fixed size, in a directory.
# To raise scrollback, history-limit must be set as the server BOOTS (set-option
# afterwards is a no-op on the live pane), so load it via -f. Use a PRIVATE temp
# file — a predictable /tmp name is symlink/race exploitable, and tmux -f will
# run whatever it loads. (td_launch_argv does this safely for you.)
conf="$(mktemp "${TMPDIR:-/tmp}/tmux-drive.XXXXXX")"
printf 'set -g history-limit 200000\n' > "$conf"
tmux -f "$conf" new-session -d -s subject -c /work -x 220 -y 50 'claude --effort medium'
rm -f "$conf"

tmux capture-pane -t subject -p                   # print visible pane
tmux capture-pane -t subject -p -S -4000          # ... + last 4000 scrollback lines
tmux capture-pane -t subject -p -e                # ... keep ANSI escapes (don't feed -e output into approval logic)
tmux capture-pane -t subject -p -J                # ... join wrapped lines

tmux send-keys -t subject -l -- "a prompt to type" # type text verbatim (no Enter)
tmux send-keys -t subject Enter                    # press Enter (submit)
tmux send-keys -t subject 1                         # answer a permission prompt ("1. Yes")
tmux send-keys -t subject Escape                    # cancel a permission prompt
tmux send-keys -t subject C-c                       # Ctrl-C

tmux list-sessions                                # what's running
tmux kill-session -t subject                      # stop it
```

## Key names for `send-keys`

`Enter` `Escape` `Space` `Tab` `BSpace` (backspace) `Up` `Down` `Left` `Right`
`Home` `End` `PageUp` `PageDown` `C-c` (Ctrl-C) `C-d` `C-u` (clear line) `F1`..`F12`.
Plain characters (`1`, `2`, `y`, `q`) are sent as-is. Use `-l` for *literal*
text (a prompt) so it isn't interpreted as a key name.

## Polling, not sleeping

There's no portable `timeout` and `sleep` may be unavailable/blocked. Pattern:

```bash
for _ in $(seq 1 N); do
  tmux capture-pane -t subject -p | grep -qiE "READY_REGEX" && break
  perl -e 'select(undef,undef,undef,0.4)'   # ~0.4s; reliable everywhere perl exists
done
```

`nap` in the helper is `perl -e 'select(undef,undef,undef,$secs)'`, falling back
to `sleep $secs` (then `sleep 1`) only if perl is missing.

## Claude Code launch flags worth knowing

```
--model <id>                 example IDs: claude-opus-4-8, claude-sonnet-4-6  (current list — see below)
--effort <low|medium|high|xhigh|max>
--permission-mode <default|acceptEdits|plan|bypassPermissions>
--dangerously-skip-permissions     # fully autonomous; container/VM-only (runs anything as you) — see Security
--append-system-prompt "<text>"    # inject extra system instructions
--add-dir <path>                   # grant access to another directory
-p / --print                       # headless one-shot (no TUI) — see note below
--output-format <text|json|stream-json>   # (print mode) machine-readable output
```

Model IDs change with each release, so the two above are only examples — list the
models available to you with `/model` in a Claude Code session, or see the current
[Claude models overview](https://platform.claude.com/docs/en/about-claude/models/overview).

Prefer flags over in-TUI slash commands when driving via tmux: typing `/effort`
or `/clear` opens an autocomplete menu that intercepts your Enter. To reset a
subagent's context, kill and relaunch instead of `/clear`.

### Interactive (tmux) vs headless (`-p`)

- **Interactive + tmux** (this skill): a real session you watch and steer turn
  by turn; the subagent's permission prompts appear on screen and you answer
  them. Best when you want to *observe* and *supervise*.
- **Headless `claude -p "..." --output-format json`**: one-shot, returns the
  final result as text/JSON, no TUI. Cheaper and scriptable, but in `default`
  permission mode tool calls are auto-denied (no human to approve) — so for
  autonomous tool use you must add `--permission-mode bypassPermissions` (or an
  allowlist). Use when you only need the *answer*, not the live session.

## Capturing FULL output (beyond the truncated TUI)

The visible pane is small and Claude Code elides long tool output. Options:
- Widen the pane at launch: `td_launch "<cmd>" "$dir" 240 80`.
- Pull scrollback: `td_capture -S -8000` (raise `history-limit` first; the
  helper sets 200000).
- The authoritative full transcript is the subagent's session `.jsonl` under
  `~/.claude/projects/<cwd-slug>/<session-id>.jsonl` — tail/parse that for every
  tool call and result, verbatim and untruncated.

## Security

- **Launch untrusted args via argv** — `td_launch_argv "$dir" <cols> <rows> prog
  args…` (and `cc_launch`) exec a vector, no shell. `td_launch "<string>"` runs
  the string through `sh -c`, so reserve it for *trusted literals*.
- **`bypassPermissions` is container/VM-only** — it runs anything as you, with
  your credentials, tools, and network. Default to `--permission-mode default`.
- **Scraped output is attacker-shaped** — `td_capture` / `td_actions` and the
  `.jsonl` are produced by the subagent; never auto-approve based on them. Decide
  from the real permission prompt and default to deny.
- **The clean room isn't a sandbox** — the subagent still has your credentials
  and network and can read outside its cwd. Real isolation = container/VM.

## Troubleshooting

- **Empty capture right after launch** — Claude Code hasn't drawn yet. Poll for
  a ready marker (`for shortcuts`); don't capture once and assume.
- **Loop "settles" instantly on a prompt you just answered** — stale frame.
  Use `td_wait_settle` (stability check) or `nap 1` before polling.
- **`send-keys` text starting with `-` errors** — that's why the helper uses
  `send-keys -l -- "$text"` (the `--` ends option parsing).
- **The "trust this folder" prompt blocks the first launch** — `cc_launch`
  accepts it for you; by hand, send `Enter` on it.
- **Slash command didn't run** (`/effort`, `/clear` stuck in the input box) —
  the autocomplete ate the Enter. Use launch flags, or kill+relaunch to reset.
- **`disown: no current job`** — harmless; the backgrounded process already
  detached.
- **Session vanished** — `claude` exited. Check `tmux capture-pane -p` for an
  error, or run `claude` directly once to see why it died.
- **Garbled/escape-code soup in capture** — drop `-e`, and add `-J` to join
  wrapped lines.
- **Need several subagents at once** — give each a distinct `SESSION` name
  (`SESSION=a cc_launch ...`, `SESSION=b cc_launch ...`).
