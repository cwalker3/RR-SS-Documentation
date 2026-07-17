# Source & build pipeline

The source documents and scripts that generate the site's data. **The live site
(`../docs`) is fully self-contained and needs nothing in this folder at runtime** —
everything here is only for (re)generating the data.

## Layout

```
source/
  parse.ps1  enrich.ps1  build.ps1  fetch-*.ps1     ← shared scripts (game-agnostic)
  *.csv  *.tsv  gen6-pokedex.ts  gen7-pokedex.ts    ← shared PokeAPI/Showdown reference data
  games/
    rrss/
      *.txt          ← this game's change docs (the source of truth)
      data.json      ← generated (gitignored)
```

The scripts and reference CSVs are shared across every game; only each game's `.txt`
change docs live in its own `games/<id>/` folder. Adding a game no longer means copying
`source/` — just add a new `games/<id>/` folder.

## Pipeline

```
games/<id>/*.txt ──parse.ps1──► games/<id>/data.json ──enrich.ps1──► games/<id>/data.json ──build.ps1──► ../docs/data.js
                                              ▲
                                   PokeAPI + Showdown data files (in source/)
```

`parse.ps1` and `enrich.ps1` take a `-GameDir` parameter (the `games/<id>/` folder);
`build.ps1` passes it for you.

## Files

| File | Purpose |
|------|---------|
| `games/<id>/*.txt` | A game's change documents (e.g. `games/rrss/`) — the source of truth for all parsed data. |
| `parse.ps1` | Parses the `.txt` files into `data.json` (Pokémon, areas, moves, evolutions, items, gifts, thief). |
| `enrich.ps1` | Adds base stats (Gen-6-corrected), vanilla abilities (2 regular + hidden), Mega/Primal forme stats, TM/HM compatibility, and move info (type/category/power/accuracy/PP/description + hack changes). |
| `build.ps1` | Runs parse + enrich and writes `../docs/data.js`. **This is the one to run.** |
| `fetch-sprites.ps1` | Re-downloads all 721 sprites into `../docs/sprites.js`. Only needed if sprites change. |
| `fetch-tms.ps1` | Regenerates `oras_tms.csv` from PokeAPI (~10 MB download). Only needed to refresh TM data. |
| `fetch-moves.ps1` | Regenerates `move_desc.tsv` + refreshes `moves.csv`/`type_names.csv` from PokeAPI (~5 MB). Only to refresh move data. |
| `pokemon.csv`, `pokemon_stats.csv`, `pokemon_abilities.csv`, `ability_names.csv`, `machines.csv`, `move_names.csv`, `moves.csv`, `type_names.csv` | PokeAPI data (forms incl. megas, stats, abilities, TM/HM machines, move names, move stats, type names). |
| `oras_tms.csv` | Per-Pokémon ORAS TM/HM compatibility (pre-computed; see `fetch-tms.ps1`). |
| `move_desc.tsv` | ORAS move descriptions (pre-computed; see `fetch-moves.ps1`). |
| `gen6-pokedex.ts`, `gen7-pokedex.ts` | Pokémon Showdown historical base-stat overrides (for Gen-6 accuracy). |

## Rebuild the data

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1
```

Regenerates `../docs/data.js` from the `.txt` files. The frontend itself
(`../docs/index.html`, `app.js`, `styles.css`) is hand-maintained — not generated.

## Adding another game

The site supports multiple games. Each game's data file self-registers into a
`window.RRSS_GAMES` registry (`{id, name, short, data}`), and the app shows a game
picker in the sidebar whenever more than one game is loaded. Per-game progress
(caught / trainers / missed / profile) is stored under its own `rrss-<id>-…`
localStorage namespace, so switching games keeps each nuzlocke separate.

To add a game (e.g. Omega Ruby / Alpha Sapphire):

1. Create `games/<id>/` (e.g. `games/oras/`) and drop the new game's change `.txt` docs into it.
2. In `build.ps1`, set `$gameId` / `$gameName` / `$gameShort` to the new game and
   point `$out` at a new file, e.g. `../docs/data-oras.js`. (`$gameDir` is derived from `$gameId`.)
3. Run `powershell -ExecutionPolicy Bypass -File build.ps1`.
4. Add one line to `../docs/index.html`, right after the existing `data.js` script:
   `<script src="data-oras.js"></script>`.

The new game then appears automatically in the in-app picker — no frontend code
changes needed. (`$gameId` must be unique and stable; it keys the saved progress.)
