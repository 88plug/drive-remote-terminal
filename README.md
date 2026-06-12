# drive-remote-terminal

A Claude Code plugin that teaches the agent to operate an interactive,
full-screen terminal program (a TUI) on a **remote** machine — the way a human
would: type a keystroke, look at the screen, decide the next move.

You can't drive a TUI with one-shot SSH (`ssh host 'cmd'` runs and exits; piping
into a full-screen program that needs a real PTY fails). This skill uses tmux
(or `screen` as a fallback) to give the agent both a way to type and eyes to see.

## The technique

The whole skill is one loop:

- **Type** — `tmux send-keys -t SESSION 'text' Enter`
- **Wait** — `sleep N` (let the app redraw)
- **Screenshot** — `tmux capture-pane -t SESSION -p` (this *is* the screenshot)
- **Read & decide** — look at the captured screen, then send the next input

Plus the hard-won rules: always screenshot after acting, always wait before you
screenshot, never double-send on an unexpected screen, submit a stuck line with a
standalone `Enter`, and confirm the program actually launched before sending keys
(or they fall through to the shell).

## What it bundles

One skill (`drive-remote-terminal`) with reference files for the full tmux key /
capture-pane table, a GNU `screen` fallback playbook, and advanced SSH connection
reuse + deterministic sync. No scripts, no MCP, no hooks — it teaches a method.

## Install

```
/plugin marketplace add 88plug/drive-remote-terminal
/plugin install drive-remote-terminal@drive-remote-terminal
```

Or from a local clone:

```
git clone https://github.com/88plug/drive-remote-terminal
/plugin marketplace add ./drive-remote-terminal
/plugin install drive-remote-terminal@drive-remote-terminal
```

Requires `tmux` (or `screen`) and `ssh` on the path — all standard.

## License

[FSL-1.1-ALv2](LICENSE.md) © 2026 [88plug](https://github.com/88plug) —
Functional Source License; converts to Apache 2.0 two years after each release.
