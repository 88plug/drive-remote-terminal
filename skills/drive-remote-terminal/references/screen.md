# Driving GNU `screen` (first-class alternative to tmux)

`screen` is the right host when **tmux isn't installed** (common on stock/locked-down boxes —
e.g. Ubuntu/Zorin ship `screen` but not always `tmux`). It can do everything the core loop
needs — start detached, type, screenshot, target a window, tear down — with two ergonomic
differences from tmux: **(a) no symbolic key names** (you send raw bytes), and **(b) no
stdout capture** (`hardcopy` writes a file you then read). Everything below was verified live
on GNU screen 4.06.02; cites `screen(1)` + https://www.gnu.org/software/screen/manual/screen.html.

The control verb is `screen -S NAME -p WINDOW -X <command>` — `-X` sends a command to a
running session over its socket (bypasses the `C-a` escape char entirely, so no collision
worries). **Always pass `-p 0`** (or the right window index) so you target a deterministic
window. Produce control bytes with **shell ANSI-C quoting `$'...'`** (needs bash/zsh, not
`dash` — so over SSH run inside `bash -lc`).

## The type → wait → screenshot loop, in screen

```bash
N=work
# create (idempotent — see below), then:
screen -S $N -p 0 -X stuff $'some command\r'   # TYPE (text + Enter as raw CR)
sleep 0.3                                       # WAIT (and ~0.2s before capture: hardcopy is async)
screen -S $N -p 0 -X hardcopy /tmp/cap.txt      # SCREENSHOT (to a file)
sleep 0.2
cat /tmp/cap.txt                                # READ
```

## Special keys — exact byte sequences (VERIFIED)

screen has no `Enter`/`C-c` names; send the literal terminal bytes via `$'...'`:

| Key | Send | Byte |
|---|---|---|
| Enter / Return | `$'\r'` | `0d` (CR — canonical; use `\r`, not `\n`) |
| Escape | `$'\033'` | `1b` |
| Ctrl-C (SIGINT) | `$'\003'` | `03` |
| Ctrl-D (EOF) | `$'\004'` | `04` |
| Tab | `$'\t'` | `09` |
| Up / Down / Right / Left | `$'\033[A'` / `[B` / `[C` / `[D` | normal-cursor mode |
| Up… in **application-cursor** apps (vim/readline) | `$'\033OA'` … | use `O` not `[` if `[A` doesn't move |
| F1–F4 | `$'\033OP'` `OQ` `OR` `OS` | |
| Home/End/PgUp/PgDn/Ins/Del | `$'\033[1~'` `[4~` `[5~` `[6~` `[2~` `[3~` | |

Send command **and** Enter in one call: `stuff $'ls -la\r'`. (caret notation `^M` also works,
but `$'\r'` is unambiguous.)

## The `stuff` size limit — the nastiest gotcha (VERIFIED)

A single `stuff` is capped at **~756 bytes**, and overflow is **silently dropped in its
entirety** (no error, no truncation — you just get nothing). Keep any one `stuff` under ~750
bytes. For larger input, load from a **file** into a register and `paste` (inline
`register key "string"` does NOT bypass the limit — same command buffer):

```bash
printf '%s' "$BIG" > /tmp/payload
screen -S $N -X readreg r /tmp/payload     # file → register r (no length limit)
screen -S $N -p 0 -X paste r               # inject into the window
```
Caveat: `paste` into a **cooked-mode** program (a normal shell) caps at **4096 bytes** (kernel
canonical line buffer); only a **raw-mode** reader (a TUI, `stty raw`) receives the whole
buffer. If pasting >4 KB into a shell, chunk it or have the program read the file directly.
`slowpaste msec` throttles for slow consumers.

## Reading the rendered screen — `hardcopy` (VERIFIED)

`hardcopy [-h] [file]` writes the **rendered visible grid** to a FILE (never stdout):
```bash
screen -S $N -p 0 -X hardcopy /tmp/cap.txt        # current screen
screen -S $N -p 0 -X hardcopy -h /tmp/cap.txt     # + scrollback history
sleep 0.2; cat /tmp/cap.txt                        # async write — sleep before reading
```
- **Timing:** `-X hardcopy` returns *before* the file is flushed; a ~0.2s sleep before `cat`
  avoids reading a stale/partial file. Same for a `stuff` before capturing (let output render).
- **TUIs/altscreen captured correctly** — verified `top`/`less` (alternate screen) render into
  the hardcopy as the visible viewport. Set `altscreen on` for xterm-like behavior.
