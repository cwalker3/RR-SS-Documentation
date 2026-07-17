param([string]$GameDir)   # folder holding this game's .txt change docs (and where data.json is written)
$ErrorActionPreference = 'Stop'
$src = if ($GameDir) { $GameDir } else { $PSScriptRoot }   # the .txt source documents live here
$out = $src

function Read-Lines($name){
  return [System.IO.File]::ReadAllLines((Join-Path $src $name), [System.Text.Encoding]::UTF8)
}
function Get-Cells($line){
  if ($line -notmatch '\|'){ return @() }
  $t = $line.Trim()
  $t = $t.Trim('|')
  return @($t -split '\|' | ForEach-Object { $_.Trim() })
}
function Is-Border($l){ return ($l -match '^\s*o[-o]*o\s*$') }
function Is-NarrowBox($l){ return ($l -match '^o-{3,34}o$') }
function Is-Rule($l){ return ($l -match '^=+\s*$') }
function Format-Name($n){
  $t = (Get-Culture).TextInfo.ToTitleCase($n.ToLower())
  $t = $t -creplace "'D\b","'d"
  $t = $t -creplace "'S\b","'s"
  return $t.Trim()
}

# ---------- Generic intro / doc meta ----------
function Get-DocMeta($lines){
  $meta = @{ subtitle=''; heading=''; blurb=@(); files=@(); bodyStart=0 }
  # subtitle line: 4th line (index 3) with two cells: docType | subtitle
  for($i=0;$i -lt [Math]::Min(8,$lines.Count);$i++){
    if($lines[$i] -match 'POKÉMON RISING RUBY'){
      $c = @(Get-Cells $lines[$i+2])
      if($c.Count -ge 2){ $meta.heading=$c[0]; $meta.subtitle=$c[1] }
      break
    }
  }
  # find "Files mentioned"
  $filesIdx = -1
  for($i=0;$i -lt $lines.Count;$i++){ if($lines[$i] -match 'Files mentioned in this document'){ $filesIdx=$i; break } }
  if($filesIdx -ge 0){
    # blurb: single-cell content lines between subtitle box and files title
    $blurb = New-Object System.Collections.ArrayList
    $cur = ''
    # start scanning after the subtitle box: find the 3rd border
    $borders=0; $start=0
    for($i=0;$i -lt $filesIdx;$i++){ if(Is-Border $lines[$i]){ $borders++; if($borders -eq 5){ $start=$i+1; break } } }
    for($i=$start;$i -lt $filesIdx-0;$i++){
      if(Is-Border $lines[$i]){ if($i -ge $filesIdx-1){break}; continue }
      $c = Get-Cells $lines[$i]
      $txt = ($c -join ' ').Trim()
      if($txt -eq ''){ if($cur){ [void]$blurb.Add($cur); $cur='' } }
      else { $cur = ($cur + ' ' + $txt).Trim() }
    }
    if($cur){ [void]$blurb.Add($cur) }
    $meta.blurb = @($blurb)
    # files table rows after filesIdx
    $files = New-Object System.Collections.ArrayList
    $j = $filesIdx+1
    while($j -lt $lines.Count -and (Is-Border $lines[$j])){ $j++ }  # skip border after title
    while($j -lt $lines.Count -and -not (Is-Border $lines[$j])){
      $c = @(Get-Cells $lines[$j])
      if($c.Count -ge 2){ [void]$files.Add(@{ code=$c[0]; desc=$c[1] }) }
      $j++
    }
    $meta.files = @($files)
    $meta.bodyStart = $j+1
  }
  return $meta
}

function Get-Paragraphs($cellTexts){
  $paras = New-Object System.Collections.ArrayList
  $cur=''
  foreach($t in $cellTexts){
    if($t -eq ''){ if($cur){ [void]$paras.Add($cur); $cur='' } }
    else { $cur = ($cur + ' ' + $t).Trim() }
  }
  if($cur){ [void]$paras.Add($cur) }
  return @($paras)
}

