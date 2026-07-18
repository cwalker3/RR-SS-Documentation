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
# fix move-name spellings so learnset/trainer moves match the PokeAPI move info
$moveFix = @{ 'Faint Attack'='Feint Attack'; 'Hi Jump Kick'='High Jump Kick'; 'Bonemarang'='Bonemerang'; 'ViceGrip'='Vise Grip' }
function Fix-Move($m){ $m = ([string]$m).Trim(); if ($moveFix.ContainsKey($m)) { return $moveFix[$m] } return $m }

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
    # a name row carries the family's stages left-to-right; record evolution adjacency
    $band = @()
    foreach ($b in $bases) { if ((Field $row ($b+2)) -eq 'Learnset') { $nb = Field $row $b; if ($nb) { if ($nameFix.ContainsKey($nb)) { $nb = $nameFix[$nb] }; $band += $nb } } }
    for ($x = 0; $x -lt $band.Count - 1; $x++) { [void]$script:evoPairs.Add(@($band[$x], $band[$x+1])) }
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
  if ($p[2] -and [int]$p[2] -gt 5) { return }   # Gen-5 hack: drop Gen-6+ moves (Blood Moon, etc.)
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

# ---------- Thief items ----------
# "<Gym> Split" headers group "<Location>:" headers, each followed by "-Item (Pokemon)" lines.
$tiPath = Join-Path $GameDir 'Brutal Black Important Thief Items.txt'
$thiefStages = New-Object System.Collections.ArrayList
$split = ''; $stage = $null; $firstLine = $true
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
$thiefStages = @($thiefStages | Where-Object { $_.rows.Count -gt 0 })
foreach ($s in $thiefStages) { $s.rows = @($s.rows) }

# ---------- Areas (wild encounters + trainers) + Gifts, from the Mastersheet ----------
$msPath = Join-Path $GameDir 'Brutal Black Mastersheet.txt'
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

function New-BBArea($name){
  foreach ($a in $script:areas) { if ($a.name -eq $name) { return $a } }   # merge repeat visits
  $a = [ordered]@{ name=$name; wild=(New-Object System.Collections.ArrayList); trainers=(New-Object System.Collections.ArrayList); notes=(New-Object System.Collections.ArrayList); homeSplit=$script:curSplit }
  [void]$script:areas.Add($a); return $a
}
function End-BBTrainer(){
  if ($script:trainer -and $script:trainer.team.Count -gt 0 -and $script:area) { [void]$script:area.trainers.Add($script:trainer) }
  $script:trainer = $null
}
function New-BBTrainer($name){ return [ordered]@{ id=''; name=$name; badge=$(if($name -match 'Gym Leader'){'Leader'}else{''}); choice=''; splitAt=$script:curSplit; split=''; team=(New-Object System.Collections.ArrayList) } }
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
  # any other line ends a pending note
  if ($noteBuf -ne $null) { if ($area) { [void]$area.notes.Add($noteBuf) }; $noteBuf = $null }
  if ($t -match '\(Level Cap:') { $curSplit = ($t -replace '\s*\(Level Cap:.*$','').Trim(); continue }   # gym split / phase
  if ($t.StartsWith('*')) {
    $n = $t.TrimStart('*').Trim()
    if ($n -match '^(.+?)\s*>\s*(.+)$') { [void]$itemRows.Add(@($(if($area){$area.name}else{''}), $Matches[1].Trim(), $Matches[2].Trim())) }  # item-ball swap
    else { $noteBuf = $n }                                # prose note (may gather bullet lines)
    continue
  }

  $mg = $reGift.Match($t)
  if ($mg.Success) { [void]$giftRows.Add(@($(if($area){$area.name}else{''}), $mg.Groups['g'].Value.Trim())); continue }

  $mw = $reWild.Match($t)
  if ($mw.Success -and $mw.Groups['list'].Value -match '\(\d+%\)') {
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
      ability=$mt.Groups['ab'].Value.Trim(); moves=$moves
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
    }
    # a ':' line that reads like a sentence (lowercase function words) is a note that
    # introduces a fight, not a location — keep the following trainers in the current area
    elseif ($h -cmatch '\b(you|your|have|has|to|and|get|got|back|this|that|until|before|after|when|while|if|can|will|would|should|must|one|two|three|do|does|doing|done|fight|fights|wait|instead|only|available|between|make|sure|switch|teams|first|down|far|least|but|so|then|give|gives)\b') {
      if ($area) { [void]$area.notes.Add($h) }
    }
    elseif ($h -ne 'Notes') { $area = New-BBArea $h }     # location header ('Notes' = doc intro, skip)
    $choice = ''
    continue
  }
}
if ($noteBuf -ne $null -and $area) { [void]$area.notes.Add($noteBuf) }
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
# group gifts (incl. the Nuvema starter choice) by location so they show in the area too
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

