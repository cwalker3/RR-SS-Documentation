#!/usr/bin/env python3
"""One-time migration: split the generated docs/data-*.js bundles into editable JSON.

After this runs, docs/data/** is the source of truth (see docs/loader.js). The prose
mastersheets and source/games/*/build.ps1 remain only as historical reference.

Layout produced (under docs/data/):
  manifest.json                 list of games {id,name,short,gen}
  hacks/<id>/meta.json          id,name,short,gen + any misc top-level keys (nameDex, generated, ...)
  hacks/<id>/pokemon.json       data.pokemon
  hacks/<id>/moves.json         {moveInfo, attacks}
  hacks/<id>/areas.json         data.areas
  hacks/<id>/gifts.json         data.gifts
  hacks/<id>/items.json         data.items
  hacks/<id>/evolution.json     data.evolution
  hacks/<id>/thief.json         data.thief

Run:  python source/migrate-to-json.py
"""
import json, re, os, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
OUT = DOCS / "data"

# (bundle file, game id, generation of the base game)
BUNDLES = [
    ("data.js", "rrss", 6),
    ("data-rigred.js", "rigred", 3),
    ("data-brutalblack.js", "brutalblack", 5),
]

# top-level data keys that get their own file; everything else falls through to meta.json
OWN_FILE = ["pokemon", "areas", "gifts", "items", "evolution", "thief"]


def extract(path, game_id):
    raw = path.read_text(encoding="utf-8")
    m = re.search(r'RRSS_GAMES\["' + re.escape(game_id) + r'"\]\s*=', raw)
    s = raw[m.end():]
    # outer object has unquoted keys id/name/short/data — pull the three strings, then the data JSON
    outer = s[: s.index("data:")]
    name = re.search(r'name:"((?:[^"\\]|\\.)*)"', outer).group(1)
    short = re.search(r'short:"((?:[^"\\]|\\.)*)"', outer).group(1)
    idv = re.search(r'id:"((?:[^"\\]|\\.)*)"', outer).group(1)
    d = s[s.index("data:") + 5:]
    start = d.index("{"); depth = 0; i = start; instr = False; esc = False
    while i < len(d):
        c = d[i]
        if instr:
            if esc: esc = False
            elif c == "\\": esc = True
            elif c == '"': instr = False
        else:
            if c == '"': instr = True
            elif c == "{": depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0: break
        i += 1
    data = json.loads(d[start:i + 1])
    return idv, name, short, data


def dump(obj, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    manifest = {"games": []}
    for fname, gid, gen in BUNDLES:
        idv, name, short, data = extract(DOCS / fname, gid)
        hack = OUT / "hacks" / gid
        # own-file keys
        for k in OWN_FILE:
            if k in data:
                dump(data[k], hack / f"{k}.json")
        # moves = moveInfo + attacks
        dump({"moveInfo": data.get("moveInfo", {}), "attacks": data.get("attacks", {})}, hack / "moves.json")
        # meta = id/name/short/gen + every remaining top-level key (nameDex, generated, ...)
        handled = set(OWN_FILE) | {"moveInfo", "attacks"}
        meta = {"id": idv, "name": name, "short": short, "gen": gen}
        for k, v in data.items():
            if k not in handled:
                meta[k] = v
        dump(meta, hack / "meta.json")
        manifest["games"].append({"id": idv, "name": name, "short": short, "gen": gen})
        print(f"  {gid}: split into {hack.relative_to(DOCS)}/  (gen {gen})")
    dump(manifest, OUT / "manifest.json")
    print(f"Wrote manifest with {len(manifest['games'])} games -> {(OUT/'manifest.json').relative_to(DOCS)}")


if __name__ == "__main__":
    main()
