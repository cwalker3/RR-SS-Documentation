$ErrorActionPreference='Stop'
$dir = $PSScriptRoot

# --- 1. PokeAPI current base stats: id -> [hp,atk,def,spa,spd,spe] ---
$api=@{}
Get-Content "$dir\pokemon_stats.csv" | Select-Object -Skip 1 | ForEach-Object {
  $p=$_ -split ','; if($p.Count -lt 3){return}
  $id=[int]$p[0]; if($id -lt 1 -or $id -gt 721){return}
  if(-not $api.ContainsKey($id)){ $api[$id]=@(0,0,0,0,0,0) }
  $api[$id][[int]$p[1]-1]=[int]$p[2]
}

# --- 2. Gen-6 corrections from Showdown mods (gen6 wins over gen7) ---
$rx=[regex]'(\w+):\s*\{[^{}]*?baseStats:\s*\{\s*hp:\s*(\d+),\s*atk:\s*(\d+),\s*def:\s*(\d+),\s*spa:\s*(\d+),\s*spd:\s*(\d+),\s*spe:\s*(\d+)\s*\}'
$corr=@{}
foreach($g in 'gen7','gen6'){  # gen6 applied last so it overrides
  $t=[System.IO.File]::ReadAllText("$dir\$g-pokedex.ts",[Text.Encoding]::UTF8)
  foreach($m in $rx.Matches($t)){
    $corr[$m.Groups[1].Value]=@([int]$m.Groups[2].Value,[int]$m.Groups[3].Value,[int]$m.Groups[4].Value,[int]$m.Groups[5].Value,[int]$m.Groups[6].Value,[int]$m.Groups[7].Value)
  }
}
"gen6 corrections: $($corr.Count)"

function Norm($s){ ($s.ToLower() -replace '[^a-z0-9]','') }
function StatKey($label){
  switch -regex ($label){
    '^HP$'{'hp'} '^Attack$'{'atk'} '^Defense$'{'def'}
    '^Sp\. ?Att?ack$|^Sp\. ?Atk$'{'spa'} '^Sp\. ?Defense$|^Sp\. ?Def$'{'spd'} '^Speed$'{'spe'}
    default{''}
  }
}
$order=@('hp','atk','def','spa','spd','spe')

# --- vanilla primary ability (slot 1) from PokeAPI ---
$abName=@{}
Get-Content "$dir\ability_names.csv" | Select-Object -Skip 1 | ForEach-Object {
  $p=$_ -split ','; if($p.Count -ge 3 -and $p[1] -eq '9'){ $abName[[int]$p[0]]=$p[2].Trim() }
}
$a1=@{}; $a2=@{}; $ah=@{}   # slot-1 regular, slot-2 regular, hidden
Get-Content "$dir\pokemon_abilities.csv" | Select-Object -Skip 1 | ForEach-Object {
  $p=$_ -split ','; if($p.Count -lt 4){ return }
  $pkid=[int]$p[0]; if($pkid -lt 1 -or $pkid -gt 721){ return }
  $nm=$abName[[int]$p[1]]
  if($p[2] -eq '1'){ $ah[$pkid]=$nm } elseif($p[3] -eq '1'){ $a1[$pkid]=$nm } elseif($p[3] -eq '2'){ $a2[$pkid]=$nm }
}
"vanilla abilities loaded: slot1=$($a1.Keys.Count) slot2=$($a2.Keys.Count) hidden=$($ah.Keys.Count)"

# --- TM/HM compatibility: ORAS base (from oras_tms.csv) + hack "New TM/HMs" additions ---
$mn2move=@{}
Get-Content "$dir\machines.csv" | Where-Object { $_ -match '^\d+,16,' } | ForEach-Object {
  $p=$_ -split ','; $n=[int]$p[0]; $key=if($n -le 100){'TM{0:D2}' -f $n}else{'HM{0:D2}' -f ($n-100)}; $mn2move[$key]=[int]$p[3]
}
$moveNm=@{}
Get-Content "$dir\move_names.csv" | Select-Object -Skip 1 | ForEach-Object { $p=$_ -split ','; if($p.Count -ge 3 -and $p[1] -eq '9'){ $moveNm[[int]$p[0]]=$p[2].Trim() } }
$tmMoves=[ordered]@{}; $name2key=@{}
foreach($k in ($mn2move.Keys | Sort-Object { if($_ -like 'HM*'){1000+[int]$_.Substring(2)}else{[int]$_.Substring(2)} })){
  $nm=$moveNm[$mn2move[$k]]; if($nm){ $tmMoves[$k]=$nm; $name2key[$nm.ToLower()]=$k }
}
$vanTm=@{}
Get-Content "$dir\oras_tms.csv" | ForEach-Object { $p=$_ -split ','; if($p.Count -ge 2){ $vanTm[[int]$p[0]]=$p[1] } }
function Sort-Tm($keys){ $keys | Sort-Object { if($_ -like 'HM*'){1000+[int]$_.Substring(2)}else{[int]$_.Substring(2)} } }
"TM/HM map: $($tmMoves.Count); pokemon with vanilla TMs: $($vanTm.Count)"

