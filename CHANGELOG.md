# Changelog

## 2026.7.17

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
