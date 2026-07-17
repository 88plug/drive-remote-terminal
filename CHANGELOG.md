# Changelog

## 2026.7.17

- Skill: fold remote-driving lessons from session histories — wait-by-polling
  (busy/ready + two-idle-read guard), stale-frame false-negatives, launch
  assert-or-abort, first-launch gauntlet, unattended detached jobs, SSH
  BatchMode/heredoc traps, env via environment.d, load-buffer multi-line paste,
  screen native escapes (references updated).
- Quality waves (post-initial): rolling-calver regime (hub computes version from
  commit count; no static `version` in plugin.json); CI `setup-python` v6.3.0 +
  runner fallback; fleet ruff check/format + pyright green; Dependabot + MkDocs
  green; docs/MkDocs site polish; `marketplace-entry.json` source shape `url`
  (fleet standard). Skill `references/` kept byte-identical with `docs/reference/`.

## 2026.6.23

- Initial release: a skill that teaches Claude Code to drive an interactive
  full-screen TUI on a remote machine over tmux/screen + SSH using a
  type-wait-screenshot-read loop.
- Reference files: full tmux key + `capture-pane` table, a GNU `screen`
  fallback playbook, and advanced SSH connection reuse / deterministic sync.