# --- 3. enrich each entry ---
$d=[System.IO.File]::ReadAllText("$dir\data.json",[Text.Encoding]::UTF8) | ConvertFrom-Json
$noBase=New-Object System.Collections.ArrayList
foreach($e in $d.pokemon.entries){
  $id=[int]$e.dex
  $nn=Norm $e.name
  Add-Member -InputObject $e -NotePropertyName a1 -NotePropertyValue ($(if($a1.ContainsKey($id)){$a1[$id]}else{''})) -Force
  Add-Member -InputObject $e -NotePropertyName a2 -NotePropertyValue ($(if($a2.ContainsKey($id) -and $a2[$id] -ne $a1[$id]){$a2[$id]}else{''})) -Force
  Add-Member -InputObject $e -NotePropertyName ah -NotePropertyValue ($(if($ah.ContainsKey($id)){$ah[$id]}else{''})) -Force
  # TM/HM compatibility
  $vanSet=New-Object System.Collections.Generic.HashSet[string]
  if($vanTm.ContainsKey($id)){ foreach($k in ($vanTm[$id] -split ' ')){ if($k){[void]$vanSet.Add($k)} } }
  $newSet=New-Object System.Collections.Generic.HashSet[string]
  $extra=New-Object System.Collections.ArrayList
  foreach($a in @($e.attrs)){
    if($a.label -notmatch 'TM/HM'){ continue }
    foreach($mv in ($a.value -split ',')){
      $nm=($mv -replace '\*','').Trim(); if($nm -eq ''){ continue }
      $k=$name2key[$nm.ToLower()]
      if($k){ if(-not $vanSet.Contains($k)){ [void]$newSet.Add($k) } } else { if(-not $extra.Contains($nm)){ [void]$extra.Add($nm) } }
    }
  }
  $allSet=New-Object System.Collections.Generic.HashSet[string]
  foreach($k in $vanSet){[void]$allSet.Add($k)}; foreach($k in $newSet){[void]$allSet.Add($k)}
  Add-Member -InputObject $e -NotePropertyName tms -NotePropertyValue ((Sort-Tm $allSet) -join ' ') -Force
  Add-Member -InputObject $e -NotePropertyName tmsNew -NotePropertyValue ((Sort-Tm $newSet) -join ' ') -Force
  Add-Member -InputObject $e -NotePropertyName tmsExtra -NotePropertyValue (@($extra)) -Force
  $baseArr = if($corr.ContainsKey($nn)){ $corr[$nn] } elseif($api.ContainsKey($id)){ $api[$id] } else { $null }
  if($null -eq $baseArr){ [void]$noBase.Add("$($e.dex) $($e.name)"); $baseArr=@(0,0,0,0,0,0) }
  $base=@{}; for($i=0;$i -lt 6;$i++){ $base[$order[$i]]=$baseArr[$i] }
  # apply documented changes (primary/normal forme only)
  $chg=@{}
  foreach($c in @($e.changes)){
    if($c.forme -and $c.forme -notmatch 'Normal'){ continue }
    $k=StatKey $c.label; if($k -eq ''){ continue }
    $to=0; if([int]::TryParse(($c.to -replace '[^\d]',''),[ref]$to)){ $chg[$k]=@{ from=$c.from; to=$to } }
  }
  $stats=[ordered]@{}
  $total=0
  foreach($k in $order){
    $v = if($chg.ContainsKey($k)){ $chg[$k].to } else { $base[$k] }
    $stats[$k]=$v; $total+=$v
  }
  $stats['total']=$total
  # statChg map for highlighting (from -> to)
  $statChg=[ordered]@{}
  foreach($k in $order){ if($chg.ContainsKey($k)){ $statChg[$k]=@{ from=[int]($chg[$k].from); to=[int]$chg[$k].to } } }
  Add-Member -InputObject $e -NotePropertyName stats -NotePropertyValue $stats -Force
  Add-Member -InputObject $e -NotePropertyName statChg -NotePropertyValue $statChg -Force
}
if($noBase.Count){ "NO BASE STATS ($($noBase.Count)): " + ($noBase -join ', ') } else { "all entries have base stats" }

Add-Member -InputObject $d.pokemon -NotePropertyName tmMoves -NotePropertyValue $tmMoves -Force
$json=$d | ConvertTo-Json -Depth 40 -Compress
[System.IO.File]::WriteAllText("$dir\data.json",$json,(New-Object System.Text.UTF8Encoding($false)))
"data.json rewritten: {0:N0} bytes" -f $json.Length
# sanity print
$bulba=$d.pokemon.entries | Where-Object { $_.dex -eq '001' }
"Bulbasaur stats: " + (($bulba.stats.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' ')
$arbok=$d.pokemon.entries | Where-Object { $_.name -eq 'Arbok' }
"Arbok stats: " + (($arbok.stats.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' ')
$butter=$d.pokemon.entries | Where-Object { $_.name -eq 'Butterfree' }
"Butterfree stats: " + (($butter.stats.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' ') + "  changed: " + (($butter.statChg.PSObject.Properties | ForEach-Object { $_.Name }) -join ',')