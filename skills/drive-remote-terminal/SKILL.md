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
   early and you read a stale or half-drawn frame and make the wrong next move. A fixed
   `sleep` is fine for a fast keystroke/menu move (~1–3s); for anything with variable
   latency (a model turn, a build, a boot) **don't hard-code one big sleep — poll** (see
   "Wait by polling" below).
3. **If the screen isn't what you expected, screenshot again after a longer wait — do NOT
   re-send the input.** Double-sending keystrokes is the #1 way to desync/corrupt a TUI.
   Give it more time and re-capture first. **The same trap fires when the screen looks
   *unchanged*:** an apparent "nothing happened" often means your capture beat the redraw,
   not that your input was a no-op — treat an unexpected no-change with the same suspicion
   (wait longer, re-capture) before concluding anything or re-sending.
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
   installed on a host, so `i`, the text, and `:wq` leaked to the shell. In an unattended
   single-`ssh` drive (see the gotcha below), make this an **assert-or-abort** *inside* the
   script — `capture | grep -q '<ready-marker>' || exit 1` before the first real
   `send-keys` — so a failed launch aborts instead of firing your key sequence into the
   shell. (Run the `command -v` pre-check in the *same* PATH the launch will use, and use
   `pgrep -x name`, never `pgrep -f name`, for "is it already up?" — `-f` self-matches your
   own ssh/bash command line.)
6. **Gate that launch-check on a string UNIQUE to the program's READY/input state — never
   on its name or banner, which often ALSO appear in its startup dialogs.** A program's
   title/logo usually renders on its splash, trust, and confirm screens *and* on its ready
   screen — so matching the app name can falsely report "ready" while a dialog is still up,
   and your next keystrokes then fire into that dialog instead of the input. Match the
   actual ready marker: the input prompt/composer, a menu's selectable rows, an editor's
   mode line — something that does NOT render during a confirm/onboarding screen. (Verified
   this session: matching a TUI's banner text caught its trust-folder dialog as "ready", so
   the input went to the wrong place.) Bare prompt glyphs (`>`, `❯`, `$`) are just as unsafe
   a token — they decorate splashes and menus too; anchor on the glyph *plus* ready-only
   chrome (a hint line, a token counter). And exclude status-row chatter from your match:
   a `focus-events off · add 'set -g focus-events on'…` hint is cosmetic tmux noise, never
   an error to "fix" — but it lives on the same bottom row as real ready markers.

