#!/usr/bin/env python3
"""One-time: emit vanilla reference data organized by generation into docs/data/general/genN/.

Reconstructed from the migrated per-hack JSON: a changed value's "from" is the vanilla value,
and anything the hack didn't change is already vanilla. Each hack maps to its base generation
(rigred=3, brutalblack=5, rrss=6), so this covers the species/moves that actually appear in a hack.

These files are editable reference only (the app reads the self-contained per-hack JSON, not these).

Run:  python source/build-general-reference.py
"""
import json, pathlib

DOCS = pathlib.Path(__file__).resolve().parent.parent / "docs"
DATA = DOCS / "data"
HACK_GEN = {"rigred": 3, "brutalblack": 5, "rrss": 6}
STAT_KEYS = ["hp", "atk", "def", "spa", "spd", "spe"]


def load(gid, name):
    return json.loads((DATA / "hacks" / gid / f"{name}.json").read_text(encoding="utf-8"))


def dump(obj, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def vanilla_pokemon(entry):
    chg = {c.get("label"): c for c in entry.get("changes", []) if c.get("kind") == "change"}
    stats = {k: (entry["statChg"][k]["from"] if k in entry.get("statChg", {}) else entry["stats"].get(k))
             for k in STAT_KEYS}
    attr_type = next((a["value"] for a in entry.get("attrs", []) if a.get("label") == "Type"), "")
    typ = chg["Type"]["from"] if "Type" in chg else attr_type
    a1 = chg["Ability 1"]["from"] if "Ability 1" in chg else entry.get("a1", "")
    a2 = chg["Ability 2"]["from"] if "Ability 2" in chg else entry.get("a2", "")
    return {
        "name": entry["name"], "stats": stats,
        "types": [t.strip() for t in str(typ).split("/") if t.strip()],
        "abilities": [a for a in (a1, a2) if a],
    }


def vanilla_move(norm, mi, changes_by_norm):
    rows = {r.get("label"): r for r in changes_by_norm.get(norm, []) if r.get("kind") == "change"}
    pick = lambda label, cur: rows[label]["from"] if label in rows and rows[label].get("from") not in (None, "") else cur
    return {
        "name": mi.get("n", ""),
        "type": pick("Type", mi.get("t", "")),
        "category": pick("Category", mi.get("c", "")),
        "power": pick("Power", mi.get("pow")),
        "accuracy": mi.get("acc"),
        "pp": pick("PP", mi.get("pp")),
    }


def norm(s):
    return "".join(ch for ch in str(s).lower() if ch.isalnum())


def main():
    for gid, gen in HACK_GEN.items():
        gdir = DATA / "general" / f"gen{gen}"
        # pokemon (base stats / types / abilities)
        poke = load(gid, "pokemon")
        pk = {}
        for e in poke.get("entries", []):
            if e.get("dex") and e["dex"] != "000":
                pk[e["dex"]] = vanilla_pokemon(e)
        dump(dict(sorted(pk.items())), gdir / "pokemon.json")
        # moves (base info)
        moves = load(gid, "moves")
        changes_by_norm = {norm(en["name"]): en.get("rows", []) for en in moves.get("attacks", {}).get("entries", [])}
        mv = {k: vanilla_move(k, v, changes_by_norm) for k, v in moves.get("moveInfo", {}).items()}
        dump(dict(sorted(mv.items())), gdir / "moves.json")
        print(f"  gen{gen} ({gid}): {len(pk)} species, {len(mv)} moves -> {gdir.relative_to(DOCS)}")


if __name__ == "__main__":
    main()
