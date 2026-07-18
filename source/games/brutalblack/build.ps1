# Builds ../../../docs/data-brutalblack.js from Brutal Black's Pokemon-changes CSVs.
# Run:  powershell -ExecutionPolicy Bypass -File build.ps1
#
# Brutal Black is a Gen-5 hack with its OWN stats/types/abilities/learnsets, so it
# does NOT use the shared parse/enrich pipeline (that pulls ORAS/Gen-6 data). This
# script reads the per-region CSV grids directly (Kanto/Johto/Hoenn/Sinnoh/Unova)
# and emits a game that self-registers into window.RRSS_GAMES. First pass: Pokedex
# only (species, types, abilities, base stats with +/- changes vs vanilla, and
# level-up learnsets).
param([string]$GameDir = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$src  = Split-Path (Split-Path $GameDir -Parent) -Parent      # ...\source
$docs = Join-Path (Split-Path $src -Parent) 'docs'
$out  = Join-Path $docs 'data-brutalblack.js'
# every per-region change sheet (skip the "TM Changes" sheet, which isn't per-species)
$csvFiles = Get-ChildItem -Path $GameDir -Filter 'Brutal Black Pokemon Changes + Movesets - *.csv' |
  Where-Object { $_.Name -notmatch 'TM Changes' } | Sort-Object Name

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

# --- read a CSV grid (quote-aware) into an array of field-arrays ---
Add-Type -AssemblyName Microsoft.VisualBasic
function Read-Grid($path){
  # the sheets are UTF-8 (e.g. Nidoran's ♀/♂ signs) — read them as such
  $parser = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($path, [System.Text.Encoding]::UTF8)
  $parser.TextFieldType = [Microsoft.VisualBasic.FileIO.FieldType]::Delimited
  $parser.SetDelimiters(',')
  $parser.HasFieldsEnclosedInQuotes = $true
  $rows = New-Object System.Collections.ArrayList
  while (-not $parser.EndOfData) { [void]$rows.Add($parser.ReadFields()) }
  $parser.Close()
  return $rows
}

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
  # Nidoran: the gender sign (U+2640 female / U+2642 male) is stripped by Norm, so map
  # explicitly. Build the chars from code points to stay independent of this file's encoding.
  $dex = if ($nkey -eq 'nidoran' -and $e.name.Contains([char]0x2640)) { '029' }
    elseif ($nkey -eq 'nidoran' -and $e.name.Contains([char]0x2642)) { '032' }
    elseif ($script:name2dex.ContainsKey($nkey)) { '{0:D3}' -f $script:name2dex[$nkey] }
    else { [void]$script:unmatched.Add($e.name); '000' }
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

function Parse-Grid($rows){
  $cur = @{ 1=$null; 5=$null; 9=$null }
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
}

foreach ($f in $csvFiles) { Parse-Grid (Read-Grid $f.FullName) }

# de-dupe by name (first occurrence wins) in case a species appears in two region
# sheets. Alternate formes (Rotom-Heat, Castform-Sunny, …) have distinct names, so they
# survive; only Nidoran's two genders collide under Norm, so keep the gender in the key.
$seen = @{}; $dupes = New-Object System.Collections.ArrayList
$deduped = New-Object System.Collections.ArrayList
foreach ($e in $entries) {
  $k = Norm $e.name
  if ($e.name.Contains([char]0x2640)) { $k += 'f' } elseif ($e.name.Contains([char]0x2642)) { $k += 'm' }
  if ($seen.ContainsKey($k)) { [void]$dupes.Add($e.name); continue }
  $seen[$k] = $true; [void]$deduped.Add($e)
}

# sort by dex (unknowns last, then by name)
$sorted = $deduped | Sort-Object @{ Expression = { if ($_.dex -eq '000') { 9999 } else { [int]$_.dex } } }, name

# ---------- Moves: base info from the shared PokeAPI dump + Brutal Black's move-change overlay ----------
# Same base-info build as the RR/SS enrich step (type / category / power / accuracy / PP / desc).
$typeNm = @{}
Get-Content "$src\type_names.csv" | ForEach-Object { $p=$_ -split ','; if($p.Count -ge 3 -and $p[1] -eq '9'){ $typeNm[[int]$p[0]]=$p[2].Trim() } }
$mvName = @{}
Get-Content "$src\move_names.csv" | Select-Object -Skip 1 | ForEach-Object { $p=$_ -split ',',3; if($p.Count -ge 3 -and $p[1] -eq '9'){ $mvName[[int]$p[0]]=$p[2].Trim().Trim('"') } }
$mvDesc = @{}
Get-Content "$src\move_desc.tsv" | ForEach-Object { $p=$_ -split "`t",2; if($p.Count -eq 2){ $mvDesc[[int]$p[0]]=$p[1] } }
$catName = @{'1'='Status';'2'='Physical';'3'='Special'}
$moveInfo = [ordered]@{}
Get-Content "$src\moves.csv" | Select-Object -Skip 1 | ForEach-Object {
  $p=$_ -split ','
  $mid=[int]$p[0]; $nm=$mvName[$mid]; if(-not $nm){ return }
  $moveInfo[(Norm $nm)] = [ordered]@{
    n=$nm; t=$(if($p[3]){$typeNm[[int]$p[3]]}else{''}); c=$(if($p[9]){$catName[$p[9]]}else{''})
    pow=$(if($p[4] -ne ''){[int]$p[4]}else{$null}); acc=$(if($p[6] -ne ''){[int]$p[6]}else{$null}); pp=$(if($p[5] -ne ''){[int]$p[5]}else{$null})
    d=$(if($mvDesc.ContainsKey($mid)){$mvDesc[$mid]}else{''})
  }
}

# Parse "Brutal Black Move Changes.txt": grouped by type header, one move per line as
# "Name: change, change, …". Pull the numeric BP/Acc/PP (and type/category) into structured
# rows; keep any remaining prose as an Effect note.
$typeAlt = (($TYPES.Values | ForEach-Object { [regex]::Escape($_) }) -join '|')
$mcPath  = Join-Path $GameDir 'Brutal Black Move Changes.txt'
$attackEntries = New-Object System.Collections.ArrayList
$mcNoMatch = New-Object System.Collections.ArrayList
$prev = $null
foreach ($line in [System.IO.File]::ReadAllLines($mcPath, [System.Text.Encoding]::UTF8)) {
  $t = $line.Trim()
  if (-not $t) { continue }
  if ($t -match "^($typeAlt):$") { $prev = $null; continue }          # type header
  if ($t -notmatch ':' -or $t -match '^>') {                          # continuation / stray
    if ($prev) {
      $fx = ($prev.rows | Where-Object { $_.kind -eq 'note' -and $_.label -eq 'Effect' } | Select-Object -First 1)
      if ($fx) { $fx.value = ($fx.value + '; ' + $t).Trim('; ') }
      else { [void]$prev.rows.Add([ordered]@{ kind='note'; label='Effect'; value=$t }) }
    }
    continue
  }
  $ci   = $t.IndexOf(':')
  $name = $t.Substring(0, $ci).Trim()
  $body = $t.Substring($ci + 1).Trim()
  $key  = Norm $name
  $van  = if ($moveInfo.Contains($key)) { $moveInfo[$key] } else { $null }
  $rows = New-Object System.Collections.ArrayList

  if     ($body -match 'BP:\s*(\d+)\s*>\s*(\d+)') { [void]$rows.Add([ordered]@{ kind='change'; label='Power'; from=$Matches[1]; to=$Matches[2] }) }
  elseif ($body -match 'BP:\s*(\d+)')             { [void]$rows.Add([ordered]@{ kind='change'; label='Power'; from=$(if($van -and $van.pow -ne $null){"$($van.pow)"}else{''}); to=$Matches[1] }) }
  if ($body -match 'Acc:\s*(\d+)\s*>\s*(\d+)')    { [void]$rows.Add([ordered]@{ kind='change'; label='Accuracy'; from=$Matches[1]; to=$Matches[2] }) }
  if ($body -match 'PP:\s*(\d+)\s*>\s*(\d+)')     { [void]$rows.Add([ordered]@{ kind='change'; label='PP'; from=$Matches[1]; to=$Matches[2] }) }
  if ($body -match "now\s+(?:a\s+)?(?:special\s+)?($typeAlt)\s+(?:type|move)") { [void]$rows.Add([ordered]@{ kind='change'; label='Type'; from=$(if($van){$van.t}else{''}); to=$Matches[1] }) }
  if ($body -match 'now\s+a\s+[Ss]pecial')        { [void]$rows.Add([ordered]@{ kind='change'; label='Category'; from=$(if($van){$van.c}else{''}); to='Special' }) }

  # leftover prose (after removing the structured bits) -> Effect note
  $rem = $body
  $rem = [regex]::Replace($rem, 'BP:\s*\d+\s*>\s*\d+', '')
  $rem = [regex]::Replace($rem, 'BP:\s*\d+', '')
  $rem = [regex]::Replace($rem, 'Acc:\s*\d+\s*>\s*\d+', '')
  $rem = [regex]::Replace($rem, 'PP:\s*\d+\s*>\s*\d+', '')
  $rem = [regex]::Replace($rem, "now\s+(?:a\s+)?(?:special\s+)?($typeAlt)\s+(?:type(?:\s+move)?|move)", '')
  $rem = [regex]::Replace($rem, 'now\s+a\s+[Ss]pecial\s+move', '')
  $rem = ($rem -replace '\s+', ' ').Trim(" ,;")
  if ($rem -match '[A-Za-z0-9]') { [void]$rows.Add([ordered]@{ kind='note'; label='Effect'; value=$rem }) }

  if (-not $van) { [void]$mcNoMatch.Add($name) }
  $entry = [ordered]@{ name=$name; rows=$rows }
  [void]$attackEntries.Add($entry)
  $prev = $entry
}

# merge duplicate move lines (a few moves are listed twice in the doc, e.g. String Shot)
$byKey = [ordered]@{}
foreach ($entry in $attackEntries) {
  $k = Norm $entry.name
  if ($byKey.Contains($k)) { foreach ($r in $entry.rows) { [void]$byKey[$k].rows.Add($r) } }
  else { $byKey[$k] = $entry }
}
$attackEntries = @($byKey.Values)

# overlay the changes onto moveInfo (mirrors the RR/SS enrich overlay)
foreach ($entry in $attackEntries) {
  $key = Norm $entry.name
  if (-not $moveInfo.Contains($key)) { $moveInfo[$key] = [ordered]@{ n=$entry.name; t=''; c=''; pow=$null; acc=$null; pp=$null; d='' } }
  $mi = $moveInfo[$key]; $tmp = 0
  foreach ($r in $entry.rows) {
    if ($r.kind -eq 'change') {
      switch ($r.label) {
        'Power'    { if ([int]::TryParse([string]$r.to, [ref]$tmp)) { $mi.pow = $tmp } }
        'Accuracy' { if ([int]::TryParse([string]$r.to, [ref]$tmp)) { $mi.acc = $tmp } }
        'PP'       { if ([int]::TryParse([string]$r.to, [ref]$tmp)) { $mi.pp = $tmp } }
        'Type'     { $mi.t = $r.to }
        'Category' { $mi.c = $r.to }
      }
    } elseif ($r.kind -eq 'note' -and $r.label -eq 'Effect') { $mi['fx'] = $r.value }
  }
  $mi['chg'] = $true
}
# materialize rows arrays for JSON
foreach ($entry in $attackEntries) { $entry.rows = @($entry.rows) }

$data = [ordered]@{
  pokemon = [ordered]@{
    meta = [ordered]@{
      subtitle = ''
      blurb = @('Pokemon changes for Brutal Black (a Gen-5 / Pokemon Black hack): typing, abilities, base stats (with +/- vs vanilla), and level-up learnsets. Parsed from the official change sheet.')
    }
    entries = @($sorted)
    tmMoves = [ordered]@{}
  }
  attacks = [ordered]@{
    meta = [ordered]@{
      subtitle = ''
      blurb = @('Move changes for Brutal Black. Power / accuracy / PP tweaks plus type, category, and effect reworks. Every move''s base info is shown; changed moves are marked.')
    }
    entries = @($attackEntries)
  }
  moveInfo = $moveInfo
}

$json = $data | ConvertTo-Json -Depth 12 -Compress
$reg = 'window.RRSS_GAMES=window.RRSS_GAMES||{};window.RRSS_GAMES["brutalblack"]={id:"brutalblack",name:"Brutal Black",short:"Brutal Black",data:' + $json + '};'
[System.IO.File]::WriteAllText($out, $reg, (New-Object System.Text.UTF8Encoding($false)))

"Parsed {0} region sheets: {1}" -f $csvFiles.Count, (($csvFiles | ForEach-Object { $_.Name -replace '^.*- (.+)\.csv$','$1' }) -join ', ')
"Moves: {0} total, {1} changed" -f $moveInfo.Count, $attackEntries.Count
if ($mcNoMatch.Count) { "Move changes with no base-info match: {0} -> {1}" -f $mcNoMatch.Count, ($mcNoMatch -join ', ') }
"Wrote {0} ({1:N0} bytes)" -f $out, ((Get-Item $out).Length)
"Species: {0}" -f $sorted.Count
if ($dupes.Count) { "Duplicates dropped: {0} -> {1}" -f $dupes.Count, ($dupes -join ', ') }
if ($unmatched.Count) { "Unmatched (no dex/sprite): {0} -> {1}" -f $unmatched.Count, ($unmatched -join ', ') }
else { "All species matched a national dex number." }
