#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "=== smoke: manifest is valid JSON ==="
python3 -c "import json; json.load(open('.claude-plugin/plugin.json')); print('  ok: .claude-plugin/plugin.json')"
python3 -c "import json; json.load(open('.claude-plugin/marketplace.json')); print('  ok: .claude-plugin/marketplace.json')"

echo "=== smoke: skill frontmatter present ==="
while IFS= read -r f; do
    head -1 "$f" | grep -q '^---$' && echo "  ok: $f"
done < <(find skills -name SKILL.md 2>/dev/null)

echo "=== smoke: no root-level plugin.json ==="
if [[ -f plugin.json ]]; then
    echo "  FAIL: root plugin.json must not exist"
    exit 1
fi
echo "  ok: no root plugin.json"

echo "=== smoke: all good ==="
