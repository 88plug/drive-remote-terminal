---
name: drive-remote-terminal
description: >-
  Operate and observe an interactive, full-screen terminal program (a TUI) on a REMOTE
  machine over SSH by hosting it in a tmux (or screen) session and driving it like a
  human: TYPE with `tmux send-keys` and SCREENSHOT with `tmux capture-pane -p`. The loop
  — send input, wait, capture, read, decide the next input — IS the technique. Use it
  whenever you must act as the human at a remote terminal: launching or resuming an
  interactive app (Claude Code TUI, vim, top, an installer, a REPL, a curses menu),
  answering its prompts, typing into it, or reading what's on screen over SSH. Reach for
  it the moment a plain `ssh host 'cmd'` or a pipe isn't enough because the program needs
  a real terminal/PTY and stays running. Triggers: drive the TUI on my server, answer the
  prompt in that remote session, screenshot the terminal, resume my claude session on the
  server, type into the running program over ssh, automate keystrokes. Prefer this over
  one-shot SSH for anything interactive.
---

# Driving a remote terminal as a human would

You cannot operate an interactive TUI with one-shot SSH. `ssh host 'cmd'` runs a command
and exits; piping into a full-screen program (Claude Code's interactive UI, `vim`, `top`,
a curses installer, a REPL) fails because that program needs a real terminal (a PTY),
stays running, redraws the screen, and reads keystrokes. To be the human at the keyboard
you need two things a human has: **a way to type, and eyes to see the screen.** tmux gives
you both remotely.

## The heart of this skill: the type → wait → screenshot → read loop

**This loop is the whole technique. Everything else is setup around it.** You drive a
remote TUI exactly like a human plays a turn-based game: make one move, look at the
screen, decide the next move.

- **Type (input):** `tmux send-keys -t SESSION 'what the human would type' Enter`
  — but for a **long line, send the text and `Enter` as two separate calls** (type, brief
  `sleep`, then `Enter`); a fast text+Enter burst often lets `Enter` arrive before the
  composer has settled, so the text just sits there unsubmitted (see rule 4). For arbitrary
  or untrusted text, use `send-keys -l -- "$text"` (then a separate `Enter`): `-l` forces
  *literal* characters so a payload that equals a key name (`Enter`, `Up`, `C-c`) is typed
  verbatim instead of interpreted, and `--` stops a leading `-` parsing as a flag.
- **Wait:** `sleep N` — let the app process and redraw.
- **Screenshot (observe):** `tmux capture-pane -t SESSION -p` — this prints the current
  visible screen to stdout. **`capture-pane` IS your screenshot.** It's how you see what
  a human would see.
- **Read and decide:** look at the captured screen, then send the next input.

```bash
tmux send-keys -t rc 'summarize the last error in this log' Enter
sleep 15                                  # slow op (model/network); a menu keypress needs ~2s
tmux capture-pane -t rc -p | tail -30     # <-- the screenshot: read the response off it
# ...decide the next input based on what you just saw, then repeat
```

Three rules that make this loop reliable:

1. **Always screenshot after acting.** Never send an input and assume it worked — capture
   and confirm the screen changed the way you expected before the next move. The screen is
   your only source of truth about remote state.
2. **Always wait before you screenshot.** The pane updates asynchronously; capture too
   early and you read a stale or half-drawn frame and make the wrong next move. Tune the
   sleep to the action: ~1–3s for a keystroke/menu move, ~12–20s for a model response,
   network call, or app boot.
3. **If the screen isn't what you expected, screenshot again after a longer wait — do NOT
   re-send the input.** Double-sending keystrokes is the #1 way to desync/corrupt a TUI.
   Give it more time and re-capture first.
4. **If your screenshot shows your typed text still sitting in the input box with no
   spinner/response, it wasn't submitted — send a standalone `Enter` to submit it.** This
   is the common failure when text and `Enter` were sent together too fast. Sending a lone
   `Enter` to submit already-typed text is fine and is NOT the same as re-typing the input
   (which rule 3 warns against). Verified in practice: a long prompt sat unsent until a
   separate `Enter` submitted it, after which the TUI ran its tools and responded.
