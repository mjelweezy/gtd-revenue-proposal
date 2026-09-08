#!/usr/bin/env bash
# Re-publish the GTD Revenue Proposal from a fresh export.
#
#   ./update.sh ~/Downloads/"GTD Revenue Proposal (4).html"
#
# Two fixes are re-applied on every publish, because the export carries
# neither:
#   1. the page title (the export ships as "Bundled Page")
#   2. the GoatCounter tag (endpoint on window - see the note below)
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

if 'goatcounter' not in s:
    m = re.search(r'(<script type="__bundler/template">)(.*?)(</script>)', s, re.S)
    if not m:
        raise SystemExit('no bundler template found - export format changed?')
    raw = m.group(2)
    if raw.count(HEAD_CLOSE) != 1:
        raise SystemExit('expected exactly one </head> in template, found %d'
                         % raw.count(HEAD_CLOSE))
    # The endpoint goes on window, NOT on a data-goatcounter attribute: the DC
    # runtime rebuilds the head after the loader's swap and strips the tag, and
    # count.js on a background tab defers counting until the tab is visible --
    # by which time the attribute is gone and it has nowhere to send.
    q = chr(92) + '"'
    # The outer <head> title is cosmetic only - it is discarded in the same
    # document swap, leaving document.title empty (Chrome then shows the raw
    # URL in the tab, and GoatCounter records a blank title). The <title> that
    # actually takes effect is this one, inside the template.
    #
    # The endpoint goes on window rather than a data-goatcounter attribute:
    # the DC runtime strips the tag after it executes, and count.js resolves
    # its endpoint at count time - on a background tab that is only once the
    # tab becomes visible, long after the attribute is gone.
    js = """window.goatcounter = {endpoint: "ENDPOINT"};

// Per-slide events. The deck fires `slidechange` on document; count a slide
// once per load, and only once it has been on screen for MIN_MS, so paging
// through to slide 9 does not log every slide on the way there.
(function () {
  var MIN_MS = 2000, seen = {}, cur = null, since = 0, queue = [], tries = 0;

  function flush() {
    if (!(window.goatcounter && window.goatcounter.count)) {
      if (tries++ < 20) setTimeout(flush, 500);   // count.js still loading
      return;
    }
    while (queue.length) window.goatcounter.count(queue.shift());
  }

  function leave() {
    if (!cur || seen[cur.path] || Date.now() - since < MIN_MS) return;
    seen[cur.path] = 1;
    queue.push({path: cur.path, title: cur.title, event: true});
    flush();
  }

  function slug(s) {
    return String(s).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
  }

  document.addEventListener("slidechange", function (e) {
    leave();
    var d = e.detail || {};
    var n = (d.index == null ? 0 : d.index) + 1;
    var nn = (n < 10 ? "0" : "") + n;
    var label = (d.slide && d.slide.getAttribute("data-label")) || "";
    cur = {
      path: "slide-" + nn + (label ? "-" + slug(label) : ""),
      title: "Slide " + nn + (label ? " - " + label : "")
    };
    since = Date.now();
  });

  // count() uses navigator.sendBeacon, so the slide being read when the tab
  // closes still gets recorded.
  document.addEventListener("visibilitychange", function () { if (document.hidden) leave(); });
  window.addEventListener("pagehide", leave);
})();
""".replace('ENDPOINT', 'https://mjelweezy.goatcounter.com/count')

    # Escape for the JSON template string: json.dumps handles quotes,
    # backslashes and newlines; "/" in a closing tag additionally becomes
    # \u002F so it cannot terminate the host <script> element.
    esc = json.dumps(js)[1:-1].replace('</', '<' + chr(92) + 'u002F')

    snippet = ('<title>GTD Revenue Proposal' + SCRIPT_CLOSE.replace('script', 'title') + chr(92) + 'n' +
               '<script>' + chr(92) + 'n' + esc + SCRIPT_CLOSE + chr(92) + 'n' +
               '<script async src=' + q + 'https://gc.zgo.at/count.js' + q + '>' +
               SCRIPT_CLOSE + chr(92) + 'n')
    raw = raw.replace(HEAD_CLOSE, snippet + HEAD_CLOSE, 1)
    s = s[:m.start(2)] + raw + s[m.end(2):]

io.open(p, 'w', encoding='utf-8').write(s)

# --- 3. verify before publishing -----------------------------------------
tpl = json.loads(re.search(r'<script type="__bundler/template">(.*?)</script>',
                           s, re.S).group(1).strip())
head = tpl[:tpl.index('</head>')]
if 'goatcounter' not in head:
    raise SystemExit('analytics tag did not land in the template <head>')
if '<title>GTD Revenue Proposal</title>' not in head:
    raise SystemExit('title did not land in the template <head>')
if s.count('gc.zgo.at/count.js') != 1:
    raise SystemExit('expected exactly one analytics tag, found %d'
                     % s.count('gc.zgo.at/count.js'))
print('ok: title set, one analytics tag in template <head>, %d slides'
      % tpl.count('<section data-label='))
PY

git add index.html
git commit -m "Update GTD Revenue Proposal to latest export" \
           -m "Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
git push origin main
