<div align="center">

# drive-remote-terminal

Teach Claude Code to operate an interactive full-screen terminal program (a TUI) on a remote machine over SSH — for people who automate work on servers, dev boxes, and headless hosts.

[![plugin-validate](https://github.com/88plug/drive-remote-terminal/actions/workflows/plugin-validate.yml/badge.svg)](https://github.com/88plug/drive-remote-terminal/actions/workflows/plugin-validate.yml)
[![License: FSL-1.1-ALv2](https://img.shields.io/badge/license-FSL--1.1--ALv2-blue?style=flat)](LICENSE.md)
[![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-8A2BE2?style=flat)](https://github.com/88plug/claude-code-plugins)

</div>

## Install

```text
/plugin marketplace add 88plug/drive-remote-terminal
/plugin install drive-remote-terminal@drive-remote-terminal
```

Or from a local clone:

```text
git clone https://github.com/88plug/drive-remote-terminal
/plugin marketplace add ./drive-remote-terminal
/plugin install drive-remote-terminal@drive-remote-terminal
```

Requires `tmux` (or `screen`) and `ssh` on the path — all standard.

## Quickstart

Once installed, ask Claude Code to drive a remote TUI and it follows the bundled loop:

```text
SSH into build-01 and run `htop`, then tell me which process is using the most memory.
```

Claude starts a tmux session on the remote host, launches the program, captures the
screen, reads it, and reports back — the same type-wait-look loop a human uses. You
see a real rendering of the remote screen in the answer, not a blind command result.

## What it does and why

You can't drive a TUI with one-shot SSH. `ssh host 'cmd'` runs and exits; piping
into a full-screen program that needs a real PTY fails. This plugin uses tmux (or
`screen` as a fallback) to give the agent both a way to type and eyes to see, so it
can operate the Claude Code TUI, vim, top, curses installers, REPLs, or any program
that needs a real PTY over SSH — the way a human would: type a keystroke, look at
the screen, decide the next move.

## The technique

The whole skill is one loop:

- Type — `tmux send-keys -t SESSION 'text' Enter`
- Wait — `sleep N` (let the app redraw)
- Screenshot — `tmux capture-pane -t SESSION -p` (this *is* the screenshot)
- Read and decide — look at the captured screen, then send the next input

Plus the hard-won rules: always screenshot after acting, always wait before you
screenshot, never double-send on an unexpected screen, submit a stuck line with a
standalone `Enter`, and confirm the program actually launched before sending keys
(or they fall through to the shell).

> [!TIP]
> The wait step matters more than it looks. Capturing the pane before the app has
> redrawn returns a stale screen, which leads the agent to act on the wrong state.

## What it bundles

One skill (`drive-remote-terminal`) that teaches a method — no scripts, no MCP, no
hooks. It ships reference files for:

- The full tmux key and `capture-pane` table
- A GNU `screen` fallback playbook
- Advanced SSH connection reuse and deterministic sync

## Contributing

Issues and pull requests are welcome. Open an issue to discuss a change before
sending a large pull request, and keep edits to the skill focused on the method it
teaches.

## License

[FSL-1.1-ALv2](LICENSE.md) © 2026 [88plug](https://github.com/88plug) —
Functional Source License; converts to Apache 2.0 two years after each release.
