#!/usr/bin/env bash
# tmux-drive.sh — drive a Claude Code instance via tmux.
#
# SOURCE it, don't execute it:
#     source /path/to/tmux-drive.sh
#
# Claude Code helpers:  cc_launch / cc_task / cc_approve / cc_approve_all / cc_deny / td_actions
# tmux primitives:      td_launch / td_send / td_key / td_capture / td_wait_for / td_wait_settle / td_kill
#
# Tune with env vars (export before sourcing, or set per call):
#   SESSION      tmux session name                (default: subject)
#   THINK_MARK   regex shown while Claude is busy  (default: the working spinner)
#   PROMPT_MARK  regex for a permission prompt     (default: Claude's prompt)
#   IDLE_MARK    regex for the input box           (default: Claude's footer)
# (The primitives are generic; override the three marks to point at another TUI.)

SESSION="${SESSION:-subject}"
THINK_MARK="${THINK_MARK:-esc to interrupt}"
PROMPT_MARK="${PROMPT_MARK:-Do you want to|don.t ask again|allow all edits}"   # matches Bash (proceed), Write (create), Edit (make this edit) prompts
IDLE_MARK="${IDLE_MARK:-for shortcuts}"

# --- portable sub-second sleep: perl, else fractional sleep, else 1s (always delays) ---
nap() { perl -e "select(undef,undef,undef,${1:-0.3})" 2>/dev/null || sleep "${1:-0.3}" 2>/dev/null || sleep 1; }

# --- read the screen ---------------------------------------------------------
# td_capture           -> visible pane
# td_capture -S -4000  -> last 4000 lines of scrollback
td_capture() { tmux capture-pane -t "$SESSION" -p "$@" 2>/dev/null; }

# Claude Code prints each action it takes on a line beginning with the bullet ⏺.
# td_actions [scrollback]  -> just those action/narration lines (a compact run log)
td_actions() { td_capture -S "${1:--6000}" | grep -E '^⏺'; }

# --- launch in a fresh detached session --------------------------------------
# td_launch_argv <workdir> <cols> <rows> <program> [args...]
#   Runs an argv VECTOR directly (tmux exec's it, no shell), so arguments can't be
#   injected. Use this whenever any argument is variable or untrusted (e.g. cc_launch).
td_launch_argv() {
  local dir="$1" cols="$2" rows="$3"; shift 3
  tmux kill-session -t "$SESSION" 2>/dev/null
  # Raise scrollback for the first pane: history-limit only applies when set as the
  # server boots, so load it from a private config via -f (a plain `set -g` afterwards
  # does NOT resize the already-created pane). Fail closed if we can't get a temp file —
  # never fall back to a predictable name, which would invite a /tmp symlink clobber.
  local conf; conf="$(mktemp "${TMPDIR:-/tmp}/tmux-drive.XXXXXX" 2>/dev/null)" || return 1
  printf 'set -g history-limit 200000\n' > "$conf" 2>/dev/null
  tmux -f "$conf" new-session -d -s "$SESSION" -c "$dir" -x "$cols" -y "$rows" "$@"
  local rc=$?
  rm -f "$conf"   # tmux reads -f at server boot (before new-session returns), so safe to remove now
  [ "$rc" -eq 0 ] || return 1
}

# td_launch "<command>" [workdir] [cols] [rows]
#   Convenience for a TRUSTED, literal command string (runs via `sh -c`, so pipes and
#   redirects work). For any variable or untrusted argument, use td_launch_argv instead.
td_launch() {
  local cmd="$1" dir="${2:-$PWD}" cols="${3:-220}" rows="${4:-50}"
  td_launch_argv "$dir" "$cols" "$rows" /bin/sh -c "$cmd"
}

# --- wait until <regex> appears on screen. returns 0 if found, 1 on timeout ---
# td_wait_for "<regex>" [timeout_s] [poll_s]
td_wait_for() {
  local re="$1" t="${2:-30}" p="${3:-0.4}" n i=0
  n=$(awk "BEGIN{d=$p+0; if(d<=0)d=0.4; print int(($t+0)/d)+1}")
  while [ "$i" -lt "$n" ]; do
    td_capture | grep -qiE "$re" && return 0
    nap "$p"; i=$((i+1))
  done
  return 1
}

