# tmux send-keys / capture-pane reference

## send-keys basics

`tmux send-keys -t TARGET <args...>` sends keystrokes to a pane as if typed.

- **Literal text** goes as one quoted argument: `tmux send-keys -t rc 'hello world'`
  (this types the characters but does NOT press Enter).
- **Named keys** are separate bare arguments: `tmux send-keys -t rc 'hello' Enter`.
- You can chain: `tmux send-keys -t rc 'cd /tmp' Enter 'ls' Enter`.
- `-l` forces literal interpretation (useful if your text collides with a key name,
  e.g. sending the literal word "Enter": `tmux send-keys -t rc -l 'Enter'`).
- Target a specific window/pane with `session:window.pane` (e.g. `rc:0.0`); bare
  session name targets its active pane.

## Common named keys

| Key name | Effect |
|---|---|
| `Enter` (or `C-m`) | Return / submit |
| `Escape` | Esc — cancel, leave insert mode |
| `Tab` / `BTab` | Tab / Shift-Tab (cycle fields, modes) |
| `Space` | Space (often toggles a checkbox/selection) |
| `Up` `Down` `Left` `Right` | Arrow keys — navigate menus |
| `Home` `End` `PageUp` `PageDown` | Navigation |
| `BSpace` | Backspace |
| `C-c` | Ctrl-C (interrupt / cancel) |
| `C-d` | Ctrl-D (EOF / exit a REPL) |
| `C-u` | Ctrl-U (clear the input line) |
| `C-a` `C-e` | Start / end of line (readline) |
| `C-l` | Ctrl-L (redraw / clear screen) |

Ctrl combos are `C-x`; Alt/Meta combos are `M-x`.

## capture-pane (your "screenshot")

`tmux capture-pane -t TARGET -p` prints the current visible pane to stdout.

- `-p` = print to stdout (instead of a paste buffer).
- `-S -N` / `-S -` includes scrollback: `capture-pane -t rc -p -S -200` grabs the last
  200 lines of history — useful to read output that scrolled off, or
  `-S -` for the entire scrollback.
- `-e` preserves escape sequences (colors); usually omit it so you get clean text.
- `-J` joins wrapped lines — handy when long lines were soft-wrapped by the pane width.

Typical reads:
```bash
tmux capture-pane -t rc -p | tail -30                      # last visible screen
tmux capture-pane -t rc -p | grep -v '^[[:space:]]*$' | tail -25   # drop blank lines
tmux capture-pane -t rc -p -S -300 | grep -i error          # search scrollback
```

## Session / pane management

```bash
tmux new-session -d -s NAME -x 220 -y 50   # detached, sized (cols x rows)
tmux ls                                     # list sessions
tmux has-session -t NAME 2>/dev/null        # exit 0 if it exists
tmux kill-session -t NAME                   # stop it
tmux attach -t NAME                          # (human) attach interactively
tmux resize-window -t NAME -x 240 -y 60      # resize after creation if needed
```

## Gotchas

- **Size matters.** TUIs reflow to the pane size; a small pane truncates output. Start
  wide and tall (`-x 220 -y 50`).
- **Sleep before capture.** The pane updates asynchronously; capture too soon and you
  read a stale/half-drawn frame.
- **One action at a time when unsure.** If the screen didn't change as expected, capture
  again after a longer sleep rather than firing another keystroke — double-input is the
  main way to desync a TUI.
- **Servers persist.** A tmux server keeps running after your SSH session ends, so the
  TUI and its state survive — that's the point. Clean up with `kill-session` when done.
