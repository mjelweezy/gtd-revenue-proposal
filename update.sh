#!/usr/bin/env bash
# Re-publish the GTD Revenue Proposal from a fresh export.
#
#   ./update.sh ~/Downloads/"GTD Revenue Proposal (4).html"
#
# The export ships as <title>Bundled Page</title> and carries no analytics,
# so both fixes are re-applied here on every publish.
set -euo pipefail

src=${1:?usage: ./update.sh <exported .html>}
cd "$(dirname "$0")"
[ -f "$src" ] || { echo "no such file: $src" >&2; exit 1; }

cp "$src" index.html

python3 - <<'PY'
import io
p = 'index.html'
s = io.open(p, encoding='utf-8').read()

title = '  <title>GTD Revenue Proposal</title>\n'
s = s.replace('  <title>Bundled Page</title>\n', title, 1)
if title not in s:
    raise SystemExit('could not set title - export format changed?')

if 'goatcounter' not in s:
    s = s.replace(title, title + '''  <script data-goatcounter="https://mjelweezy.goatcounter.com/count"
          async src="//gc.zgo.at/count.js"></script>
''', 1)

io.open(p, 'w', encoding='utf-8').write(s)
print('title + analytics applied')
PY

git add index.html
git commit -m "Update GTD Revenue Proposal to latest export" \
           -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
git push origin main