# ---------- Generic boxed-block parser (Evolution / Items / Gifts) ----------
# In these docs a table's header row sits in its OWN border-delimited box, and the
# data rows (sometimes split further, e.g. one box per shop) follow. So we first
# classify every box, then merge consecutive table fragments into a single table,
# using the first fragment's line as the shared header.
function Parse-Blocks($lines, $start){
  # --- pass 1: collect boxes (content lines between full-width borders) ---
  $boxes = New-Object System.Collections.ArrayList
  $group = New-Object System.Collections.ArrayList
  for($i=$start;$i -lt $lines.Count;$i++){
    $l = $lines[$i]
    if(Is-Border $l){ if($group.Count){ [void]$boxes.Add(@($group)); $group=New-Object System.Collections.ArrayList }; continue }
    if($l.Trim() -eq '' -and $group.Count -eq 0){ continue }
    [void]$group.Add($l)
  }
  if($group.Count){ [void]$boxes.Add(@($group)) }

  # --- pass 1b: classify each box ---
  $items = New-Object System.Collections.ArrayList
  foreach($box in $boxes){
    $cl = @($box)
    $cellLines = @($cl | ForEach-Object { ,@(Get-Cells $_) })
    $multi = @($cellLines | Where-Object { $_.Count -ge 2 }).Count
    if($cl.Count -eq 1 -and $cellLines[0].Count -le 1){
      $txt = (($cellLines[0]) -join ' ').Trim()
      if($txt.StartsWith('*')){ [void]$items.Add(@{ kind='prose'; paragraphs=@($txt) }) }
      else { [void]$items.Add(@{ kind='heading'; text=$txt }) }
    } elseif($multi -ge 1){
      [void]$items.Add(@{ kind='tablefrag'; lines=$cellLines })
    } else {
      $texts = @($cl | ForEach-Object { ((Get-Cells $_) -join ' ').Trim() })
      $joined = ($texts -join ' ').Trim()
      if($cl.Count -gt 1 -and $joined -notmatch '[.!?]' -and $joined -match ','){
        [void]$items.Add(@{ kind='chips'; items=@($joined -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) })
      } else {
        [void]$items.Add(@{ kind='prose'; paragraphs=(Get-Paragraphs $texts) })
      }
    }
  }

  # --- pass 2: emit blocks, merging consecutive table fragments ---
  $blocks = New-Object System.Collections.ArrayList
  $pCols = $null; $pRows = $null
  foreach($it in $items){
    if($it.kind -eq 'tablefrag'){
      $flines = $it.lines
      $startIdx = 0
      if($null -eq $pCols){ $pCols = @($flines[0]); $pRows = New-Object System.Collections.ArrayList; $startIdx = 1 }
      for($k=$startIdx;$k -lt $flines.Count;$k++){
        $c = @($flines[$k])
        if($c.Count -eq 0){ continue }
        if($c[0] -eq '' -and $pRows.Count -gt 0){
          $prev = $pRows[$pRows.Count-1]
          for($m=1;$m -lt $c.Count -and $m -lt $prev.Count;$m++){ if($c[$m]){ $prev[$m] = ($prev[$m]+' '+$c[$m]).Trim() } }
        } else { [void]$pRows.Add([System.Collections.ArrayList]@($c)) }
      }
    } else {
      if($null -ne $pCols){
        [void]$blocks.Add(@{ type='table'; columns=@($pCols); rows=@($pRows | ForEach-Object { ,@($_) }) })
        $pCols=$null; $pRows=$null
      }
      if($it.kind -eq 'heading'){ [void]$blocks.Add(@{ type='heading'; text=$it.text }) }
      elseif($it.kind -eq 'chips'){ [void]$blocks.Add(@{ type='chips'; items=@($it.items) }) }
      else { [void]$blocks.Add(@{ type='prose'; paragraphs=@($it.paragraphs) }) }
    }
  }
  if($null -ne $pCols){ [void]$blocks.Add(@{ type='table'; columns=@($pCols); rows=@($pRows | ForEach-Object { ,@($_) }) }) }
  return @($blocks)
}