# ---------- Evolutions: family adjacency (from CSV bands) + level (from "Evolves at level X" notes) ----------
$evoLevel = @{}
foreach ($e in $entries) {
  foreach ($n in $e.notes) { if ($n -match 'Evolves at level\s*(\d+)') { $evoLevel[(Norm $e.name)] = $Matches[1]; break } }
}
$evoObjs = New-Object System.Collections.ArrayList
$evoSeen = @{}
foreach ($pair in $evoPairs) {
  $fk = Norm $pair[0]
  $k = "$fk>$(Norm $pair[1])"
  if ($evoSeen.ContainsKey($k)) { continue }
  $evoSeen[$k] = $true
  # the sheet writes "Evolves at level X" on the RESULT stage, so the level lives on `to`
  $tk = Norm $pair[1]
  $lvl = if ($evoLevel.ContainsKey($tk)) { 'Level ' + $evoLevel[$tk] } else { '' }
  $dex = if ($name2dex.ContainsKey($fk)) { [int]$name2dex[$fk] } else { 9999 }
  [void]$evoObjs.Add([pscustomobject]@{ from=$pair[0]; to=$pair[1]; lvl=$lvl; dex=$dex })
}
# sort the objects (not the arrays — piping arrays through Sort-Object corrupts them), then emit rows
$evoRows = New-Object System.Collections.ArrayList
foreach ($o in ($evoObjs | Sort-Object dex, from)) { [void]$evoRows.Add(@($o.from, $o.to, $o.lvl)) }

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
  thief = [ordered]@{
    intro = 'Important items you can steal with Thief / Covet from wild Pokemon, by location. Grouped by gym split in story order.'
    stages = @($thiefStages)
  }
  areas = [ordered]@{
    meta = [ordered]@{
      subtitle = ''
      blurb = @('Wild encounters and trainer teams for every location, in story order, from the Brutal Black mastersheet. Tick wild Pokemon as caught and mark trainers beaten to track your run.')
      starters = @('Snivy','Tepig','Oshawott')
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
      blurb = @('Item changes in Brutal Black: which move each TM now teaches, and the item balls that were swapped for TMs (by location).')
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
      [ordered]@{ type='table'; columns=@('Pokemon','Evolves into','Level'); rows=@($evoRows) }
    )
  }
}

$json = $data | ConvertTo-Json -Depth 12 -Compress
$reg = 'window.RRSS_GAMES=window.RRSS_GAMES||{};window.RRSS_GAMES["brutalblack"]={id:"brutalblack",name:"Brutal Black",short:"Brutal Black",data:' + $json + '};'
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
"Wrote {0} ({1:N0} bytes)" -f $out, ((Get-Item $out).Length)
"Species: {0}" -f $sorted.Count
if ($dupes.Count) { "Duplicates dropped: {0} -> {1}" -f $dupes.Count, ($dupes -join ', ') }
if ($unmatched.Count) { "Unmatched (no dex/sprite): {0} -> {1}" -f $unmatched.Count, ($unmatched -join ', ') }
else { "All species matched a national dex number." }
