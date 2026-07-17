# Builds ../../../docs/data-brutalblack.js from Brutal Black's Pokemon-changes CSV.
# Run:  powershell -ExecutionPolicy Bypass -File build.ps1
#
# Brutal Black is a Gen-5 hack with its OWN stats/types/abilities/learnsets, so it
# does NOT use the shared parse/enrich pipeline (that pulls ORAS/Gen-6 data). This
# script reads the CSV grid directly and emits a game that self-registers into
# window.RRSS_GAMES. First pass: Pokedex only (species, types, abilities, base stats
# with +/- changes vs vanilla, and level-up learnsets).
param([string]$GameDir = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$src  = Split-Path (Split-Path $GameDir -Parent) -Parent      # ...\source
$docs = Join-Path (Split-Path $src -Parent) 'docs'
$csvPath = Join-Path $GameDir 'Brutal Black Pokemon Changes + Movesets - Unova.csv'
$out  = Join-Path $docs 'data-brutalblack.js'

# --- national-dex lookup from the shared PokeAPI dump (name -> dex, for sprites) ---
# Index every row (incl. alternate formes) by its normalized identifier -> species_id
# (the national dex, which is what sprites.js is keyed on). Default rows come first in
# the file, so base identifiers win.
$name2dex = @{}
Get-Content "$src\pokemon.csv" | Select-Object -Skip 1 | ForEach-Object {
  $p = $_ -split ','
  if ($p.Count -ge 3) {
    $species = [int]$p[2]
    if ($species -ge 1 -and $species -le 721) {
      $key = ($p[1].ToLower() -replace '[^a-z0-9]','')
      if (-not $name2dex.ContainsKey($key)) { $name2dex[$key] = $species }
    }
  }
}
# Brutal Black writes some species by base name only (formes) or with a typo.
@{ 'darmanitan'=555; 'frillish'=592; 'jellicent'=593; 'beeheyem'=606 }.GetEnumerator() |
  ForEach-Object { if (-not $name2dex.ContainsKey($_.Key)) { $name2dex[$_.Key] = $_.Value } }
function Norm($s){ return ([string]$s).ToLower() -replace '[^a-z0-9]','' }
# fix obvious source-sheet misspellings so the display name matches the real species
$nameFix = @{ 'Beeheyem' = 'Beheeyem' }

# --- read the CSV grid (quote-aware) ---
Add-Type -AssemblyName Microsoft.VisualBasic
$parser = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($csvPath)
$parser.TextFieldType = [Microsoft.VisualBasic.FileIO.FieldType]::Delimited
$parser.SetDelimiters(',')
$parser.HasFieldsEnclosedInQuotes = $true
$rows = New-Object System.Collections.ArrayList
while (-not $parser.EndOfData) { [void]$rows.Add($parser.ReadFields()) }
$parser.Close()

$TYPES = @{'NORMAL'='Normal';'FIRE'='Fire';'WATER'='Water';'ELECTRIC'='Electric';'GRASS'='Grass';
  'ICE'='Ice';'FIGHTING'='Fighting';'POISON'='Poison';'GROUND'='Ground';'FLYING'='Flying';
  'PSYCHIC'='Psychic';'BUG'='Bug';'ROCK'='Rock';'GHOST'='Ghost';'DRAGON'='Dragon';
  'DARK'='Dark';'STEEL'='Steel';'FAIRY'='Fairy'}
$STATKEY = @{'HP'='hp';'Attack'='atk';'Defense'='def';'Special Attack'='spa';
  'Special Defense'='spd';'Speed'='spe'}

function Field($row,$i){ if($i -lt $row.Count){ return ([string]$row[$i]).Trim() } return '' }

$entries = New-Object System.Collections.ArrayList
$unmatched = New-Object System.Collections.ArrayList

# three Pokemon per row-band; each occupies base cols (name, value, learnset)
$bases = @(1,5,9)
$cur = @{ 1=$null; 5=$null; 9=$null }

function Finalize($e){
  if ($null -eq $e) { return }
  # build stats + statChg
  $stats = [ordered]@{ hp=0; atk=0; def=0; spa=0; spd=0; spe=0; total=0 }
  $statChg = [ordered]@{}
  foreach ($k in @('hp','atk','def','spa','spd','spe')) {
    $stats[$k] = [int]$e.stats[$k]
    if ($e.chg.Contains($k)) { $statChg[$k] = $e.chg[$k] }
  }
  $stats['total'] = $stats.hp+$stats.atk+$stats.def+$stats.spa+$stats.spd+$stats.spe
  $attrs = New-Object System.Collections.ArrayList
  if ($e.type) { [void]$attrs.Add([ordered]@{ label='Type'; value=$e.type }) }
  $nkey = Norm $e.name
  $dex = if ($script:name2dex.ContainsKey($nkey)) { '{0:D3}' -f $script:name2dex[$nkey] } else { [void]$script:unmatched.Add($e.name); '000' }
  $a2 = if ($e.a2 -and $e.a2 -ne $e.a1) { $e.a2 } else { '' }
  [void]$script:entries.Add([ordered]@{
    name    = $e.name
    dex     = $dex
    moves   = $e.moves.ToArray()
    changes = @()
    attrs   = $attrs.ToArray()
    notes   = $e.notes.ToArray()
    a1      = $e.a1
    a2      = $a2
    ah      = ''
    tms     = ''
    tmsNew  = ''
    tmsExtra = @()
    stats   = $stats
    statChg = $statChg
  })
}

foreach ($row in $rows) {
  foreach ($base in $bases) {
    $nm    = Field $row $base
    $val   = Field $row ($base+1)
    $learn = Field $row ($base+2)

    if ($learn -eq 'Learnset' -and $nm) {
      Finalize $cur[$base]
      if ($nameFix.ContainsKey($nm)) { $nm = $nameFix[$nm] }
      $cur[$base] = @{ name=$nm; moves=(New-Object System.Collections.ArrayList);
        notes=(New-Object System.Collections.ArrayList); stats=@{}; chg=@{};
        type=''; a1=''; a2='' }
      continue
    }
    $e = $cur[$base]
    if ($null -eq $e) { continue }

    # learnset entry: "LEVEL - Move Name"
    if ($learn -match '^\s*(\d+)\s*-\s*(.+?)\s*$') {
      [void]$e.moves.Add([ordered]@{ level=[int]$Matches[1]; name=$Matches[2].Trim(); rarity=0 })
    }

    if ($TYPES.ContainsKey($nm.ToUpper())) {
      $t = $TYPES[$nm.ToUpper()]
      if ($val -and $TYPES.ContainsKey($val.ToUpper())) { $t = "$t / " + $TYPES[$val.ToUpper()] }
      $e.type = $t
    }
    elseif ($nm -eq 'Ability 1') { $e.a1 = $val }
    elseif ($nm -eq 'Ability 2') { $e.a2 = $val }
    elseif ($STATKEY.ContainsKey($nm)) {
      if ($val -match '^\s*(\d+)\s*(?:\(([+-]?\d+)\))?') {
        $bv = [int]$Matches[1]
        $key = $STATKEY[$nm]
        $e.stats[$key] = $bv
        if ($Matches[2]) { $e.chg[$key] = [ordered]@{ from=($bv - [int]$Matches[2]); to=$bv } }
      }
    }
    elseif ($nm -match '^(Evolves at level|Now learns)') { [void]$e.notes.Add($nm) }
  }
}
foreach ($base in $bases) { Finalize $cur[$base] }

# sort by dex (unknowns last, then by name)
$sorted = $entries | Sort-Object @{ Expression = { if ($_.dex -eq '000') { 9999 } else { [int]$_.dex } } }, name

$data = [ordered]@{
  pokemon = [ordered]@{
    meta = [ordered]@{
      subtitle = ''
      blurb = @('Pokemon changes for Brutal Black (a Gen-5 / Pokemon Black hack): typing, abilities, base stats (with +/- vs vanilla), and level-up learnsets. Parsed from the official change sheet.')
    }
    entries = @($sorted)
    tmMoves = [ordered]@{}
  }
  moveInfo = [ordered]@{}
}

$json = $data | ConvertTo-Json -Depth 12 -Compress
$reg = 'window.RRSS_GAMES=window.RRSS_GAMES||{};window.RRSS_GAMES["brutalblack"]={id:"brutalblack",name:"Brutal Black",short:"Brutal Black",data:' + $json + '};'
[System.IO.File]::WriteAllText($out, $reg, (New-Object System.Text.UTF8Encoding($false)))

"Wrote {0} ({1:N0} bytes)" -f $out, ((Get-Item $out).Length)
"Species: {0}" -f $sorted.Count
if ($unmatched.Count) { "Unmatched (no dex/sprite): {0} -> {1}" -f $unmatched.Count, ($unmatched -join ', ') }
else { "All species matched a national dex number." }