# --- type literal text, then press Enter -------------------------------------
# Sending text and Enter as ONE call races; do them separately with a tiny gap.
# NOTE: control characters are stripped before sending (an embedded newline would
# otherwise submit the prompt early) — pass a single-line prompt.
# td_send "<text>"
td_send() {
  local t; t="$(printf '%s' "$1" | LC_ALL=C tr -d '[:cntrl:]')"   # drop C0 controls (newline/CR/etc.)
  tmux send-keys -t "$SESSION" -l -- "$t"
  nap 0.4
  tmux send-keys -t "$SESSION" Enter
}

# --- send raw key(s): td_key Enter | td_key Escape | td_key 2 | td_key Down Down Space ---
td_key() { tmux send-keys -t "$SESSION" "$@"; }

# --- wait until the app stops "thinking" and reaches a STABLE prompt/idle -----
# Prints PROMPT | IDLE | TIMEOUT. Requires the state to hold for two consecutive
# polls, which filters out stale frames (e.g. the just-answered prompt still on
# screen for a moment right after you send a keystroke).
# td_wait_settle [timeout_s] [poll_s]
td_wait_settle() {
  local t="${1:-180}" p="${2:-0.5}" n i=0 last="" state pane
  n=$(awk "BEGIN{d=$p+0; if(d<=0)d=0.4; print int(($t+0)/d)+1}")
  while [ "$i" -lt "$n" ]; do
    pane="$(td_capture)"
    if   printf '%s' "$pane" | grep -qiE "$THINK_MARK";  then state=THINK
    elif printf '%s' "$pane" | grep -qiE "$PROMPT_MARK"; then state=PROMPT
    elif printf '%s' "$pane" | grep -qiE "$IDLE_MARK";   then state=IDLE
    else state=OTHER; fi
    if { [ "$state" = PROMPT ] || [ "$state" = IDLE ]; } && [ "$state" = "$last" ]; then
      printf '%s\n' "$state"; return 0
    fi
    last="$state"; nap "$p"; i=$((i+1))
  done
  printf 'TIMEOUT\n'; return 1
}

# --- tear down ---------------------------------------------------------------
td_kill() { tmux kill-session -t "$SESSION" 2>/dev/null; }

# ============================ Claude Code helpers ============================

# Claude Code permission-prompt answers:
cc_approve()     { td_key 1; }       # "1. Yes"
cc_approve_all() { td_key 2; }       # "2. Yes, and don't ask again for similar commands"
cc_deny()        { td_key Escape; }  # cancel the proposed action (or `td_key 3` for "No")

# Launch a Claude Code subagent in a CLEAN directory (so it can't read your
# project files and get pulled into your context), accept the "trust this
# folder" prompt, and wait for the input box.
#   cc_launch <workdir> [extra claude flags...]
#   e.g. cc_launch /tmp/subject --model claude-opus-4-8 --effort medium
# Tip: prefer launch flags (--model/--effort/--permission-mode) over in-TUI
# slash commands (/model, /effort) — slash commands are fiddly to send via tmux
# because the autocomplete menu intercepts Enter.
cc_launch() {
  local dir="${1:-$(mktemp -d)}"; shift 2>/dev/null || true
  td_launch_argv "$dir" 220 50 claude "$@" || return 1   # argv vector — no shell, no flag injection
  if td_wait_for "trust this folder|Yes, I trust|$IDLE_MARK" 25; then
    td_capture | grep -qiE "trust this folder|Yes, I trust" && td_key Enter
  fi
  td_wait_for "$IDLE_MARK" 40
}

# Send a task/prompt to the subagent and block until it next settles.
#   cc_task "<prompt>" [timeout_s]   -> prints PROMPT | IDLE | TIMEOUT
cc_task() { td_send "$1"; nap 1; td_wait_settle "${2:-300}"; }