5. **Confirm the program actually launched before you send ANY input — this is both a
   correctness and a SAFETY rule.** After the launch command, screenshot and verify the
   program's UI is really on screen (its prompt, menu, or buffer). If it failed to start —
   not installed, wrong path, crashed, permission denied — you'll instead see a shell
   prompt or an error, and **every keystroke you then send falls through to the shell,
   where typed text + `Enter` EXECUTES AS A SHELL COMMAND.** That can be destructive
   (imagine your "input" happening to be `rm ...` or any command). Never fire a scripted
   key sequence blind; gate it on a screenshot that confirms you're inside the program.
   Cheap pre-check: `command -v <prog>` (or `which <prog>`) before launching, so you don't
   assume a tool like `vim`/`htop` exists on that box. Learned the hard way: `vim` wasn't
   installed on a host, so `i`, the text, and `:wq` leaked to the shell.

`capture-pane -p` prints the whole visible pane; pipe through `tail -N` to focus on the
bottom (where prompts and latest output live), or `grep -v '^[[:space:]]*$'` to drop blank
lines. To read output that scrolled off, capture scrollback: `capture-pane -p -S -300`.
See `references/tmux-keys.md` for the full key + capture-pane reference.

## Answering prompts (the loop in action)

TUIs gate on prompts — trust dialogs, "are you sure?", menu selections, login fields.
**Screenshot first to SEE the prompt, then send the matching input, then screenshot again
to confirm it advanced.** This is just the loop applied to a decision point.

```
# screenshot shows:  ❯ 1. Yes, I trust this folder   2. No, exit   (Enter to confirm)
tmux send-keys -t rc '1' Enter            # type the choice
sleep 6                                   # wait
tmux capture-pane -t rc -p | tail -20     # screenshot: confirm we're now in the app
```

Numbered menu → send the number then `Enter`. Yes/no → send the highlighted choice.
Text field → send the text then `Enter`. Navigate with `Up`/`Down`/`Tab` and screenshot
to see the highlight move.

## Setup: start the session, then run the loop

```bash
tmux kill-session -t rc 2>/dev/null            # clean any prior session of this name
tmux new-session -d -s rc -x 220 -y 50         # detached; wide + tall so the screen isn't truncated
# set up the environment the program needs, THEN launch it (see env gotchas below)
tmux send-keys -t rc 'export PATH=$HOME/.local/bin:$PATH; cd /path/to/project; clear' Enter
sleep 1
tmux send-keys -t rc 'theprogram --its-flags' Enter
sleep 14                                       # boot time, then screenshot:
tmux capture-pane -t rc -p | tail -25
# ...now you're in the type → wait → screenshot loop.
```

Pick a generous pane size (`-x 220 -y 50`). TUIs reflow to the pane, so a cramped pane
truncates the very screen you're trying to read in your screenshots.

## When tmux is NOT needed

- **Non-interactive / one-shot** (read a file, run a build, tail a log, a tool with a
  batch/`--print` mode like `claude -p "..."`): just use `ssh host 'cmd'`. No tmux, no
  loop. `claude -p` returns text headless; only the interactive `claude` TUI needs tmux.
- **Interactive / stays on screen / has prompts**: use the type → wait → screenshot loop.

## SSH + auth, and the heredoc rule

When a step needs several remote commands, **don't** cram them into one
`ssh host 'bash -lc "..."'` — nested quoting breaks, and a vicious gotcha is that
**parentheses inside an `echo` string abort `bash -lc`** with a syntax error. Instead,
write a small script via a quoted heredoc, run it, remove it:

```bash
sshpass -p "$PW" ssh -o StrictHostKeyChecking=no user@host "cat > /tmp/step.sh <<'EOF'
# real multi-line bash — quoting is sane, parens are fine
tmux send-keys -t rc '1' Enter
sleep 6
tmux capture-pane -t rc -p | tail -20
EOF
bash /tmp/step.sh; rm -f /tmp/step.sh"
```

The quoted delimiter `<<'EOF'` stops `$var`/backtick expansion so the script arrives
verbatim. `sshpass -p` supplies a password non-interactively (fine for the user's own
boxes when that's what they've given you; otherwise prefer keys).

## Environment gotchas (these cause the most confusion)

A command run via `ssh host 'cmd'` or `bash -c` is a **non-login, non-interactive** shell
— it does **not** source `~/.bashrc`/`~/.bash_profile`. So:

- **PATH may be missing `~/.local/bin`** → `theprogram` "command not found" even though
  it's installed. Use the full path or `export PATH=$HOME/.local/bin:$PATH` first.
- **Env vars exported in `.bashrc` won't be present.** If the program's behavior depends
  on one (proxy URL, API base, token), set it explicitly in the tmux pane before launch.