# ================= POKEMON =================
function Parse-Pokemon(){
  $lines = Read-Lines 'PokemonChanges.txt'
  $meta = Get-DocMeta $lines
  $entries = New-Object System.Collections.ArrayList
  # find header indices
  $hdr = New-Object System.Collections.ArrayList
  for($i=0;$i -lt $lines.Count;$i++){ if($lines[$i] -match '^#(\d+)\s+(.+?)\s*$'){ [void]$hdr.Add($i) } }
  for($h=0;$h -lt $hdr.Count;$h++){
    $start = $hdr[$h]
    $end = if($h+1 -lt $hdr.Count){ $hdr[$h+1]-1 } else { $lines.Count-1 }
    $null = ($lines[$start] -match '^#(\d+)\s+(.+?)\s*$')
    $dex = $matches[1]; $rawName = $matches[2]
    $attrs = New-Object System.Collections.ArrayList
    $changes = New-Object System.Collections.ArrayList
    $moves = New-Object System.Collections.ArrayList
    $notes = New-Object System.Collections.ArrayList
    $forme = ''
    for($i=$start+1;$i -le $end;$i++){
      $l = $lines[$i]
      if($l.Trim() -eq ''){ continue }
      if(Is-Rule $l){ continue }
      if(($i+1 -le $end) -and (Is-Rule $lines[$i+1])){ $forme = $l.Trim(); continue }
      if($l -match '^(\d+)\s+(.+?)\s*$'){
        $lvl=[int]$matches[1]; $mv=$matches[2].Trim(); $rar=0
        if($mv -match '^(.*?)\s*(\*+)$'){ $rar=$matches[2].Length; $mv=$matches[1].Trim() }
        [void]$moves.Add(@{ level=$lvl; name=$mv; rarity=$rar }); continue
      }
      if($l -match '>>'){
        $p = $l -split '\s*>>\s*',2
        $to=$p[1].Trim(); $left=$p[0].Trim(); $label=''; $from=''
        if($left -match '^(.+?):\s*(.+)$'){ $label=$matches[1].Trim(); $from=$matches[2].Trim() }
        elseif($left -match '^(.+?)\s{1,}(\S+)$'){ $label=$matches[1].Trim(); $from=$matches[2].Trim() }
        else { $label=$left; $from='' }
        [void]$changes.Add(@{ forme=$forme; label=$label; from=$from; to=$to }); continue
      }
      if($l -match '^\s*(.+?):\s*(.+)$'){
        $lab=$matches[1].Trim(); $val=$matches[2].Trim()
        if($lab -eq 'ocation'){ $lab='Location' }
        [void]$attrs.Add(@{ label=$lab; value=$val }); continue
      }
      [void]$notes.Add($l.Trim())
    }
    [void]$entries.Add(@{
      dex=$dex; name=(Format-Name $rawName);
      attrs=@($attrs); changes=@($changes); moves=@($moves); notes=@($notes)
    })
  }
  return @{ meta=$meta; entries=@($entries) }
}

