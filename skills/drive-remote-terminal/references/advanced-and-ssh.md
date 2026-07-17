# Advanced: robust SSH transport, deterministic sync, and when to use something else

The core skill (type → wait → screenshot, in SKILL.md) is enough for most jobs. This file
is the upgrade path when you're doing a lot of remote driving, want to stop guessing
`sleep` durations, or are deciding whether tmux is even the right tool. All claims are from
the OpenSSH man pages (`ssh(1)`, `ssh_config(5)`, `sshpass(1)`), the tmux manual
(`tmux.1`, man.openbsd.org), the tmux Control-Mode wiki, and the expect/pexpect/screen/
util-linux docs.

## Contents
1. SSH transport: PTY rules, connection reuse, auth, environment
2. Deterministic sync — better than `sleep`
3. Robust `send-keys` and `capture-pane`
4. Targeting by ID; idempotent sessions; geometry
5. tmux control mode (advanced driver)
6. Decision guide: tmux vs expect vs screen vs recording

---

## 1. SSH transport

**PTY rules.** `ssh host 'cmd'` does NOT allocate a PTY → no `TERM` is sent, `isatty()` is
false, curses/TUI programs misrender or refuse to start. That's why you host the TUI in a
**remote tmux** and reach it with ordinary non-PTY `tmux` control calls. Reserve a PTY
(`ssh -t`, or `-tt` when ssh itself has no local TTY, e.g. inside a script/cron) ONLY for
when you actually *attach to watch* a live session.

**Key rule:** do NOT pass `-t` to your `tmux send-keys`/`capture-pane` calls. Those are
non-TTY control commands; a PTY injects escape/encoding noise that can corrupt
`capture-pane -p` output. Plain `ssh host 'tmux send-keys …'` / `ssh host 'tmux capture-pane -p …'`
needs no PTY.

**Connection reuse — the highest-impact change for a send-keys/capture loop.** Every
remote `tmux` call otherwise pays a full TCP + key-exchange + auth round trip. Multiplex:
```
# ~/.ssh/config   (mkdir -p ~/.ssh/cm && chmod 700 ~/.ssh/cm)
Host myhost
    HostName host.example.com
    User me
    ControlMaster auto
    ControlPath ~/.ssh/cm/%C
    ControlPersist 10m
    ServerAliveInterval 30
    ServerAliveCountMax 3
```
Now every subsequent command rides the existing authenticated master — no re-auth, far
lower latency. `ssh -O check host` / `ssh -O exit host` manage it.

**Auth.** Prefer public-key + agent (the `sshpass` man page itself recommends this). If you
must pass a password, use `sshpass -d` (fd) / `-f` (file) / `-e` (env) — never `-p`, which
is visible to all users in `ps`. For automation add `BatchMode=yes` (fail fast instead of
hanging on a prompt) and `StrictHostKeyChecking=accept-new` (TOFU on first contact, still
MITM-safe against *changed* keys; avoid `no`/`off`).

**Environment.** `ssh host 'cmd'` is a non-login, non-interactive shell — it sources neither
profile nor the interactive part of `.bashrc`, so PATH/env are minimal. Cleanest fix for the
tmux pattern: **start the tmux server once from a login shell**, and every pane inherits
that good env:
```
ssh host 'bash -lc "tmux has-session -t rc 2>/dev/null || tmux new-session -d -s rc -x 220 -y 50"'
```
For specific vars use `-o SetEnv=NAME=VALUE` (server must allow via `AcceptEnv`), or
`tmux new-session -e NAME=VALUE`.

## 2. Deterministic sync — better than `sleep`

`sleep` is a guess. When you're driving a **shell** in the pane, prefer event-driven sync.
Hierarchy (best first):

- **`wait-for` — have the command signal its own completion.** Append a tmux signal to what
  you send, then block on it:
  ```
  tmux send-keys -t rc -l -- 'make test; tmux wait-for -S done'
  tmux send-keys -t rc Enter
  tmux wait-for done        # blocks until 'make test' finishes — no guessing
  ```
- **One-shot exit status:** `set -g remain-on-exit on`, launch the command, then poll
  `#{pane_dead}` and read `#{pane_dead_status}` (exit code) via
  `tmux display-message -p -t rc '#{pane_dead} #{pane_dead_status}'`; reuse the pane with
  `respawn-pane`.
- **Log tailing:** `tmux pipe-pane -o -t rc 'cat >> /tmp/rc.log'` then `grep` the file for a
  sentinel string — robust against partial redraws.
- **Fallback:** capture-and-poll in a loop; fixed `sleep` only as the last resort.

Note: `wait-for`/exit-status work when a **shell command** is what's running. For a
full-screen TUI you're still reading the painted screen, so `sleep` + `capture-pane` (or a
capture-poll loop watching for an expected on-screen change) remains how you sync those.

## 3. Robust send-keys / capture-pane