`capture-pane -p` prints the whole visible pane; pipe through `tail -N` to focus on the
bottom (where prompts and latest output live), or `grep -v '^[[:space:]]*$'` to drop blank
lines. Add **`-J`** to rejoin a long line that wrapped to the pane width — otherwise one
logical line (a wide rule, a path, a status row) arrives as ragged fragments that break
your `grep`. Captures strip ANSI escapes by default (good — keeps matching clean); add `-e`
only when you must assert on colour. To read output that scrolled off, capture scrollback:
`capture-pane -p -S -300` — and reach for it **the moment a long op finished and the visible
tail looks truncated or empty**, because the result is now history, not the viewport. (A
full-screen app that has *exited* leaves nothing in the normal-buffer scrollback either —
capture it *while it's still running*.) An **empty capture, or an empty `grep` over one, is
NOT proof of absence** — re-capture the raw pane with no filter and no `2>/dev/null` (which
can hide the real error) before acting on "nothing's there". See `references/tmux-keys.md`
for the full key + capture-pane reference.

### Wait by polling (beats a guessed sleep)

For variable-latency work, poll instead of guessing: capture → test for a marker → small
`sleep` → repeat, under an overall ceiling. Match a **busy** marker disappearing (a
spinner / "working…" / "esc to interrupt" line) or a **ready** marker appearing — not a
duration. Require **two consecutive idle reads** before declaring done (the UI can flash
idle for a beat before work actually starts):

```bash
idle=0
for i in $(seq 1 40); do                          # ceiling ~40×3s=2min — size to the SLOW path
  if tmux capture-pane -t rc -p | grep -q '<busy-marker>'; then idle=0
  else idle=$((idle+1)); [ "$idle" -ge 2 ] && break; fi
  sleep 3
done
tmux capture-pane -t rc -p | tail -20
```

Size the ceiling to the worst case (cold model load, slow mirror, busy host — real waits
run from tens of seconds to minutes) and make re-entry resume, not restart. This replaces
the escalating-blind-sleep antipattern (`sleep 25` → "still spinning" → `sleep 30` →
`sleep 30` …). Fixed `sleep` stays only for fast, deterministic keystroke/menu moves.

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

**First-launch gauntlet (common to many TUIs):** a program's *first* run — or its first
run in a new directory/profile — often gates the real UI behind one or more one-time
screens: a trust / "do you trust this folder?" prompt, an onboarding or "what's new"
welcome, a theme or login picker. Clear each (screenshot → answer → screenshot) before
sending real input. **Tell a modal gate from a non-modal overlay:** a trust/login/theme
prompt is modal — it swallows your keystrokes, so you must answer it first; an
informational "welcome / what's new / tips" panel usually sits *above an already-active
input composer* and does not block — if the composer is present and focused in the same
capture, just type. Decide by whether the real input prompt is reachable, not by the banner
(rule 6). After answering any prompt, screenshot and confirm the *expected next state* (the
dialog advanced / the app went busy) — if your "answer" instead just echoed into a composer
or scrolled into the shell, the gate wasn't where you thought. Flags that skip *permission*
gating don't necessarily skip these *first-run* prompts; to avoid the gauntlet entirely,
launch in a directory/profile the program has already initialised. A fixed `launch → clear
prompts → type → read` flow is cleanest as a single in-session script (see the next gotcha).

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

## Gotcha: the tmux server vanished between SSH calls ("no server running")

If you drive with **one fresh `ssh host '…'` per step**, the tmux *server* can be killed
the instant the SSH session that started it closes — your next call greets you with
`no server running on /tmp/tmux-1000/default`, and every step after silently no-ops
(keystrokes go nowhere). Cause: systemd-logind with `KillUserProcesses=yes` (the default
on many distros) reaps all of a user's session-scope processes — including that tmux
server — on logout when the user has no lingering. **Verified in practice this session: a
multi-call drive died exactly this way mid-run**, after the launch screenshot had already
succeeded — so it looks like it's working, then the next SSH call finds nothing.

Three fixes — pick one:
- **Simplest & most reliable for a fixed sequence: do the entire drive inside ONE `ssh`
  invocation.** Put the launch + every send-keys/sleep/capture into a single heredoc script
  and run it over one connection. The server lives as long as that one session, which spans
  the whole drive. (This is also why a one-shot `launch → answer prompts → type → read`
  flow is best written as a single in-session script.)
- **Keep the connection alive across calls** with SSH multiplexing: `ControlMaster auto` +
  a `ControlPath` + `ControlPersist 5m`. Every send-keys/capture reuses the one live
  session, so the server is never orphaned — and it's much faster (no re-auth per call).
- **Make the server outlive the session**: run `loginctl enable-linger "$USER"` once, or
  start tmux escaped from the session scope:
  `systemd-run --user --scope tmux new-session -d -s rc …`.

Reach for ControlPersist (not single-script) only when you need a genuine
look-decide-look loop whose later moves depend on what earlier screenshots showed.

## When tmux is NOT needed

- **Non-interactive / one-shot** (read a file, run a build, tail a log, or any tool invoked
  in a batch / `--print` / headless mode that returns its output and exits): just use
  `ssh host 'cmd'`. No tmux, no loop. Only a program that stays running and redraws a
  full-screen UI needs the tmux loop.
- **Interactive / stays on screen / has prompts**: use the type → wait → screenshot loop.
- **A long job that just needs to RUN unattended** (you'll read its logfile, not watch a
  UI): do NOT wrap it in `tmux new-session -d` over per-call SSH — that server dies with the
  SSH session and silently takes the job with it (verified: repeated `no server running`,
  the job never persisted). Launch it genuinely detached — `nohup cmd >log 2>&1 &`,
  `setsid`, `systemd-run --user`, or `docker exec -d` — and poll the logfile. tmux is for
  *interactive driving*, not background persistence.

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

**Two sharp traps with that pattern:**
- The quoted `<<'EOF'` only stops the **remote** shell from expanding — but the whole
  heredoc sits inside the **outer double-quoted** `ssh "…"` arg, which your **local** shell
  expands *first*. So any `$VAR`, `$(…)`, `` `…` `` you want the *remote* side to evaluate
  must be backslash-escaped (`\$HOME`, `\$(id -u)`), and a bare `$$` there is the *local*
  PID (useless for a unique remote temp name — use `mktemp` remotely). Cleanest escape-free
  alternative: **pipe the script over stdin — `ssh host 'bash -s' < script.sh`** (or
  single-quote the outer arg) — then nothing takes a local-expansion pass.
- For scripted (non-interactive) ssh steps add `-o BatchMode=yes -o ConnectTimeout=15` and
  wrap the call in `timeout 30`: `BatchMode` makes auth fail *fast* instead of hanging on a
  password/passphrase prompt a script can't answer (the classic "the drive froze"). Prefer
  `StrictHostKeyChecking=accept-new` over `=no` — it auto-trusts a first-seen host yet still
  refuses a *changed* key (recover a legitimately changed one with `ssh-keygen -R host`).
  Don't combine `BatchMode=yes` with `sshpass` (sshpass must feed the prompt).

## Environment gotchas (these cause the most confusion)

A command run via `ssh host 'cmd'` or `bash -c` is a **non-login, non-interactive** shell
— it does **not** source `~/.bashrc`/`~/.bash_profile`. So:

- **PATH may be missing `~/.local/bin`** → `theprogram` "command not found" even though
  it's installed. Use the full path or `export PATH=$HOME/.local/bin:$PATH` first.
- **Env vars exported in `.bashrc` won't be present** — and worse, **the export can be IN
  `.bashrc` and still not reach you**: the standard top-of-file non-interactive guard
  (`case $- in *i*) ;; *) return;; esac`) `return`s before the export line for a
  `bash -lc`/non-interactive ssh shell. So "but it's in my `.bashrc`" does not fix it. Set
  the var explicitly in the tmux pane before launch, or put the binary/var on a location
  already on the base PATH (e.g. symlink into `~/.local/bin`).
- A program in tmux inherits the env of **the pane/shell that launched it** — not your
  SSH command's env unless you exported it in that pane.
- **A program started by the systemd *user manager* or the GUI session ignores both
  `.bashrc` and your tmux `export`.** Set it for the manager (`systemctl --user
  set-environment VAR=…`, or a `~/.config/environment.d/<name>.conf` drop-in), and verify
  what a *freshly-spawned* managed process will actually see with
  `systemd-run --user --wait --pipe /usr/bin/env | grep VAR`.

Verify what a *running* process actually sees (ground truth) from `/proc` — pick the PID
with `pgrep -x name` (not `-f`, which self-matches your ssh/bash line) and tolerate it
vanishing mid-read:

```bash
tr '\0' '\n' < /proc/$(pgrep -x theprogram | head -1)/environ 2>/dev/null | grep -E 'PATH|THE_VAR'
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
  noise that can corrupt the capture); reserve `-t`/`-tt` only for attaching to *watch* —
  and from a non-TTY driver that attach needs **`-tt`** (a single `-t` silently refuses to
  allocate a PTY). Add `ServerAliveInterval 30` so a long-idle multiplexed master isn't
  dropped between bursts.
- **Deterministic sync instead of `sleep`** when driving a shell: append
  `; tmux wait-for -S done` to the command you send and block on `tmux wait-for done`; or use
  `remain-on-exit` + `#{pane_dead_status}` for one-shot exit codes.
- **Idempotent session + env**: prefer `tmux new-session -A -d -s NAME -x 220 -y 50`
  (create-or-reuse) over `has-session || new-session`. It's the bare *attach* (`-A` alone)
  that needs a PTY and fails over non-PTY ssh — adding `-d` (or `-A -D` to also boot a stale
  attached client) keeps it detached, so it never attaches and works headlessly. Start it
  via `ssh host 'bash -lc "…"'` so panes inherit a login PATH/env; target by stable IDs.
  Running several jobs at once? Give **each its own uniquely-named session** and poll with
  `tmux has-session -t NAME 2>/dev/null && echo alive || echo dead` — one session per unit
  of work designs the wrong-pane-targeting problem out of existence.
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
tmux send-keys -t rc 'export APP_API_BASE=http://127.0.0.1:9099; cd ~/project; clear' Enter
sleep 1
tmux send-keys -t rc 'theprogram --its-flags' Enter
sleep 16

# SCREENSHOT: a first-run prompt may be up (trust/onboarding)
tmux capture-pane -t rc -p | tail -25     # e.g. shows: ❯ 1. Yes, I trust this folder ...

# TYPE the answer → WAIT → SCREENSHOT to confirm it advanced
tmux send-keys -t rc '1' Enter
sleep 8
tmux capture-pane -t rc -p | tail -20     # confirm the real input prompt is now on screen

# TYPE a real instruction → WAIT (slow op) → SCREENSHOT the result
tmux send-keys -t rc 'the task the human would type' Enter
sleep 15
tmux capture-pane -t rc -p | tail -10     # the result is on the screen
```

That type → wait → screenshot → read rhythm, with the environment set correctly before
launch, is the whole skill.