# ================= AREAS =================
function Parse-Species($val){
  $out = New-Object System.Collections.ArrayList
  foreach($s in ($val -split ',')){
    $n = $s.Trim(); if($n -eq ''){ continue }
    $rare=$false
    if($n -match '^(.*?)\*\s*$'){ $n=$matches[1].Trim(); $rare=$true }
    [void]$out.Add(@{ name=$n; rare=$rare })
  }
  return @($out)
}
function Parse-Team($val){
  $out = New-Object System.Collections.ArrayList
  foreach($s in ($val -split ',')){
    $t=$s.Trim(); if($t -eq ''){ continue }
    if($t -match '^(.*\S)\s+(\d+)\s*$'){ [void]$out.Add(@{ species=$matches[1].Trim(); level=[int]$matches[2] }) }
    else { [void]$out.Add(@{ species=$t; level=$null }) }
  }
  return @($out)
}
function Parse-Areas(){
  $lines = Read-Lines 'AreaChanges.txt'
  $meta = Get-DocMeta $lines
  $areas = New-Object System.Collections.ArrayList
  $cur = $null; $mode=''; $roster=$null; $special=$null
  for($i=$meta.bodyStart;$i -lt $lines.Count;$i++){
    $l = $lines[$i]
    if($l.Trim() -eq ''){ continue }
    if(Is-Border $l){ continue }
    if($l -notmatch '\|'){ continue }
    $c = @(Get-Cells $l)
    if($c.Count -eq 0){ continue }
    # route name?
    if($i-1 -ge 0 -and (Is-NarrowBox $lines[$i-1]) -and $c.Count -eq 1){
      $cur = @{ name=$c[0]; wild=(New-Object System.Collections.ArrayList); rosters=(New-Object System.Collections.ArrayList); special=(New-Object System.Collections.ArrayList) }
      [void]$areas.Add($cur); $mode=''; $roster=$null; $special=$null; continue
    }
    if($null -eq $cur){ continue }
    if($c.Count -eq 1){
      $title=$c[0]
      if($title -match '^Special Battle'){
        $t = $title -replace '^Special Battle\s*-\s*',''
        $special = @{ title=$t; team=(New-Object System.Collections.ArrayList) }
        [void]$cur.special.Add($special); $mode='special'
      } elseif($title -match '^(Trainers|Rematches)'){
        $kind = if($title -match 'Rematch'){'rematch'}else{'roster'}
        $roster = @{ title=$title; kind=$kind; trainers=(New-Object System.Collections.ArrayList) }
        [void]$cur.rosters.Add($roster); $mode='trainer'
      }
      continue
    }
    # header rows
    if($c[0] -eq 'Method' -and $c -contains 'Species'){ $mode='wild'; continue }
    if($c[0] -eq 'ID' -and $c -contains 'Trainer'){
      if($null -eq $roster){ $roster=@{ title='Trainers'; kind='roster'; trainers=(New-Object System.Collections.ArrayList) }; [void]$cur.rosters.Add($roster) }
      $mode='trainer'; continue
    }
    if($c[0] -eq 'Pokemon' -and $c -contains 'Ability'){ $mode='special'; continue }
    # data rows
    switch($mode){
      'wild' {
        if($c.Count -ge 3){ [void]$cur.wild.Add(@{ method=$c[0]; level=$c[1]; species=(Parse-Species $c[2]) }) }
      }
      'trainer' {
        if($c.Count -ge 3 -and $null -ne $roster){
          $tn=$c[1]; $badge=''
          if($tn -match '^(.*?)\s*\(([\w]+)\)\s*$'){ $tn=$matches[1].Trim(); $badge=$matches[2] }
          [void]$roster.trainers.Add(@{ id=$c[0]; name=$tn; badge=$badge; team=(Parse-Team $c[2]) })
        }
      }
      'special' {
        if($c.Count -ge 5 -and $null -ne $special){
          $mv = @($c[4] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
          [void]$special.team.Add(@{ name=$c[0]; level=$c[1]; item=$c[2]; ability=$c[3]; moves=$mv })
        }
      }
    }
  }
  # convert ArrayLists to arrays
  $areasOut = @($areas | ForEach-Object {
    @{ name=$_.name; wild=@($_.wild); rosters=@($_.rosters | ForEach-Object { @{ title=$_.title; kind=$_.kind; trainers=@($_.trainers) } }); special=@($_.special | ForEach-Object { @{ title=$_.title; team=@($_.team) } }) }
  })
  return @{ meta=$meta; areas=$areasOut }
}

# ================= ATTACKS =================
function Parse-Attacks(){
  $lines = Read-Lines 'AttackChanges.txt'
  $meta = Get-DocMeta $lines
  $entries = New-Object System.Collections.ArrayList
  $cur=$null
  for($i=$meta.bodyStart;$i -lt $lines.Count;$i++){
    $l=$lines[$i]
    if($l.Trim() -eq ''){ continue }
    if(Is-Rule $l){ continue }
    if(($i+1 -lt $lines.Count) -and (Is-Rule $lines[$i+1])){
      $cur=@{ name=$l.Trim(); rows=(New-Object System.Collections.ArrayList) }
      [void]$entries.Add($cur); continue
    }
    if($null -eq $cur){ continue }
    if($l -match '>>'){
      $p=$l -split '\s*>>\s*',2; $to=$p[1].Trim(); $left=$p[0].Trim()
      if($left -match '^(.+?)\s{2,}(.+)$'){ [void]$cur.rows.Add(@{ kind='change'; label=$matches[1].Trim(); from=$matches[2].Trim(); to=$to }) }
      else { [void]$cur.rows.Add(@{ kind='change'; label=$left; from=''; to=$to }) }
    } elseif($l -match '^(.+?)\s{2,}(.+)$'){
      [void]$cur.rows.Add(@{ kind='note'; label=$matches[1].Trim(); value=$matches[2].Trim() })
    } else {
      [void]$cur.rows.Add(@{ kind='note'; label=''; value=$l.Trim() })
    }
  }
  $entriesOut = @($entries | ForEach-Object { @{ name=$_.name; rows=@($_.rows) } })
  return @{ meta=$meta; entries=$entriesOut }
}

# ================= THIEF =================
# Linear, structure-aware parse of the (prose-heavy) thief doc.
function Parse-Thief(){
  $lines = Read-Lines 'RRSS_Thiefable_Items.txt'
  $introParts = New-Object System.Collections.ArrayList
  $earlyLearn = New-Object System.Collections.ArrayList
  $earlyNote = ''
  $stages = New-Object System.Collections.ArrayList
  $generalNotes = New-Object System.Collections.ArrayList
  $contest = $null
  $mega = $null
  $megaBuf = New-Object System.Collections.ArrayList
  $cur = $null
  $mode = 'intro'   # intro | early | preStage | contestHead | contest | stage | mega

  for($i=0;$i -lt $lines.Count;$i++){
    $ln = $lines[$i].Trim()
    if($ln -eq ''){ continue }
    if($ln -match '^-{5,}$'){ continue }
    if($ln -eq 'THIEFABLE ITEMS DOC'){ continue }

    if($mode -eq 'mega'){ [void]$megaBuf.Add($ln); continue }
    if($mode -eq 'contestHead'){
      $contest.subtitle = ($contest.subtitle + ' ' + $ln).Trim()
      if($ln.EndsWith(':')){ $contest.subtitle = $contest.subtitle.TrimEnd(':').Trim(); $mode='contest' }
      continue
    }

    # section starts (checked in every mode)
    if($ln -match '^The following Mega Stones'){
      $mega = @{ subtitle = $ln.TrimEnd(':').Trim() }; $mode='mega'; continue
    }
    if($ln -match '^Farmable items from Contests'){
      $contest = @{ title='Contest Prizes'; subtitle=$ln; rows=(New-Object System.Collections.ArrayList); notes=(New-Object System.Collections.ArrayList) }
      if($ln.EndsWith(':')){ $contest.subtitle=$contest.subtitle.TrimEnd(':').Trim(); $mode='contest' } else { $mode='contestHead' }
      continue
    }
    if($ln -match '^Before\s+(.+?):(.*)$'){
      $cur = @{ title=('Before '+$matches[1].Trim()); rows=(New-Object System.Collections.ArrayList); notes=(New-Object System.Collections.ArrayList) }
      [void]$stages.Add($cur)
      $trail=$matches[2].Trim(); if($trail -ne ''){ [void]$cur.notes.Add($trail) }
      $mode='stage'; continue
    }

    switch($mode){
      'intro' {
        if($ln -match '^(.+?)\s-\s(.+)$'){ $mode='early'; [void]$earlyLearn.Add(@{ name=$matches[1].Trim(); detail=$matches[2].Trim() }) }
        else { [void]$introParts.Add($ln) }
      }
      'early' {
        if($ln -match '^(.+?)\s-\s(.+)$'){ [void]$earlyLearn.Add(@{ name=$matches[1].Trim(); detail=$matches[2].Trim() }) }
        else { if($earlyNote -eq ''){ $earlyNote=$ln } else { [void]$generalNotes.Add($ln) }; $mode='preStage' }
      }
      'preStage' { [void]$generalNotes.Add($ln) }
      'contest' {
        if($ln -match '^(.+?)\s-\s(.+)$'){ [void]$contest.rows.Add(@{ name=$matches[1].Trim(); item=$matches[2].Trim() }) }
        else { [void]$contest.notes.Add($ln) }
      }
      'stage' {
        if($ln.StartsWith('-')){ [void]$generalNotes.Add($ln.TrimStart('-').Trim()) }
        elseif($ln.StartsWith('*')){ [void]$cur.notes.Add($ln.Trim('*').Trim()) }
        elseif($ln -match '^(.+?)\s-\s(.+)$'){ [void]$cur.rows.Add(@{ name=$matches[1].Trim(); item=$matches[2].Trim() }) }
        else { [void]$cur.notes.Add($ln) }
      }
    }
  }

  # assemble mega entries (each starts with '*', continuation lines follow)
  $megaOut = $null
  if($mega -ne $null){
    $rows = New-Object System.Collections.ArrayList; $curE=''
    foreach($l in $megaBuf){
      if($l.StartsWith('*')){ if($curE){ [void]$rows.Add($curE) }; $curE=$l.TrimStart('*').Trim() }
      else { $curE=($curE+' '+$l).Trim() }
    }
    if($curE){ [void]$rows.Add($curE) }
    $mr = New-Object System.Collections.ArrayList
    foreach($e in $rows){
      if($e -match '^(.+?)\s-\s(.+)$'){ [void]$mr.Add(@{ name=$matches[1].Trim(); detail=$matches[2].Trim() }) }
      else { [void]$mr.Add(@{ name=''; detail=$e }) }
    }
    $megaOut = @{ subtitle=$mega.subtitle; rows=@($mr) }
  }

  $contestOut = if($contest){ @{ title=$contest.title; subtitle=$contest.subtitle; rows=@($contest.rows); notes=@($contest.notes) } } else { $null }
  return @{
    intro = ($introParts -join ' ').TrimEnd(':').Trim()
    earlyLearn = @($earlyLearn)
    earlyNote = $earlyNote
    stages = @($stages | ForEach-Object { @{ title=$_.title; rows=@($_.rows); notes=@($_.notes) } })
    contest = $contestOut
    mega = $megaOut
    generalNotes = @($generalNotes)
  }
}

# ================= EVOLUTION / ITEMS / GIFTS =================
function Parse-BoxDoc($name){
  $lines = Read-Lines $name
  $meta = Get-DocMeta $lines
  $blocks = Parse-Blocks $lines $meta.bodyStart
  return @{ meta=$meta; blocks=@($blocks) }
}

# ---------- assemble ----------
Write-Host 'Parsing Pokemon...'
$pokemon = Parse-Pokemon
Write-Host ("  entries: {0}" -f $pokemon.entries.Count)
Write-Host 'Parsing Areas...'
$areas = Parse-Areas
Write-Host ("  areas: {0}" -f $areas.areas.Count)
Write-Host 'Parsing Attacks...'
$attacks = Parse-Attacks
Write-Host ("  moves: {0}" -f $attacks.entries.Count)
Write-Host 'Parsing Evolution...'
$evolution = Parse-BoxDoc 'EvolutionChanges.txt'
Write-Host 'Parsing Items...'
$items = Parse-BoxDoc 'ItemChanges.txt'
Write-Host 'Parsing Gifts...'
$gifts = Parse-BoxDoc 'GiftsStaticEncountersChanges.txt'
Write-Host 'Parsing Thief...'
$thief = Parse-Thief
Write-Host ("  thief sections: {0}" -f $thief.sections.Count)

$data = @{
  generated = (Get-Date -Format 'yyyy-MM-dd')
  pokemon = $pokemon
  areas = $areas
  attacks = $attacks
  evolution = $evolution
  items = $items
  gifts = $gifts
  thief = $thief
}

$json = $data | ConvertTo-Json -Depth 40 -Compress
[System.IO.File]::WriteAllText((Join-Path $out 'data.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("Wrote data.json ({0:N0} bytes)" -f $json.Length)
