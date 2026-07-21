# Data (editable JSON — the source of truth)

The site reads these JSON files directly (via `../loader.js`, which reassembles them into the shape
`app.js` expects). **Edit these files to change the site** — there is no build step anymore. The old
PowerShell build scripts and prose mastersheets under `../../source/` are kept only as historical
reference.

## Layout
```
manifest.json          list of games shown in the picker: {id, name, short, gen}
hacks/<id>/            one folder per romhack (rigred, brutalblack, rrss) — self-contained
  meta.json            id, name, short, gen, + nameDex (name→dex fallbacks)
  pokemon.json         { meta, entries[], tmMoves }   base stats+deltas, learnsets, abilities, types
  moves.json           { moveInfo{}, attacks{} }      move database + the "what changed" list
  areas.json           { meta, areas[] }              routes: wild encounters, trainers, gauntlets…
  gifts.json  items.json  evolution.json  thief.json
general/genN/          vanilla reference by generation (gen3/5/6) — NOT read by the app, just reference
  pokemon.json         { dex: {name, stats, types, abilities} }   vanilla base values
  moves.json           { move: {name, type, category, power, accuracy, pp} }
```
Each hack folder is **self-contained** (vanilla values are already merged in), so editing one hack
never affects another. `general/` is there so you can look up / reuse the vanilla numbers.

## Editing
Just edit the JSON and reload the page. To add a game, drop a new `hacks/<id>/` folder with the same
files and add an entry to `manifest.json`.

## Running locally
`fetch()` is blocked on `file://`, so serve this folder's parent over http:
```
cd docs
python -m http.server 8080
# open http://localhost:8080/
```
On GitHub Pages / nuzlocke.net it just works (static files).

## Regenerating (only if you ever need to re-derive from the old bundles)
`python ../../source/migrate-to-json.py`  — re-splits the old `data-*.js` bundles (git history).
`python ../../source/build-general-reference.py`  — rebuilds `general/` from the hack JSON.
