/* Loads the per-hack JSON in docs/data/ and reassembles the exact window.RRSS_GAMES shape that
   app.js expects, then injects app.js. Split-then-reassemble is an identity transform, so app.js
   is unchanged — only *how* the data arrives changed (script bundles -> fetched JSON).

   NOTE: fetch() is blocked on file:// URLs. Serve docs/ over http for local dev, e.g.
     python -m http.server 8080     (then open http://localhost:8080/) */
(async function () {
  const BASE = 'data/';
  const NAMED = ['pokemon', 'areas', 'gifts', 'items', 'evolution', 'thief'];  // each -> data.<key>
  async function jget(path) {
    const r = await fetch(BASE + path);
    return r.ok ? r.json() : undefined;   // a missing file just means that key was absent originally
  }
  const manifest = await jget('manifest.json');
  if (!manifest) throw new Error('data/manifest.json not found');

  window.RRSS_GAMES = window.RRSS_GAMES || {};
  await Promise.all(manifest.games.map(async g => {
    const dir = 'hacks/' + g.id + '/';
    const files = await Promise.all(
      [...NAMED, 'moves', 'meta'].map(n => jget(dir + n + '.json'))
    );
    const part = Object.fromEntries([...NAMED, 'moves', 'meta'].map((n, i) => [n, files[i]]));
    const data = {};
    for (const k of NAMED) if (part[k] !== undefined) data[k] = part[k];
    if (part.moves) { data.moveInfo = part.moves.moveInfo; data.attacks = part.moves.attacks; }
    if (part.meta) for (const k in part.meta) {
      if (!['id', 'name', 'short', 'gen'].includes(k)) data[k] = part.meta[k];  // nameDex, generated, ...
    }
    window.RRSS_GAMES[g.id] = { id: g.id, name: g.name, short: g.short, data };
  }));

  const s = document.createElement('script');
  s.src = 'app.js';
  document.body.appendChild(s);
})().catch(err => {
  console.error(err);
  const c = document.getElementById('content');
  if (c) c.innerHTML = '<div style="padding:40px;line-height:1.6;color:#d08">Could not load the data files.<br><br>' +
    'If you opened <code>index.html</code> directly (a <code>file://</code> URL), the browser blocks ' +
    '<code>fetch()</code>. Serve the <code>docs/</code> folder over http instead, e.g.:<br>' +
    '<code>python -m http.server 8080</code> &rarr; open <code>http://localhost:8080/</code><br><br>' +
    '<small>' + String(err) + '</small></div>';
});
