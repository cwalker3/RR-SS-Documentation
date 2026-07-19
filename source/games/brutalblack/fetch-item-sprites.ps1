# Fetches item sprites from the PokeAPI sprite repo and embeds them (base64) into
# ../../../docs/item-sprites.js as window.RRSS_ITEMSPR = { <normalized item name>: <b64> }.
# Run:  powershell -ExecutionPolicy Bypass -File fetch-item-sprites.ps1
# Item names come from the built data-brutalblack.js so it stays in sync.
$ErrorActionPreference = 'Stop'
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
$docs = Join-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) 'docs'
$dataFile = Join-Path $docs 'data-brutalblack.js'
$raw = [System.IO.File]::ReadAllText($dataFile, [Text.Encoding]::UTF8)
$json = $raw.Substring($raw.IndexOf('data:') + 5)
$json = $json.Substring(0, $json.Length - 2)
$dd = $json | ConvertFrom-Json

# ---- collect distinct item strings (thief items, item-ball swaps, per-area items) ----
$items = @{}
foreach ($s in $dd.thief.stages) { foreach ($r in $s.rows) { if ($r.item) { $items[$r.item] = $true } } }
foreach ($b in $dd.items.blocks) { if ($b.type -eq 'table') { foreach ($r in $b.rows) { if ($r.Count -ge 3) { $items[$r[1]] = $true; $items[$r[2]] = $true } } } }
foreach ($a in $dd.areas.areas) { foreach ($it in $a.items) { if ($it.was) { $items[$it.was] = $true } } }

function Norm-Item($s){ return ([string]$s).ToLower() -replace '[^a-z0-9]','' }

# name -> PokeAPI item identifier (returns $null to skip: moves, compounds, TMs/HMs handled separately)
$override = @{
  'x defend'='x-defense'; 'x accuracy'='x-accuracy'; 'parlyz heal'='paralyze-heal';
  'kings rock'='kings-rock'; 'never-melt ice'='never-melt-ice'; 'poke ball'='poke-ball';
  'exp share'='exp-share'; 'thick clubs'='thick-club'; 'black sludges'='black-sludge';
  'toxic and flame orbs'='flame-orb'; 'iron balls and sticky barbs'='iron-ball';
  'hard stone and everstones'='hard-stone'; 'metal coats'='metal-coat'
}
function To-ItemId($name){
  $n = ([string]$name -replace [char]0x2019, "'").Trim()
  $low = $n.ToLower()
  if ($override.ContainsKey($low)) { return $override[$low] }
  if ($n -match '^(TM|HM)\d') { return $null }                 # TMs/HMs get a generic disc in the UI
  $id = $low -replace 'berries','berry'
  $id = $id -replace '\bstones\b','stone' -replace '\bbands\b','band' -replace '\bherbs\b','herb' `
             -replace '\bclubs\b','club' -replace '\borbs\b','orb' -replace '\bplates\b','plate' `
             -replace '\bseeds\b','seed' -replace '\bfangs\b','fang' -replace '\bscarfs\b','scarf'
  $id = $id -replace "['.]",'' -replace '\s+','-'
  return $id
}

$out = New-Object System.Collections.Specialized.OrderedDictionary
$idCache = @{}
$ok = 0; $miss = New-Object System.Collections.ArrayList
function Fetch-Sprite($id){
  if ($script:idCache.ContainsKey($id)) { return $script:idCache[$id] }
  $b64 = $null
  try {
    $u = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/items/$id.png"
    $bytes = (Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 20).Content
    if ($bytes -is [string]) { $bytes = [Text.Encoding]::Default.GetBytes($bytes) }
    $b64 = [Convert]::ToBase64String($bytes)
  } catch { $b64 = $null }
  $script:idCache[$id] = $b64
  return $b64
}

# generic TM / HM disc
$tm = Fetch-Sprite 'tm-normal'
if ($tm) { $out['_tm'] = $tm; $out['_hm'] = $tm }

foreach ($name in ($items.Keys | Sort-Object)) {
  if ($name -match '^(TM|HM)\d') { continue }                  # covered by _tm/_hm
  $id = To-ItemId $name
  if (-not $id) { continue }
  $b64 = Fetch-Sprite $id
  if ($b64) { $out[(Norm-Item $name)] = $b64; $ok++ } else { [void]$miss.Add("$name -> $id") }
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.Append('window.RRSS_ITEMSPR=')
[void]$sb.Append(($out | ConvertTo-Json -Compress))
[void]$sb.Append(';')
$outFile = Join-Path $docs 'item-sprites.js'
[System.IO.File]::WriteAllText($outFile, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
"Wrote {0} ({1:N0} bytes)" -f $outFile, ((Get-Item $outFile).Length)
"Item sprites: {0} matched, {1} unmatched" -f $ok, $miss.Count
if ($miss.Count) { "Unmatched: " + (($miss | Select-Object -First 60) -join ', ') }
