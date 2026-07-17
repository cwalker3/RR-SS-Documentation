# Rebuilds ../docs/data.js from the .txt source documents.
# Run:  powershell -ExecutionPolicy Bypass -File build.ps1
#
# To add ANOTHER game: copy this whole `source` folder, drop the new game's .txt
# docs in it, change the $game* variables below, and point $out at a new file
# (e.g. ../docs/data-<id>.js). Then add a <script src="data-<id>.js"> line in
# ../docs/index.html. The game self-registers and appears in the in-app picker.
$ErrorActionPreference = 'Stop'
$src  = $PSScriptRoot
$docs = Join-Path (Split-Path $src -Parent) 'docs'

# --- this game's identity (change these for a different game) ---
$gameId    = 'rrss'
$gameName  = 'Rising Ruby / Sinking Sapphire'
$gameShort = 'RR/SS'
$out       = Join-Path $docs 'data.js'

& "$src\parse.ps1"    # .txt  -> data.json
& "$src\enrich.ps1"   # + stats, abilities, megas, TM/HM, move info

$data = [System.IO.File]::ReadAllText("$src\data.json", [System.Text.Encoding]::UTF8)
$reg = 'window.RRSS_GAMES=window.RRSS_GAMES||{};window.RRSS_GAMES["' + $gameId + '"]={id:"' + $gameId + '",name:"' + $gameName + '",short:"' + $gameShort + '",data:' + $data + '};'
[System.IO.File]::WriteAllText($out, $reg, (New-Object System.Text.UTF8Encoding($false)))
"Wrote {0} ({1:N0} bytes)" -f $out, ((Get-Item $out).Length)
