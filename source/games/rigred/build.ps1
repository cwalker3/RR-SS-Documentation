# Builds ../../../docs/data-rigred.js from Rigorous Red's Pokemon-changes CSVs.
# Run:  powershell -ExecutionPolicy Bypass -File build.ps1
#
# Rigorous Red is a Gen-3 (FireRed) hack with its OWN stats/types/abilities/learnsets.
# It reads the per-region CSV grids (Kanto/Johto/Hoenn), the Move Changes doc and the
# Mastersheet directly and emits a game that self-registers into window.RRSS_GAMES.
# Gen-3 specifics: move category is type-based (no phys/spec split), and move stats
# are rolled back to Gen-3 values via the PokeAPI move changelog.
param([string]$GameDir = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$src  = Split-Path (Split-Path $GameDir -Parent) -Parent      # ...\source
$docs = Join-Path (Split-Path $src -Parent) 'docs'
$out  = Join-Path $docs 'data-rigred.js'
# every per-region change sheet
$csvFiles = Get-ChildItem -Path $GameDir -Filter 'Rigorous Red Pokemon Changes + Movesets*.csv' |
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
# fix move-name spellings so learnset/trainer moves match the PokeAPI move info
$moveFix = @{ 'Faint Attack'='Feint Attack'; 'Hi Jump Kick'='High Jump Kick'; 'Bonemarang'='Bonemerang'; 'ViceGrip'='Vise Grip' }
function Fix-Move($m){ $m = ([string]$m).Trim(); if ($moveFix.ContainsKey($m)) { return $moveFix[$m] } return $m }
# branching families: the CSV lays stages left-to-right, which is wrong for splits
# (e.g. Eevee's eeveelutions). Map each branch child (normalized) to its true pre-evo.
$branchParent = @{
  'vaporeon'='Eevee';'jolteon'='Eevee';'flareon'='Eevee';'espeon'='Eevee';'umbreon'='Eevee';'leafeon'='Eevee';'glaceon'='Eevee';'sylveon'='Eevee'
  'gardevoir'='Kirlia';'gallade'='Kirlia'
  'hitmonlee'='Tyrogue';'hitmonchan'='Tyrogue';'hitmontop'='Tyrogue'
  'vileplume'='Gloom';'bellossom'='Gloom'
  'poliwrath'='Poliwhirl';'politoed'='Poliwhirl'
  'slowbro'='Slowpoke';'slowking'='Slowpoke'
  'ninjask'='Nincada';'shedinja'='Nincada'
  'glalie'='Snorunt';'froslass'='Snorunt'
  'huntail'='Clamperl';'gorebyss'='Clamperl'
  'silcoon'='Wurmple';'beautifly'='Silcoon';'cascoon'='Wurmple';'dustox'='Cascoon'
  'wormadam'='Burmy';'mothim'='Burmy'
}

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
$evoPairs = New-Object System.Collections.ArrayList   # [from, to] adjacent stages within a family band

# up to eight Pokemon per row-band (wide branches like Eevee's eeveelutions);
# each occupies base cols (name, value, learnset)
$bases = @(1,5,9,13,17,21,25,29)

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
  $cur = @{}; foreach ($b in $bases) { $cur[$b] = $null }
  foreach ($row in $rows) {
    # a name row is any row whose learnset-header cell says "Learnset" in some column.
    # (a few blocks omit the header and put the first move there instead, e.g. Ralts)
    $isNameRow = $false
    foreach ($b in $bases) { if ((Field $row ($b+2)) -eq 'Learnset') { $isNameRow = $true; break } }
    if ($isNameRow) {
      $band = @()
      foreach ($b in $bases) { $nb = Field $row $b; if ($nb) { if ($nameFix.ContainsKey($nb)) { $nb = $nameFix[$nb] }; $band += $nb } }
      for ($x = 1; $x -lt $band.Count; $x++) {
        $child = $band[$x]
        $parent = if ($branchParent.ContainsKey((Norm $child))) { $branchParent[(Norm $child)] } else { $band[$x-1] }
        [void]$script:evoPairs.Add(@($parent, $child))
      }
    }
    foreach ($base in $bases) {
      $nm    = Field $row $base
      $val   = Field $row ($base+1)
      $learn = Field $row ($base+2)

      if ($isNameRow -and $nm) {
        Finalize $cur[$base]
        if ($nameFix.ContainsKey($nm)) { $nm = $nameFix[$nm] }
        $cur[$base] = @{ name=$nm; moves=(New-Object System.Collections.ArrayList);
          notes=(New-Object System.Collections.ArrayList); stats=@{}; chg=@{};
          type=''; a1=''; a2='' }
        # a malformed header cell holds the first move instead of "Learnset" (e.g. Ralts)
        if ($learn -match '^\s*(\d+)\s*-\s*(.+?)\s*$') { [void]$cur[$base].moves.Add([ordered]@{ level=[int]$Matches[1]; name=(Fix-Move $Matches[2]); rarity=0 }) }
        continue
      }
      $e = $cur[$base]
      if ($null -eq $e) { continue }

      # learnset entry: "LEVEL - Move Name"
      if ($learn -match '^\s*(\d+)\s*-\s*(.+?)\s*$') {
        [void]$e.moves.Add([ordered]@{ level=[int]$Matches[1]; name=(Fix-Move $Matches[2]); rarity=0 })
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
      elseif ($nm -match '^(Evolves|Now learns)') { [void]$e.notes.Add($nm) }
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

# ---------- Moves: Gen-3 base info from the shared PokeAPI dump + Rigorous Red's overlay ----------
$typeNm = @{}
Get-Content "$src\type_names.csv" | ForEach-Object { $p=$_ -split ','; if($p.Count -ge 3 -and $p[1] -eq '9'){ $typeNm[[int]$p[0]]=$p[2].Trim() } }

# ---------- ability / type changes vs vanilla (Gen-3 accurate) -> entry.changes ----------
# the change sheet lists every mon's ability/type whether or not it changed, so detect changes
# by comparing to the base game; this drives the sidebar A / T marks and the "what changed" list.
$abilNm = @{}
Get-Content "$src\ability_names.csv" | Select-Object -Skip 1 | ForEach-Object { $p=$_ -split ',',3; if($p.Count -ge 3 -and $p[1] -eq '9'){ $abilNm[[int]$p[0]]=$p[2].Trim().Trim('"') } }
$vanAbil = @{}   # national dex -> @{ s1; s2 } (non-hidden only; hidden abilities are Gen-4+)
Get-Content "$src\pokemon_abilities.csv" | Select-Object -Skip 1 | ForEach-Object {
  $p=$_ -split ','; if($p.Count -lt 4 -or $p[2] -ne '0'){ return }
  $pkid=[int]$p[0]; if(-not $vanAbil.ContainsKey($pkid)){ $vanAbil[$pkid]=@{ s1=''; s2='' } }
  if($p[3] -eq '1'){ $vanAbil[$pkid].s1=$abilNm[[int]$p[1]] } elseif($p[3] -eq '2'){ $vanAbil[$pkid].s2=$abilNm[[int]$p[1]] }
}
$curType = @{}   # national dex -> @{ slot -> name } (current)
Get-Content "$src\pokemon_types.csv" | Select-Object -Skip 1 | ForEach-Object {
  $p=$_ -split ','; if($p.Count -lt 3){ return }
  $pkid=[int]$p[0]; if(-not $curType.ContainsKey($pkid)){ $curType[$pkid]=@{} }; $curType[$pkid][[int]$p[2]]=$typeNm[[int]$p[1]]
}
$pastType = @{}  # national dex -> @{ gen; slots } for the earliest past-gen entry that still covers Gen 3
Get-Content "$src\pokemon_types_past.csv" | Select-Object -Skip 1 | ForEach-Object {
  $p=$_ -split ','; if($p.Count -lt 4){ return }
  $pkid=[int]$p[0]; $gen=[int]$p[1]; if($gen -lt 3){ return }
  if(-not $pastType.ContainsKey($pkid) -or $gen -lt $pastType[$pkid].gen){ $pastType[$pkid]=@{ gen=$gen; slots=@{} } }
  if($gen -eq $pastType[$pkid].gen){ $pastType[$pkid].slots[[int]$p[3]]=$typeNm[[int]$p[2]] }
}
function VanSlots($pkid){ if($pastType.ContainsKey($pkid)){ return $pastType[$pkid].slots } elseif($curType.ContainsKey($pkid)){ return $curType[$pkid] } else { return $null } }
function VanTypeKey($pkid){   # sorted set of the mon's Gen-3 types, e.g. "grass+poison"
  $slots = VanSlots $pkid; if(-not $slots){ return '' }
  return (($slots.Values | ForEach-Object { Norm $_ } | Sort-Object) -join '+')
}
function VanTypeStr($pkid){   # display form in slot order, e.g. "Grass / Poison"
  $slots = VanSlots $pkid; if(-not $slots){ return '' }
  $t=$slots[1]; if($slots.ContainsKey(2) -and $slots[2]){ $t="$t / " + $slots[2] }; return $t
}
function HackTypeKey($s){ return (($s -split '/' | ForEach-Object { Norm $_ } | Where-Object { $_ } | Sort-Object) -join '+') }
foreach ($e in $sorted) {
  if ($e.dex -eq '000') { continue }
  $pkid=[int]$e.dex; $chg = New-Object System.Collections.ArrayList
  $hackType=''; foreach($at in $e.attrs){ if($at.label -eq 'Type'){ $hackType=$at.value } }
  $vtk = VanTypeKey $pkid
  if ($hackType -and $vtk -and (HackTypeKey $hackType) -ne $vtk) { [void]$chg.Add([ordered]@{ kind='change'; label='Type'; from=(VanTypeStr $pkid); to=$hackType }) }
  if ($vanAbil.ContainsKey($pkid)) {
    $va=$vanAbil[$pkid]
    if ($e.a1 -and $va.s1 -and (Norm $e.a1) -ne (Norm $va.s1)) { [void]$chg.Add([ordered]@{ kind='change'; label='Ability 1'; from=$va.s1; to=$e.a1 }) }
    if ($e.a2 -and $va.s2 -and (Norm $e.a2) -ne (Norm $va.s2)) { [void]$chg.Add([ordered]@{ kind='change'; label='Ability 2'; from=$va.s2; to=$e.a2 }) }
  }
  if ($chg.Count) { $e.changes = @($e.changes) + $chg.ToArray() }
}
$mvName = @{}
Get-Content "$src\move_names.csv" | Select-Object -Skip 1 | ForEach-Object { $p=$_ -split ',',3; if($p.Count -ge 3 -and $p[1] -eq '9'){ $mvName[[int]$p[0]]=$p[2].Trim().Trim('"') } }
$mvDesc = @{}
Get-Content "$src\move_desc.tsv" | ForEach-Object { $p=$_ -split "`t",2; if($p.Count -eq 2){ $mvDesc[[int]$p[0]]=$p[1] } }
# roll stats back to Gen 3: for each move, undo any change made in a Gen-4+ version group.
# Gen<=3 version groups (incl. Colosseum/XD): 1-7,12,13. A changelog row records the OLD
# value from before `changed_in_version_group_id`; the earliest Gen-4+ one is the Gen-3 value.
$genLE3 = @{}; foreach ($v in @(1,2,3,4,5,6,7,12,13)) { $genLE3[$v] = $true }
$chg = @{}
if (Test-Path "$src\move_changelog.csv") {
  Get-Content "$src\move_changelog.csv" | Select-Object -Skip 1 | ForEach-Object {
    $p = $_ -split ','; if ($p.Count -lt 7) { return }
    $mid=[int]$p[0]; $vg=[int]$p[1]; if ($genLE3.ContainsKey($vg)) { return }
    if (-not $chg.ContainsKey($mid)) { $chg[$mid] = New-Object System.Collections.ArrayList }
    [void]$chg[$mid].Add([ordered]@{ vg=$vg; type=$p[2]; power=$p[3]; pp=$p[4]; acc=$p[5] })
  }
}
function Gen3Val($mid, $field, $cur){
  if (-not $script:chg.ContainsKey($mid)) { return $cur }
  $rows = @($script:chg[$mid] | Where-Object { $_[$field] -ne '' } | Sort-Object vg)
  if ($rows.Count) { return $rows[0][$field] }
  return $cur
}
# Gen 3 has no physical/special split: category is decided by the move's type
$physTypes = @('Normal','Fighting','Flying','Poison','Ground','Rock','Bug','Ghost','Steel')
$moveInfo = [ordered]@{}
Get-Content "$src\moves.csv" | Select-Object -Skip 1 | ForEach-Object {
  $p=$_ -split ','
  $mid=[int]$p[0]; $nm=$mvName[$mid]; if(-not $nm){ return }
  $typeId = Gen3Val $mid 'type' $p[3]
  $powV = Gen3Val $mid 'power' $p[4]; $ppV = Gen3Val $mid 'pp' $p[5]; $accV = Gen3Val $mid 'acc' $p[6]
  $tn = if ($typeId) { $typeNm[[int]$typeId] } else { '' }
  $cat = if ($p[9] -eq '1') { 'Status' } elseif ($physTypes -contains $tn) { 'Physical' } else { 'Special' }
  $moveInfo[(Norm $nm)] = [ordered]@{
    n=$nm; t=$tn; c=$cat
    pow=$(if($powV -ne ''){[int]$powV}else{$null}); acc=$(if($accV -ne ''){[int]$accV}else{$null}); pp=$(if($ppV -ne ''){[int]$ppV}else{$null})
    d=$(if($mvDesc.ContainsKey($mid)){$mvDesc[$mid]}else{''})
  }
}

# Parse "Brutal Black Move Changes.txt": grouped by type header, one move per line as
# "Name: change, change, …". Pull the numeric BP/Acc/PP (and type/category) into structured
# rows; keep any remaining prose as an Effect note.
$typeAlt = (($TYPES.Values | ForEach-Object { [regex]::Escape($_) }) -join '|')
function TType($s){ $u=([string]$s).ToUpper(); if($TYPES.ContainsKey($u)){ $TYPES[$u] } else { $s } }   # canonical casing, e.g. "fighting" -> "Fighting"
$mcPath  = Join-Path $GameDir 'Rigorous Red Move Changes.txt'
$attackEntries = New-Object System.Collections.ArrayList
$mcNoMatch = New-Object System.Collections.ArrayList
$replacedMoves = New-Object System.Collections.ArrayList
$prev = $null; $inReplaced = $false
foreach ($line in [System.IO.File]::ReadAllLines($mcPath, [System.Text.Encoding]::UTF8)) {
  $t = $line.Trim()
  if (-not $t) { continue }
  if ($t -match '^Replaced moves:?\s*$') { $inReplaced = $true; $prev = $null; continue }
  if ($t -match "^($typeAlt):$") { $inReplaced = $false; $prev = $null; continue }   # type header
  if ($inReplaced) {   # "OldMove > NewMove": a Gen-3 move swapped out for a backported one
    if ($t -notmatch '^\*' -and $t -match '^(.+?)\s*>\s*(.+)$') { [void]$replacedMoves.Add([ordered]@{ old=$Matches[1].Trim(); new=$Matches[2].Trim() }) }
    continue
  }
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
  if ($body -match "now\s+(?:a\s+)?(?:special\s+)?($typeAlt)\s+(?:type|move)") { [void]$rows.Add([ordered]@{ kind='change'; label='Type'; from=$(if($van){$van.t}else{''}); to=(TType $Matches[1]) }) }
  elseif ($body -match "\b($typeAlt)\s*>\s*($typeAlt)\b") { [void]$rows.Add([ordered]@{ kind='change'; label='Type'; from=(TType $Matches[1]); to=(TType $Matches[2]) }) }   # "Cut: Normal > Bug"
  if ($body -match 'now\s+a\s+[Ss]pecial')        { [void]$rows.Add([ordered]@{ kind='change'; label='Category'; from=$(if($van){$van.c}else{''}); to='Special' }) }

  # leftover prose (after removing the structured bits) -> Effect note
  $rem = $body
  $rem = [regex]::Replace($rem, 'BP:\s*\d+\s*>\s*\d+', '')
  $rem = [regex]::Replace($rem, 'BP:\s*\d+', '')
  $rem = [regex]::Replace($rem, 'Acc:\s*\d+\s*>\s*\d+', '')
  $rem = [regex]::Replace($rem, 'PP:\s*\d+\s*>\s*\d+', '')
  $rem = [regex]::Replace($rem, "now\s+(?:a\s+)?(?:special\s+)?($typeAlt)\s+(?:type(?:\s+move)?|move)", '')
  $rem = [regex]::Replace($rem, "\b($typeAlt)\s*>\s*($typeAlt)\b", '')
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
# note the backported/replaced moves on the new move so they show as changed
foreach ($rm in $replacedMoves) {
  $k = Norm $rm.new
  $noteRow = [ordered]@{ kind='note'; label='Replaces'; value=$rm.old }
  if ($byKey.Contains($k)) { [void]$byKey[$k].rows.Add($noteRow) }
  else { $e2 = [ordered]@{ name=$rm.new; rows=(New-Object System.Collections.ArrayList) }; [void]$e2.rows.Add($noteRow); $byKey[$k] = $e2 }
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
        'Type'     { $mi.t = $r.to; if ($mi.c -ne 'Status') { $mi.c = if ($physTypes -contains $r.to) { 'Physical' } else { 'Special' } } }
        'Category' { $mi.c = $r.to }
      }
    } elseif ($r.kind -eq 'note' -and $r.label -eq 'Effect') { $mi['fx'] = $r.value }
  }
  $mi['chg'] = $true
}
# materialize rows arrays for JSON
foreach ($entry in $attackEntries) { $entry.rows = @($entry.rows) }

# ---------- Thief items (optional; Rigorous Red has no thief doc) ----------
$tiPath = Join-Path $GameDir 'Important Thief Items.txt'
$thiefStages = New-Object System.Collections.ArrayList
$split = ''; $stage = $null; $firstLine = $true
if (Test-Path $tiPath) {
foreach ($line in [System.IO.File]::ReadAllLines($tiPath, [System.Text.Encoding]::UTF8)) {
  $t = $line.Trim()
  if (-not $t) { continue }
  if ($firstLine) { $firstLine = $false; if ($t -match '^Important Thief Items') { continue } }
  if ($t.StartsWith('-')) {
    if (-not $stage) { $stage = [ordered]@{ title=$split; rows=(New-Object System.Collections.ArrayList) }; [void]$thiefStages.Add($stage) }
    if ($t -match '^-\s*(.+?)\s*\(([^)]*)\)\s*$') { [void]$stage.rows.Add([ordered]@{ name=$Matches[2].Trim(); item=$Matches[1].Trim() }) }
    else { [void]$stage.rows.Add([ordered]@{ name=''; item=$t.TrimStart('-').Trim() }) }
    continue
  }
  if ($t.EndsWith(':')) {
    $loc = $t.TrimEnd(':').Trim()
    $stage = [ordered]@{ title=$(if ($split) { "$split - $loc" } else { $loc }); rows=(New-Object System.Collections.ArrayList) }
    [void]$thiefStages.Add($stage)
    continue
  }
  $split = $t; $stage = $null                                    # gym-split header
}
}
$thiefStages = @($thiefStages | Where-Object { $_.rows.Count -gt 0 })
foreach ($s in $thiefStages) { $s.rows = @($s.rows) }

# ---------- Areas (wild encounters + trainers) + Gifts, from the Mastersheet ----------
$msPath = Join-Path $GameDir 'Rigorous Red Mastersheet.txt'
$ml = [System.IO.File]::ReadAllLines($msPath, [System.Text.Encoding]::UTF8)
$reTeam = [regex]'^(?<sp>.+?)\s*\((?<lv>\d+)\)\s*(?:\[(?<nat>[^\]]+)\]\s*)?(?:@\s*(?<item>.+?)\s*/\s*)?(?<ab>[^:@]+?)\s*:\s*(?<mv>.*)$'
$reWild = [regex]'^(?<method>[A-Za-z][A-Za-z /]*?)\s*\((?<lvl>\d+)\)[^:]*:\s*(?<list>.+)$'
$reGift = [regex]'^Gift(?:\s*\(\d+\))?\s*:\s*(?<g>.+)$'
$reHdr  = [regex]'^(?<h>.+?):\s*$'
$reSp   = [regex]'(?<name>[^,()]+?)\s*\((?<pct>\d+)%\)'   # global: tolerant of missing commas

$areas = New-Object System.Collections.ArrayList
$giftRows = New-Object System.Collections.ArrayList
$itemRows = New-Object System.Collections.ArrayList
$area = $null; $trainer = $null; $baseTName = ''; $choice = ''; $noteBuf = $null; $curSplit = ''
$pendingNotes = New-Object System.Collections.ArrayList

function New-BBArea($name){
  $split = $script:curSplit
  # same location in the same split = one area; a revisit in a later split becomes its own
  # area (kept in story order) labelled with the split, so trainers stay ordered
  foreach ($a in $script:areas) { if ($a.baseName -eq $name -and $a.homeSplit -eq $split) { return $a } }
  $exists = $false; foreach ($a in $script:areas) { if ($a.baseName -eq $name) { $exists = $true; break } }
  $disp = if ($exists -and $split) { "$name ($split)" } else { $name }
  $a = [ordered]@{ name=$disp; baseName=$name; wild=(New-Object System.Collections.ArrayList); trainers=(New-Object System.Collections.ArrayList); notes=(New-Object System.Collections.ArrayList); homeSplit=$split }
  [void]$script:areas.Add($a); return $a
}
function End-BBTrainer(){
  if ($script:trainer -and $script:trainer.team.Count -gt 0 -and $script:area) { [void]$script:area.trainers.Add($script:trainer) }
  $script:trainer = $null
}
function New-BBTrainer($name){
  # optional fights are tagged "(OPTIONAL…)" in the sheet; item-guard bosses read "(To get …)".
  # flag them and strip the bare OPTIONAL marker (keeping any "GIVES X" detail as a plain aside).
  $opt = $false
  if ($name -match '(?i)\(OPTIONAL\b') { $opt = $true; $name = ($name -replace '(?i)\(OPTIONAL,\s*', '(' -replace '(?i)\s*\(OPTIONAL\)', '').Trim() }
  elseif ($name -match '(?i)\(To get ') { $opt = $true }
  return [ordered]@{ id=''; name=$name; optional=$opt; badge=$(if($name -match 'Gym Leader'){'Leader'}else{''}); choice=''; splitAt=$script:curSplit; split=''; notes=(New-Object System.Collections.ArrayList); team=(New-Object System.Collections.ArrayList) } }
# a note that reads like it's about the upcoming battle attaches to that trainer, not the area
function Is-FightNote($n){ return ($n -match '(?i)\bfight\b|\bbattle\b|do this|doing this|wait until|before you|can.?t switch|tag battle|rematch') }
function Flush-Notes(){ foreach ($n in $script:pendingNotes) { if ($script:area) { [void]$script:area.notes.Add($n) } }; $script:pendingNotes.Clear() }
function Assign-Notes($tr){ foreach ($n in $script:pendingNotes) { if (Is-FightNote $n) { [void]$tr.notes.Add($n) } elseif ($script:area) { [void]$script:area.notes.Add($n) } }; $script:pendingNotes.Clear() }
function NextIsTeam($idx){
  for ($j=$idx+1; $j -lt $ml.Count; $j++) {
    $s = $ml[$j].Trim()
    if (-not $s -or $s.StartsWith('*') -or $s -match '^If you chose' -or $s -match '\(Level Cap:') { continue }
    return ($reTeam.IsMatch($s) -and $s -notmatch '\(\d+%\)')   # a wild-encounter line is not a team
  }
  return $false
}

for ($i=0; $i -lt $ml.Count; $i++) {
  $t = $ml[$i].Trim()
  if (-not $t) { continue }
  # bullet continuation of a note (e.g. the "now gives: -1 Exp Share …" gift list); handles - and en/em dashes / bullet
  if ($noteBuf -ne $null -and $t.Length -gt 0 -and (@('-',[char]0x2013,[char]0x2014,[char]0x2022) -contains $t.Substring(0,1))) { $noteBuf += [char]10 + $t; continue }
  # any other line ends a pending note (buffered; assigned to the next trainer or area)
  if ($noteBuf -ne $null) { [void]$pendingNotes.Add($noteBuf); $noteBuf = $null }
  if ($t -match '\(Level Cap:') { Flush-Notes; $curSplit = ($t -replace '\s*\(Level Cap:.*$','').Trim(); continue }   # gym split / phase
  if ($t.StartsWith('*')) {
    $n = $t.TrimStart('*').Trim()
    if ($n -match '^(.+?)\s*>\s*(.+)$') { [void]$itemRows.Add(@($(if($area){$area.name}else{''}), $Matches[1].Trim(), $Matches[2].Trim())) }  # item-ball swap
    else { $noteBuf = $n }                                # prose note (may gather bullet lines)
    continue
  }

  $mg = $reGift.Match($t)
  if ($mg.Success) { Flush-Notes; [void]$giftRows.Add(@($(if($area){$area.name}else{''}), $mg.Groups['g'].Value.Trim())); continue }

  $mw = $reWild.Match($t)
  if ($mw.Success -and $mw.Groups['list'].Value -match '\(\d+%\)') {
    Flush-Notes
    if ($area) {
      $sp = New-Object System.Collections.ArrayList
      foreach ($sm in $reSp.Matches($mw.Groups['list'].Value)) {
        $nm = $sm.Groups['name'].Value.Trim()
        if ($nm) { $pc = [int]$sm.Groups['pct'].Value; [void]$sp.Add([ordered]@{ name=$nm; pct=$pc; rare=($pc -le 5) }) }
      }
      if ($sp.Count) { [void]$area.wild.Add([ordered]@{ method=$mw.Groups['method'].Value.Trim(); level=$mw.Groups['lvl'].Value; species=@($sp) }) }
    }
    continue
  }

  if ($t -match '^If you chose\s+(\w+)') {
    $choice = $Matches[1]                                 # the chosen starter (Snivy / Tepig / Oshawott)
    if (NextIsTeam $i) {                                  # variant teams follow directly (pattern 1)
      if ($trainer -and $trainer.team.Count -gt 0) { End-BBTrainer; $trainer = New-BBTrainer $baseTName; $trainer.choice = $choice }
      elseif ($trainer) { $trainer.choice = $choice }
    } else { End-BBTrainer }                              # a header follows (pattern 2): keep $choice for it
    continue
  }

  $mt = $reTeam.Match($t)
  if ($mt.Success) {
    if (-not $trainer) { $baseTName = 'Trainer'; $trainer = New-BBTrainer $baseTName }
    $moves = @()
    if ($mt.Groups['mv'].Value.Trim()) { $moves = @(($mt.Groups['mv'].Value -split ',') | ForEach-Object { Fix-Move $_ } | Where-Object { $_ }) }
    [void]$trainer.team.Add([ordered]@{
      species=$mt.Groups['sp'].Value.Trim(); level=$mt.Groups['lv'].Value
      item=$(if($mt.Groups['item'].Success){$mt.Groups['item'].Value.Trim()}else{''})
      ability=$mt.Groups['ab'].Value.Trim(); nature=$(if($mt.Groups['nat'].Success){$mt.Groups['nat'].Value.Trim()}else{''}); moves=$moves
    })
    continue
  }

  $mh = $reHdr.Match($t)
  if ($mh.Success) {
    $h = $mh.Groups['h'].Value.Trim()
    End-BBTrainer
    if (NextIsTeam $i) {                                  # trainer header
      $baseTName = $h
      $trainer = New-BBTrainer $h
      if ($choice) { $trainer.choice = $choice }
      Assign-Notes $trainer                              # pending fight notes attach to this trainer
    }
    # a ':' line that reads like a sentence (lowercase function words) is a note that
    # introduces a fight, not a location — buffer it for the next trainer / area.
    # ignore words inside "(…)" so a real location with a parenthetical aside
    # (e.g. "Cinnabar Gym (…you still have to fight the trainers…) (PERMA SUN):") still counts.
    elseif (($h -replace '\([^)]*\)','') -cmatch '\b(you|your|have|has|to|and|get|got|back|this|that|until|before|after|when|while|if|can|will|would|should|must|one|two|three|do|does|doing|done|fight|fights|wait|instead|only|available|between|make|sure|switch|teams|first|down|far|least|but|so|then|give|gives)\b') {
      [void]$pendingNotes.Add($h)
    }
    elseif ($h -match '^B?\d+F$') { Flush-Notes }         # a floor sub-header (B1F, 1F, …) — stay in the current area
    elseif ($h -match '^\s*[-–—•]') { Flush-Notes }        # a bullet that ends in ':' (e.g. "-official calc:") — not a location
    # real locations only start after the first gym split; the intro (Notes, Credits,
    # Mart changes, official calc, …) all sits before it, so skip headers until then
    elseif ($curSplit -and $h -ne 'Notes') { Flush-Notes; $area = New-BBArea $h }
    $choice = ''
    continue
  }
}
if ($noteBuf -ne $null) { [void]$pendingNotes.Add($noteBuf); $noteBuf = $null }
Flush-Notes
End-BBTrainer

# TM slot changes (which move each TM now teaches)
$tmChangeRows = New-Object System.Collections.ArrayList
$tmcPath = Join-Path $GameDir 'Brutal Black Pokemon Changes + Movesets - TM Changes.csv'
if (Test-Path $tmcPath) {
  foreach ($cl in [System.IO.File]::ReadAllLines($tmcPath, [System.Text.Encoding]::UTF8)) {
    $p = $cl -split ','
    if ($p.Count -ge 4 -and $p[1].Trim() -match '^TM\d+') { [void]$tmChangeRows.Add(@($p[1].Trim(), $p[2].Trim(), $p[3].Trim())) }
  }
}

# group documented item-ball swaps by location for the per-area item checklist
$itemsByLoc = @{}
foreach ($ir in $itemRows) {
  $loc = $ir[0]; if (-not $loc) { continue }
  if (-not $itemsByLoc.ContainsKey($loc)) { $itemsByLoc[$loc] = New-Object System.Collections.ArrayList }
  [void]$itemsByLoc[$loc].Add(@($ir[1], $ir[2]))
}
# the Kanto starter is given in Pallet Town but isn't a "Gift:" line in the doc — add it
if (($areaData | Where-Object { $_.name -eq 'Pallet Town' }) -or ($areas | Where-Object { $_.name -eq 'Pallet Town' })) {
  [void]$giftRows.Add(@('Pallet Town', 'Bulbasaur/Charmander/Squirtle (100%)'))
}
# group gifts (incl. the starter choice) by location so they show in the area too
$giftsByLoc = @{}
foreach ($gr in $giftRows) {
  $loc = $gr[0]; if (-not $loc) { continue }
  if (-not $giftsByLoc.ContainsKey($loc)) { $giftsByLoc[$loc] = New-Object System.Collections.ArrayList }
  [void]$giftsByLoc[$loc].Add($gr[1])
}

# assign stable trainer ids; wrap into RR/SS's area/roster shape (skip empty locations)
$areaData = New-Object System.Collections.ArrayList
foreach ($a in $areas) {
  $ti = 0; foreach ($tr in $a.trainers) {
    $tr.id = (Norm $a.name) + '-' + (Norm $tr.name) + $(if ($tr.choice) { '-' + (Norm $tr.choice) } else { '' }) + "-$ti"
    # tag a fight that belongs to a different gym split than the area's first visit
    if ($tr.splitAt -and $a.homeSplit -and $tr.splitAt -ne $a.homeSplit) { $tr.split = $tr.splitAt } else { $tr.split = '' }
    [void]$tr.Remove('splitAt')
    $tr.notes = @($tr.notes)
    foreach ($m in $tr.team) { $m.moves = @($m.moves) }; $tr.team = @($tr.team); $ti++
  }
  $wild = @($a.wild); $trs = @($a.trainers)
  $items = @()
  if ($itemsByLoc.ContainsKey($a.name)) {
    $il = New-Object System.Collections.ArrayList; $ic = 0
    foreach ($pair in $itemsByLoc[$a.name]) { [void]$il.Add([ordered]@{ id=(Norm $a.name) + "-item-$ic"; name=$pair[1]; was=$pair[0] }); $ic++ }
    $items = @($il)
  }
  $notes = @($a.notes)
  $gifts = @(); if ($giftsByLoc.ContainsKey($a.name)) { $gifts = @($giftsByLoc[$a.name]) }
  if ($wild.Count -eq 0 -and $trs.Count -eq 0 -and $items.Count -eq 0 -and $notes.Count -eq 0 -and $gifts.Count -eq 0) { continue }
  $rosters = @(); if ($trs.Count) { $rosters = @([ordered]@{ title='Trainers'; kind=''; trainers=$trs }) }
  [void]$areaData.Add([ordered]@{ name=$a.name; wild=$wild; rosters=$rosters; special=@(); items=$items; notes=$notes; gifts=$gifts })
}

# areas the doc only mentions in prose around Celadon City: the Eevee at the Department
# Store, and the Game Corner (its own separate encounter). Insert them after Celadon City.
$celIdx = -1
for ($x = 0; $x -lt $areaData.Count; $x++) { if ($areaData[$x].name -eq 'Celadon City') { $celIdx = $x; break } }
if ($celIdx -ge 0) {
  $dept = [ordered]@{ name='Celadon Department Store'; wild=@(); rosters=@(); special=@(); items=@(); notes=@('Eevee is on 1F (counts as its own encounter). TM40, TM03, TM20 and TM34 can also be found here.'); gifts=@('Eevee (100%)') }
  # the mastersheet doesn't list the prize species, so use the classic FireRed Game Corner set
  $cornerMons = @('Abra','Clefairy','Dratini','Scyther','Porygon') | ForEach-Object { [ordered]@{ name=$_ } }
  $corner = [ordered]@{ name='Celadon Game Corner'; wild=@([ordered]@{ method='Game Corner'; level=''; species=@($cornerMons) }); rosters=@(); special=@(); items=@();
    notes=@('Prize Pokemon bought with coins (classic FireRed set): Abra (180), Clefairy (500), Dratini (2800), Scyther (5500), Porygon (9999). Pick one - it counts as a separate encounter.'); gifts=@() }
  $areaData.Insert($celIdx + 1, $corner)
  $areaData.Insert($celIdx + 1, $dept)
}

# ---------- Evolutions: family adjacency (from CSV bands) + level (from "Evolves at level X" notes) ----------
$evoLevel = @{}; $evoMethod = @{}
foreach ($e in $entries) {
  foreach ($n in $e.notes) {
    if ($n -match '^Evolves at level\s*(\d+)') { $evoLevel[(Norm $e.name)] = $Matches[1]; $evoMethod[(Norm $e.name)] = "Level $($Matches[1])"; break }
    elseif ($n -match '^Evolves\s+(?:via\s+)?(.+?)\.?\s*$') {
      $m = $Matches[1] -replace '^leveling up while holding (.+?) during the (day|night)$','$1 ($2)' -replace '^using (?:an? )?','' -replace '^a (.+? Stone)$','$1'
      $evoMethod[(Norm $e.name)] = $m; break
    }
  }
}
$evoObjs = New-Object System.Collections.ArrayList
$evoSeen = @{}
foreach ($pair in $evoPairs) {
  $fk = Norm $pair[0]
  $k = "$fk>$(Norm $pair[1])"
  if ($evoSeen.ContainsKey($k)) { continue }
  $evoSeen[$k] = $true
  # the sheet writes the method ("Evolves at level X" / "Evolves via …") on the RESULT stage
  $tk = Norm $pair[1]
  $lvl = if ($evoMethod.ContainsKey($tk)) { $evoMethod[$tk] } else { '' }
  $dex = if ($name2dex.ContainsKey($fk)) { [int]$name2dex[$fk] } else { 9999 }
  [void]$evoObjs.Add([pscustomobject]@{ from=$pair[0]; to=$pair[1]; lvl=$lvl; dex=$dex })
}
# sort the objects (not the arrays — piping arrays through Sort-Object corrupts them), then emit rows
$evoRows = New-Object System.Collections.ArrayList
foreach ($o in ($evoObjs | Sort-Object dex, from)) { [void]$evoRows.Add(@($o.from, $o.to, $o.lvl)) }

# attach each species' forward evolution to the PRE-evo, and drop the misplaced raw
# "Evolves at level X" note (the sheet writes it on the result stage)
$evoInto = @{}
foreach ($o in $evoObjs) {
  $fk = Norm $o.from
  if (-not $evoInto.ContainsKey($fk)) { $evoInto[$fk] = New-Object System.Collections.ArrayList }
  [void]$evoInto[$fk].Add([ordered]@{ into=$o.to; level=$o.lvl })
}
foreach ($e in $sorted) {
  $k = Norm $e.name
  $e.evo = if ($evoInto.ContainsKey($k)) { @($evoInto[$k]) } else { @() }
  $e.notes = @($e.notes | Where-Object { $_ -notmatch '^Evolves' })
}

# ---------- keep only moves actually in Brutal Black ----------
# a learnset move, a trainer's move, a move a TM teaches, or a move the hack changed.
$usedMoves = @{}
function Mark-Used($nm){ $k = Norm $nm; if ($k) { $script:usedMoves[$k] = $true } }
foreach ($e in $sorted) { foreach ($m in $e.moves) { Mark-Used $m.name } }
foreach ($a in $areaData) { foreach ($r in $a.rosters) { foreach ($tr in $r.trainers) { foreach ($tm in $tr.team) { foreach ($mv in $tm.moves) { Mark-Used $mv } } } } }
foreach ($en in $attackEntries) { Mark-Used $en.name }
foreach ($row in $tmChangeRows) { Mark-Used $row[2] }                         # move each TM now teaches
foreach ($ir in $itemRows) { if ($ir[2] -match '^TM\d+\s+(.+)$') { Mark-Used $Matches[1] } }  # TM found in a ball
$moveInfoFiltered = [ordered]@{}
foreach ($k in $moveInfo.Keys) { if ($usedMoves.ContainsKey($k)) { $moveInfoFiltered[$k] = $moveInfo[$k] } }
$moveInfo = $moveInfoFiltered

# ---------- species that appear in-game (wild / trainer / gift) but aren't in the change sheets ----------
# Give them a national dex so their sprite shows and they can be caught. Species with a
# unique dex also get a minimal stub entry (so they appear in the box / have a page);
# alternate forms that share an existing entry's dex only get a name->dex mapping.
$stubDexFix = @{ 'marshstomp'=259; 'carvahna'=318; 'deoxys'=386 }
function Resolve-Dex($name){
  $k = Norm $name
  if ($script:stubDexFix.ContainsKey($k)) { return $script:stubDexFix[$k] }
  if ($script:name2dex.ContainsKey($k)) { return $script:name2dex[$k] }
  $base = ($name -split '[- ]')[0]; $bk = Norm $base           # strip a form suffix, retry the base species
  if ($script:name2dex.ContainsKey($bk)) { return $script:name2dex[$bk] }
  return $null
}
$entryKeys = @{}; $entryDex = @{}
foreach ($e in $sorted) { $entryKeys[(Norm $e.name)] = $true; $entryDex[$e.dex] = $true }
$refSpecies = [ordered]@{}
foreach ($a in $areaData) {
  foreach ($w in $a.wild) { foreach ($s in $w.species) { $refSpecies[$s.name] = $true } }
  foreach ($r in $a.rosters) { foreach ($t in $r.trainers) { foreach ($m in $t.team) { $refSpecies[$m.species] = $true } } }
  foreach ($g in $a.gifts) { foreach ($o in (($g -replace '\s*\(\d+%\)\s*$','') -split '/')) { $refSpecies[$o.Trim()] = $true } }
}
$nameDex = [ordered]@{}
$stubs = New-Object System.Collections.ArrayList
$stubUnresolved = New-Object System.Collections.ArrayList
foreach ($nm in $refSpecies.Keys) {
  if (-not $nm -or $entryKeys.ContainsKey((Norm $nm))) { continue }
  $dex = Resolve-Dex $nm
  if ($null -eq $dex) { [void]$stubUnresolved.Add($nm); continue }
  $dexStr = '{0:D3}' -f $dex
  $nameDex[(Norm $nm)] = $dexStr
  if (-not $entryDex.ContainsKey($dexStr)) {
    $entryDex[$dexStr] = $true
    [void]$stubs.Add([ordered]@{ name=$nm; dex=$dexStr; moves=@(); changes=@(); attrs=@(); notes=@('Appears in-game but isn''t detailed in the Rigorous Red change sheets.'); a1=''; a2=''; ah=''; tms=''; tmsNew=''; tmsExtra=@(); stats=[ordered]@{hp=0;atk=0;def=0;spa=0;spd=0;spe=0;total=0}; statChg=[ordered]@{}; evo=@() })
  }
}
if ($stubs.Count) {
  $all = New-Object System.Collections.ArrayList
  foreach ($e in $sorted) { [void]$all.Add($e) }
  foreach ($e in $stubs) { [void]$all.Add($e) }
  $sorted = $all | Sort-Object @{ Expression = { if ($_.dex -eq '000') { 9999 } else { [int]$_.dex } } }, name
}

$data = [ordered]@{
  pokemon = [ordered]@{
    meta = [ordered]@{
      subtitle = ''
      blurb = @('Pokemon changes for Rigorous Red (a Gen-3 / FireRed hack): typing, abilities, base stats (with +/- vs vanilla), and level-up learnsets. Parsed from the official change sheet.')
    }
    entries = @($sorted)
    tmMoves = [ordered]@{}
  }
  nameDex = $nameDex

  attacks = [ordered]@{
    meta = [ordered]@{
      subtitle = ''
      blurb = @('Move changes for Rigorous Red (Gen 3: category is type-based, stats are Gen-3 accurate). Power / accuracy / PP tweaks plus type, category, and effect reworks. Every move''s base info is shown; changed moves are marked.')
    }
    entries = @($attackEntries)
  }
  moveInfo = $moveInfo
  thief = [ordered]@{
    intro = 'Important items you can steal with Thief / Covet from wild Pokemon, by location. Grouped by gym split in story order.'
    stages = @($thiefStages)
  }
  areas = [ordered]@{
    meta = [ordered]@{
      subtitle = ''
      blurb = @('Wild encounters and trainer teams for every location, in story order, from the Rigorous Red mastersheet. Tick wild Pokemon as caught and mark trainers beaten to track your run.')
      starters = @('Bulbasaur','Charmander','Squirtle')
    }
    areas = @($areaData)
  }
  gifts = [ordered]@{
    meta = [ordered]@{
      subtitle = ''
      blurb = @('Gift and starter Pokemon by location, from the mastersheet.')
    }
    blocks = @(
      [ordered]@{ type='table'; columns=@('Location','Gift'); rows=@($giftRows) }
    )
  }
  items = [ordered]@{
    meta = [ordered]@{
      subtitle = ''
      blurb = @('Item changes in Rigorous Red: item balls that were swapped, by location.')
    }
    blocks = @(
      [ordered]@{ type='heading'; text='TM slot changes' }
      [ordered]@{ type='table'; columns=@('TM','Old move','New move'); rows=@($tmChangeRows) }
      [ordered]@{ type='heading'; text='Item ball swaps' }
      [ordered]@{ type='table'; columns=@('Location','Was','Now'); rows=@($itemRows) }
    )
  }
  evolution = [ordered]@{
    meta = [ordered]@{
      subtitle = ''
      blurb = @('Evolution lines from the change sheets. Level is shown where the sheet notes one; stone/trade/other methods are left blank.')
    }
    blocks = @(
      [ordered]@{ type='table'; columns=@('Pokemon','Evolves into','Method'); rows=@($evoRows) }
    )
  }
}

$json = $data | ConvertTo-Json -Depth 12 -Compress
$reg = 'window.RRSS_GAMES=window.RRSS_GAMES||{};window.RRSS_GAMES["rigred"]={id:"rigred",name:"Rigorous Red",short:"Rigorous Red",data:' + $json + '};'
[System.IO.File]::WriteAllText($out, $reg, (New-Object System.Text.UTF8Encoding($false)))

"Parsed {0} region sheets: {1}" -f $csvFiles.Count, (($csvFiles | ForEach-Object { $_.Name -replace '^.*- (.+)\.csv$','$1' }) -join ', ')
"Moves: {0} in-game (filtered to used/changed), {1} changed" -f $moveInfo.Count, $attackEntries.Count
if ($mcNoMatch.Count) { "Move changes with no base-info match: {0} -> {1}" -f $mcNoMatch.Count, ($mcNoMatch -join ', ') }
"Thief: {0} location cards, {1} items" -f $thiefStages.Count, (($thiefStages | ForEach-Object { $_.rows.Count } | Measure-Object -Sum).Sum)
$trCount = ($areaData | ForEach-Object { ($_.rosters | ForEach-Object { $_.trainers.Count } | Measure-Object -Sum).Sum } | Measure-Object -Sum).Sum
$wildCount = ($areaData | ForEach-Object { $_.wild.Count } | Measure-Object -Sum).Sum
"Areas: {0} locations, {1} wild tables, {2} trainers" -f $areaData.Count, $wildCount, $trCount
"Gifts: {0} rows" -f $giftRows.Count
"Items: {0} TM slot changes, {1} item-ball swaps" -f $tmChangeRows.Count, $itemRows.Count
"Evolutions: {0} lines ({1} with a level)" -f $evoRows.Count, (@($evoRows | Where-Object { $_[2] }).Count)
"Extra species (in-game, not in sheets): {0} stub entries, {1} name->dex" -f $stubs.Count, $nameDex.Count
if ($stubUnresolved.Count) { "  UNRESOLVED (no sprite): {0} -> {1}" -f $stubUnresolved.Count, ($stubUnresolved -join ', ') }
"Wrote {0} ({1:N0} bytes)" -f $out, ((Get-Item $out).Length)
"Species: {0}" -f $sorted.Count
if ($dupes.Count) { "Duplicates dropped: {0} -> {1}" -f $dupes.Count, ($dupes -join ', ') }
if ($unmatched.Count) { "Unmatched (no dex/sprite): {0} -> {1}" -f $unmatched.Count, ($unmatched -join ', ') }
else { "All species matched a national dex number." }
