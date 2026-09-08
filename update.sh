#!/usr/bin/env bash
# Re-publish the GTD Revenue Proposal from a fresh export.
#
#   ./update.sh ~/Downloads/"GTD Revenue Proposal (4).html"
#
# Two fixes are re-applied on every publish, because the export carries
# neither:
#   1. the page title (the export ships as "Bundled Page")
#   2. the GoatCounter tag
#
# The tag MUST go inside the bundled template, not the outer <head>: the
# loader ends with document.documentElement.replaceWith(...), which throws
# the outer <head> away, so a tag placed there never reliably runs.
set -euo pipefail

src=${1:?usage: ./update.sh <exported .html>}
cd "$(dirname "$0")"
[ -f "$src" ] || { echo "no such file: $src" >&2; exit 1; }

cp "$src" index.html

python3 - <<'PY'
import io, json, re

p = 'index.html'
s = io.open(p, encoding='utf-8').read()

# --- 1. title -------------------------------------------------------------
title = '  <title>GTD Revenue Proposal</title>\n'
s = s.replace('  <title>Bundled Page</title>\n', title, 1)
if title not in s:
    raise SystemExit('could not set title - export format changed?')

# --- 2. GoatCounter, inside the bundled template's <head> -----------------
# Inside the template JSON, "/" in a closing tag is escaped as \u002F so it
# cannot terminate the host <script> element. Match and emit that form.
ESC = chr(92) + 'u002F'
HEAD_CLOSE   = '<' + ESC + 'head>'
SCRIPT_CLOSE = '<' + ESC + 'script>'

if 'data-goatcounter' not in s:
    m = re.search(r'(<script type="__bundler/template">)(.*?)(</script>)', s, re.S)
    if not m:
        raise SystemExit('no bundler template found - export format changed?')
    raw = m.group(2)
    if raw.count(HEAD_CLOSE) != 1:
        raise SystemExit('expected exactly one </head> in template, found %d'
                         % raw.count(HEAD_CLOSE))
    snippet = ('<script data-goatcounter=\\"https://mjelweezy.goatcounter.com/count\\" '
               'async src=\\"https://gc.zgo.at/count.js\\">' + SCRIPT_CLOSE + chr(92) + 'n')
    raw = raw.replace(HEAD_CLOSE, snippet + HEAD_CLOSE, 1)
    s = s[:m.start(2)] + raw + s[m.end(2):]

io.open(p, 'w', encoding='utf-8').write(s)

# --- 3. verify before publishing -----------------------------------------
tpl = json.loads(re.search(r'<script type="__bundler/template">(.*?)</script>',
                           s, re.S).group(1).strip())
head = tpl[:tpl.index('</head>')]
if 'data-goatcounter' not in head:
    raise SystemExit('analytics tag did not land in the template <head>')
if s.count('data-goatcounter') != 1:
    raise SystemExit('expected exactly one analytics tag, found %d'
                     % s.count('data-goatcounter'))
print('ok: title set, one analytics tag in template <head>, %d slides'
      % tpl.count('<section data-label='))
PY

git add index.html
git commit -m "Update GTD Revenue Proposal to latest export" \
           -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
git push origin main