- A program in tmux inherits the env of **the pane/shell that launched it** — not your
  SSH command's env unless you exported it in that pane.

Verify what a *running* process actually sees (ground truth) from `/proc`:

```bash
tr '\0' '\n' < /proc/PID/environ | grep -E 'PATH|THE_VAR_YOU_CARE_ABOUT'
```

For `systemctl --user` over SSH, first `export XDG_RUNTIME_DIR=/run/user/$(id -u)`.

## Don't disturb running work

Acting as the human means being careful — real work and live processes are at stake.

- **Observe before you touch.** Screenshot, read logs/transcripts, understand state. Don't
  kill/restart a process to "see what happens" — that can destroy in-flight work.
- **Don't double-open a session.** Before resuming/opening something that may already be
  running, confirm nothing live holds it: `pgrep`/`ps`, and which files a process has open
  (`ls -l /proc/PID/fd`). Attaching two instances to one session/file can corrupt it.
- **Prefer the lossless path.** If a program persists its state (e.g. a session
  transcript), relaunching/resuming loses nothing; mutating shared config other live
  processes read is risky.

## Going further (heavy automation, sync, alternatives)

The loop above is enough for most jobs. When you're driving a lot, want to stop guessing
`sleep` durations, or aren't sure tmux is even the right tool, see
`references/advanced-and-ssh.md`. Highlights (all doc-verified):
- **SSH connection reuse** (`ControlMaster auto` + `ControlPath` + `ControlPersist`) — the
  biggest speedup for a send-keys/capture loop: every call reuses one authenticated
  connection. And **don't pass `-t`** to your `send-keys`/`capture-pane` calls (a PTY adds
  noise that can corrupt the capture); reserve `-t`/`-tt` only for attaching to *watch*.
- **Deterministic sync instead of `sleep`** when driving a shell: append
  `; tmux wait-for -S done` to the command you send and block on `tmux wait-for done`; or use
  `remain-on-exit` + `#{pane_dead_status}` for one-shot exit codes.
- **Idempotent session + env**: `tmux has-session -t NAME 2>/dev/null || tmux new-session -d -s NAME -x 220 -y 50`,
  started via `ssh host 'bash -lc "…"'` so panes inherit a real login PATH/env. Target by stable
  IDs. (Don't use `new-session -A` headlessly — it attaches when the session exists and needs a
  PTY; verified to fail over a non-PTY ssh call.)
- **Right tool? / no tmux on the box?** Prompt-driven/line-oriented programs (REPLs,
  password/y-n prompts) are more robust with `expect`/`pexpect` (deterministic expect-then-send,
  no sleep-guessing); full-screen TUIs are tmux's job. If **tmux isn't installed**, GNU `screen`
  is a fully capable first-class substitute — see **`references/screen.md`** for the verified
  playbook (raw-byte key table since screen has no symbolic key names, the ~750-byte `stuff`
  limit + `readreg`/`paste`, `hardcopy` capture, and the sentinel-file run-and-wait).

## Hand back to the human

You drove it detached; the human can take over anytime by attaching to the same tmux
session from their own terminal on that box:

```
tmux attach -t rc
```

Tell them the session name and the state you left it in. When it's no longer needed,
`tmux kill-session -t rc` — but ask first if it's hosting the user's work.

## Worked example (the loop, end to end)

```bash
# SETUP: detached, well-sized session with the right env, launch the TUI
tmux kill-session -t rc 2>/dev/null
tmux new-session -d -s rc -x 220 -y 50
tmux send-keys -t rc 'export ANTHROPIC_BASE_URL=http://127.0.0.1:9099; cd ~/project; clear' Enter
sleep 1
tmux send-keys -t rc 'claude --dangerously-skip-permissions --resume <id>' Enter
sleep 16

# SCREENSHOT: see a trust prompt
tmux capture-pane -t rc -p | tail -25     # shows: ❯ 1. Yes, I trust this folder ...

# TYPE the answer → WAIT → SCREENSHOT to confirm
tmux send-keys -t rc '1' Enter
sleep 8
tmux capture-pane -t rc -p | tail -20     # now inside the app

# TYPE a real instruction → WAIT (model is slow) → SCREENSHOT the answer
tmux send-keys -t rc 'what is 7 times 6?' Enter
sleep 15
tmux capture-pane -t rc -p | tail -10     # the response is on the screen
```

That type → wait → screenshot → read rhythm, with the environment set correctly before
launch, is the whole skill.
