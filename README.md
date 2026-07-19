<div align="center">

# drive-remote-terminal

Drive remote interactive TUIs over SSH + tmux/screen — type, wait, screenshot, read. Claude Code & Grok plugin skill.

[![plugin-validate](https://github.com/88plug/drive-remote-terminal/actions/workflows/plugin-validate.yml/badge.svg)](https://github.com/88plug/drive-remote-terminal/actions/workflows/plugin-validate.yml)
[![License: FSL-1.1-ALv2](https://img.shields.io/badge/license-FSL--1.1--ALv2-blue?style=flat)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-online-2ea44f?style=flat)](https://88plug.github.io/drive-remote-terminal/)
[![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-8A2BE2?style=flat)](https://github.com/88plug/claude-code-plugins)
[![DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/88plug/drive-remote-terminal)

</div>

drive-remote-terminal is a Claude Code plugin skill for AI agents and developers who automate work on remote Linux servers, dev boxes, and headless hosts. It teaches the type → wait → screenshot → read loop so Claude can operate interactive terminal programs (TUIs) over SSH — the Claude Code TUI itself, vim, top/htop, curses installers, REPLs, and menus that need a real PTY.

One-shot `ssh host 'cmd'` cannot drive a full-screen TUI: the session exits, pipes lack a PTY, and the agent is blind. This skill uses tmux (or GNU screen) for send-keys input and capture-pane screenshots. No scripts, no MCP server, no hooks — method only. Shell, devops, and CLI automation stay in the loop you already know.

## Install

### Claude Code

```text
/plugin marketplace add 88plug/claude-code-plugins
/plugin install drive-remote-terminal@88plug
```

### Grok Build

```text
grok plugin marketplace add 88plug/claude-code-plugins
grok plugin install drive-remote-terminal@88plug --trust
```

Requires `tmux` (or `screen`) and `ssh` on the path — all standard.

## Quickstart

Once installed, ask Claude Code to drive a remote TUI:

```text
SSH into build-01 and run `htop`, then tell me which process is using the most memory.
```

Claude starts a tmux session on the remote host, launches the program, captures the screen, reads it, and reports back. You see a real rendering of the remote screen in the answer, not a blind command result.

## Features

| Feature | Detail |
| --- | --- |
| Type → wait → screenshot → read | Core human-style loop for remote TUIs |
| tmux primary path | `send-keys` to type, `capture-pane -p` to see |
| GNU screen fallback | First-class when tmux is missing |
| SSH transport notes | PTY rules, ControlMaster, auth, env gotchas |
| Method skill only | No scripts, no MCP server, no hooks |

## The tmux loop

You cannot drive a TUI with one-shot SSH. `ssh host 'cmd'` runs and exits. Piping into a full-screen program that needs a real PTY fails. This plugin uses tmux (or `screen` as a fallback) so the agent has both a way to type and eyes to see.

| Step | What | Example |
| --- | --- | --- |
| **Type** | Send keystrokes into the pane | `tmux send-keys -t SESSION 'text' Enter` |
| **Wait** | Let the app process and redraw | `sleep N` |
| **Screenshot** | Print the visible pane to stdout | `tmux capture-pane -t SESSION -p` |
| **Read** | Decide the next input from what you saw | pipe through `tail` / `grep` as needed |

```bash
tmux send-keys -t rc 'summarize the last error in this log' Enter
sleep 15
tmux capture-pane -t rc -p | tail -30
# decide the next input from the captured screen, then repeat
```

Hard-won rules that keep the loop reliable:

1. **Always screenshot after acting.** Never assume an input worked.
2. **Always wait before you screenshot.** Capture too early → stale frame → wrong next move.
3. **If the screen is unexpected, wait longer and re-capture — do not re-send.** Double-sending is the #1 way to desync a TUI.
4. **Stuck typed text with no spinner?** Send a standalone `Enter` to submit (not a retype).
5. **Confirm the program actually launched before any input** — see [Safety](#safety).

> [!TIP]
> The wait step matters more than it looks. Capturing the pane before the app has redrawn returns a stale screen, which leads the agent to act on the wrong state. Tune sleep to the action: ~1–3s for a keystroke/menu move, ~12–20s for a model response, network call, or app boot.

## When to use

Use this skill when the remote program **needs a real PTY and stays on screen**:

- Interactive TUIs (Claude Code TUI, `htop`/`top`, `vim`, curses installers, menus)
- REPLs and prompts that gate on yes/no, menus, or text fields
- Resuming a long-lived session already hosted in remote tmux/screen
- Any case where `ssh host 'cmd'` or a pipe is not enough

**Do not use it** for non-interactive / one-shot work:

- Read a file, run a build, tail a log
- Tools with a batch/`--print` mode (e.g. `claude -p "..."`)
- Anything that returns text and exits cleanly over plain SSH

If the box has no tmux, GNU `screen` is a first-class fallback — see [`skills/.../references/screen.md`](skills/drive-remote-terminal/references/screen.md). For heavy automation, connection reuse, or deterministic sync instead of `sleep`, see [`advanced-and-ssh.md`](skills/drive-remote-terminal/references/advanced-and-ssh.md). Full docs: [88plug.github.io/drive-remote-terminal](https://88plug.github.io/drive-remote-terminal/).

## Safety

Acting as the human means real work and live processes are at stake.

> [!WARNING]
> **Keys can fall through to the shell.** Confirm the program actually launched **before** sending any input. After the launch command, screenshot and verify the program's UI is on screen (its prompt, menu, or buffer). If it failed to start — not installed, wrong path, crashed, permission denied — you will instead see a shell prompt or an error. **Every keystroke then falls through to the shell**, where typed text + `Enter` executes as a shell command. That can be destructive. Never fire a scripted key sequence blind. Cheap pre-check: `command -v <prog>` before launching.

Other standing rules:

- **Observe before you touch.** Screenshot and read state first. Do not kill/restart a process just to see what happens.
- **Don't double-open a session.** Confirm nothing live already holds it (`pgrep`/`ps`, open files under `/proc/PID/fd`).
- **Prefer the lossless path.** Relaunch/resume when state is persisted; mutating shared config other live processes read is risky.
- **Hand back cleanly.** Tell the human the session name and state. Kill the session only when asked: `tmux kill-session -t NAME`.

## Skill references

One skill (`drive-remote-terminal`) ships three reference files the agent loads on demand:

| Reference | When you need it |
| --- | --- |
| [tmux keys & capture-pane](skills/drive-remote-terminal/references/tmux-keys.md) | Named keys, `capture-pane` flags, session/pane management |
| [GNU screen fallback](skills/drive-remote-terminal/references/screen.md) | No tmux on the box — raw-byte keys, `hardcopy`, `stuff` limits |
| [Advanced SSH & sync](skills/drive-remote-terminal/references/advanced-and-ssh.md) | Connection reuse, deterministic wait, expect vs tmux decision guide |

## Development

Local clone for skill edits or offline install:

```text
git clone https://github.com/88plug/drive-remote-terminal
/plugin marketplace add ./drive-remote-terminal
/plugin install drive-remote-terminal@88plug
```

## Contributing

Issues and pull requests are welcome. Open an issue to discuss a change before sending a large pull request, and keep edits to the skill focused on the method it teaches.

## License

[FSL-1.1-ALv2](LICENSE) © 2026 [88plug](https://github.com/88plug) —
Functional Source License; converts to Apache 2.0 two years after each release.
