# Rebuilds ../docs/data.js from a game's .txt source documents.
# Run:  powershell -ExecutionPolicy Bypass -File build.ps1
#
# To add ANOTHER game: make a new folder under `games/` (e.g. games/oras), drop the
# new game's .txt change docs in it, change the $game* variables below, and point
# $out at a new file (e.g. ../docs/data-oras.js). Then add a <script src="data-oras.js">
# line in ../docs/index.html. The game self-registers and appears in the in-app picker.
$ErrorActionPreference = 'Stop'
$src  = $PSScriptRoot
$docs = Join-Path (Split-Path $src -Parent) 'docs'

# --- this game's identity (change these for a different game) ---
$gameId    = 'rrss'
$gameName  = 'Rising Ruby / Sinking Sapphire'
$gameShort = 'RR/SS'
$out       = Join-Path $docs 'data.js'

$gameDir = Join-Path $src "games\$gameId"    # this game's .txt docs + generated data.json

& "$src\parse.ps1"  -GameDir $gameDir   # .txt  -> data.json
& "$src\enrich.ps1" -GameDir $gameDir   # + stats, abilities, megas, TM/HM, move info

$data = [System.IO.File]::ReadAllText("$gameDir\data.json", [System.Text.Encoding]::UTF8)
$reg = 'window.RRSS_GAMES=window.RRSS_GAMES||{};window.RRSS_GAMES["' + $gameId + '"]={id:"' + $gameId + '",name:"' + $gameName + '",short:"' + $gameShort + '",data:' + $data + '};'
[System.IO.File]::WriteAllText($out, $reg, (New-Object System.Text.UTF8Encoding($false)))
"Wrote {0} ({1:N0} bytes)" -f $out, ((Get-Item $out).Length)