- **Arbitrary text:** `tmux send-keys -t TGT -l -- "$text"` then a **separate**
  `tmux send-keys -t TGT Enter`. `-l` (literal) stops a payload that equals a key name
  (`Enter`, `Up`, `C-c`) from being reinterpreted; `--` stops a leading `-` from parsing as
  a flag. Never rely on `\n` inside the string — it's sent literally; submit with an explicit
  `Enter`.
- **Named keys** (no `-l`): `Enter Escape Tab BTab Up Down Left Right Space BSpace C-c C-d
  C-u Home End PageUp PageDown`. `send-keys -N 5 Up` repeats.
- **Capture:** `capture-pane -p` = current rendered screen (what a TUI shows). `-J` joins
  wrapped lines; `-e` includes color/attr escapes (only if you assert on them); `-S -` (and
  `-E -`) include scrollback for output that scrolled off. Don't add `-S -` for a full-screen
  TUI on the alternate screen — it has no meaningful history; capture the visible screen.

## 4. Targeting by ID; idempotent sessions; geometry

- **Use stable IDs in scripts**, not names/indexes — capture them at creation:
  `SID=$(tmux new-session -d -P -F '#{session_id}' -s rc -x 220 -y 50)`;
  `PID=$(tmux display-message -p -t rc '#{pane_id}')`. Then target `-t "$PID"`. The tmux docs
  explicitly recommend fully-qualified targets / IDs for scripts.
- **Idempotent create (headless):** `tmux has-session -t NAME 2>/dev/null || tmux new-session -d -s NAME`.
  Do NOT use `new-session -A`/`-A -D` for this — empirically (verified live) `-A` takes the
  *attach* path when the session already exists, which needs a PTY, so over a non-PTY ssh
  control call it fails with `open terminal failed: not a terminal` (rc=1). `-A` is only for the
  interactive `ssh -t … tmux new-session -A -s NAME` attach-or-create case.
- **Pin geometry** with `-x W -y H` so captures are deterministic (a detached session
  otherwise uses `default-size` 80x24, truncating output). Resize later with
  `resize-window -x W -y H`.

## 5. tmux control mode (advanced driver)

`tmux -C` / `-CC` is a text protocol: each command's output is framed
`%begin <t> <cmdnum> <flags>` … `%end`/`%error`, with a unique command number, so you get
**deterministic per-command success/failure** and async `%output`/`%window-*`/`%pane-*`
notifications instead of polling. Big win for heavy automation — but it costs a persistent
client process and a line-protocol parser, and `%output` is a raw escape stream, so you'd
*still* use `capture-pane` to read the rendered grid. Sweet spot: drive+sync via control
mode's framing/notifications, read the screen via `capture-pane`. Only reach for this when a
plain send-keys/capture loop's lack of completion signals is actually hurting.

## 6. Decision guide — is tmux even the right tool?

The governing axis (confirmed by Pexpect's own FAQ, which sends curses cases to a screen
emulator):

- **Screen-out (full-screen / curses / TUI)** — `vim`, `top`, `htop`, `less`, the Claude Code
  TUI, anything that repaints in place. The byte stream is unmatchable; you need the
  **rendered grid**. → **tmux `send-keys` + `capture-pane`** (this skill). This is the right
  and only sane choice here.
- **Prompt-in (line-oriented / prompt-driven)** — REPLs, `ssh`/`scp`/`ftp` password prompts,
  `passwd`, `fsck` y/n, CLI installers. Output is a stream ending in recognizable prompts. →
  **`expect`** (Tcl) or **`pexpect`** (Python): `expect "assword:"; send "x\r"`. Deterministic
  expect-then-send, no `sleep` guessing, branch on which pattern matched. On a minimal box
  with neither Python nor Tcl, **`empty(1)`** does expect/send from pure shell.
  Rule of thumb: *if you're `sleep`+`capture`+grepping for a stable text prompt from a
  line-oriented program, an expect tool is more robust.*

**Fallback — no tmux on the remote box?** GNU `screen` does the same job and is a first-class
alternative — see **[screen.md](screen.md)** for the full verified playbook (raw-byte key
table, the ~750-byte `stuff` limit + `readreg`/`paste` workaround, `hardcopy` capture, idempotent
sessions, and the sentinel-file run-and-wait since screen has no `wait-for`). Quick form:
`screen -dmS s bash`, `screen -S s -p 0 -X stuff $'cmd\r'` (type), `screen -S s -p 0 -X hardcopy -h /tmp/out; cat /tmp/out` (screenshot). It renders TUIs like tmux; the only costs are raw-byte
keys and file-mediated capture.

**Recording ≠ control.** `script`/`scriptreplay` (util-linux) and `asciinema` record and
replay a session for audit/debugging but **cannot inject input or branch** — use them
alongside, never instead of, a driver. (Note: input logging can capture passwords.)