- Files write as mode 0664 in the window's *default* dir (use an absolute path). `hardcopydir DIR`
  sets where bare hardcopies land; `hardcopy_append on` appends.
- Continuous logging (line-oriented output, not the grid): `screen -S $N -p 0 -X log on`
  (writes `screenlog.N`); `logfile FILE`, `logfile flush 1`.

## Idempotent headless session management (VERIFIED)

`screen -ls NAME` exits **0** if a session by that name exists, **1** if not (note: opposite of
intuition, but verified) — a clean by-name predicate. There's no atomic attach-if-exists for
headless use (`-dRR`/`-D -R` all attach a PTY), so guard-then-create:

```bash
screen -ls "$N" >/dev/null 2>&1 || screen -dmS "$N" bash    # create only if absent
# ... drive it ...
screen -S "$N" -X quit                                       # teardown (kills all windows)
screen -wipe                                                 # clear any dead sockets
```
`-dmS` = detached + named (won't fork into your terminal). For a systemd supervisor use
`-DmS` (foreground, exits when the session dies). Pin config for reproducibility:
`screen -c /dev/null -dmS "$N" bash` so a user's `.screenrc` (custom escape char, startup
windows, multiuser) can't perturb scripted behavior. Add `-fn` (flow off) so a stray `^S`
can't freeze output.

## Run-and-wait — screen has NO `wait-for`/exit-status (VERIFIED workaround)

This is screen's biggest gap vs tmux (no `wait-for`, no `pipe-pane`, no `pane_dead_status`).
Use a **driver-polled sentinel + exit-code file**:

```bash
rm -f /tmp/$N.done /tmp/$N.rc
screen -S $N -p 0 -X stuff $'mycmd; echo $? > /tmp/'"$N"$'.rc; touch /tmp/'"$N"$'.done\r'
until [ -f /tmp/$N.done ]; do sleep 0.2; done       # block until complete
rc=$(cat /tmp/$N.rc); echo "exit=$rc"                # got the real exit code
rm -f /tmp/$N.done /tmp/$N.rc
```
(Verified: blocked for the command's duration, returned the true exit code.) Pair with
`log on` if you also want the output streamed to a file you tail.

## Querying state (VERIFIED)

Only the **global** `-Q` subcommands return to your stdout and work while detached:
```bash
screen -S $N -Q windows    # e.g. "0 bash"  (current window marked * )
screen -S $N -Q number     # "0 (bash)"
screen -S $N -Q echo hi    # "hi"
```
`-Q select .`/`info`/`displays` only reach an *attached* display's message line → useless
headless; don't rely on them. There is no rich format/introspection vocabulary like tmux's
`display-message -p '#{...}'`.

## tmux ↔ screen quick parity

| operation | tmux | screen |
|---|---|---|
| start detached | `tmux new-session -d -s N` | `screen -dmS N` |
| create-or-reuse (headless) | `tmux has-session -t N \|\| tmux new-session -d -s N` | `screen -ls N \|\| screen -dmS N` |
| type text + Enter | `send-keys -t N -l -- 'txt'` ; `send-keys -t N Enter` | `-X stuff $'txt\r'` |
| special key | `send-keys -t N C-c` / `Up` | `-X stuff $'\003'` / `$'\033[A'` |
| screenshot → stdout | `capture-pane -p -t N` | (none) `-X hardcopy FILE` then `cat FILE` |
| + scrollback | `capture-pane -p -S - -t N` | `-X hardcopy -h FILE` |
| target window/pane | `-t N:win.pane` (IDs `%n`) | `-p win` (windows only, no panes) |
| exists? | `has-session -t N` (0/1) | `screen -ls N` (0/1) |
| run-and-wait / exit code | `wait-for` / `remain-on-exit`+`#{pane_dead_status}` | **sentinel+rc file** (above) |
| big input | `send-keys`/`load-buffer` (any size) | `readreg FILE` + `paste` (stuff ≤~750B) |
| safe read-only watch | `attach -r` | (none — `screen -x` is live input) |
| teardown | `kill-session -t N` | `-X quit` |

**Prefer tmux when present** (stdout capture, symbolic keys, real sync/exit-status, IDs).
**Use screen when tmux is absent** — fully capable with the patterns above; just budget for
raw-byte keys, file-mediated capture, the ~750B `stuff` limit, and the sentinel-file
completion shim.
