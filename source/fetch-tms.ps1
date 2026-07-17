# Regenerates oras_tms.csv (per-Pokemon ORAS TM/HM compatibility) from PokeAPI.
# The committed oras_tms.csv already contains this; run only to refresh it.
# Downloads a ~10MB file. Run:  powershell -ExecutionPolicy Bypass -File fetch-tms.ps1
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$dir = $PSScriptRoot
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/machines.csv' -UseBasicParsing -OutFile "$dir\machines.csv"
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/move_names.csv' -UseBasicParsing -OutFile "$dir\move_names.csv"
$tmp = Join-Path $env:TEMP 'pokemon_moves.csv'
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/pokemon_moves.csv' -UseBasicParsing -OutFile $tmp

# machine move_id -> TM/HM key (ORAS = version group 16)
$move2key = @{}
Get-Content "$dir\machines.csv" | Where-Object { $_ -match '^\d+,16,' } | ForEach-Object {
  $p = $_ -split ','; $n = [int]$p[0]
  $key = if ($n -le 100) { 'TM{0:D2}' -f $n } else { 'HM{0:D2}' -f ($n - 100) }
  $move2key[[int]$p[3]] = $key
}
# per-Pokemon machine-learnable moves (version group 16, method 4 = machine)
$pt = @{}
foreach ($line in [System.IO.File]::ReadLines($tmp)) {
  $p = $line -split ','
  if ($p[1] -eq '16' -and $p[3] -eq '4') {
    $id = [int]$p[0]; if ($id -lt 1 -or $id -gt 721) { continue }
    $k = $move2key[[int]$p[2]]
    if ($k) { if (-not $pt.ContainsKey($id)) { $pt[$id] = New-Object System.Collections.Generic.HashSet[string] }; [void]$pt[$id].Add($k) }
  }
}
$out = New-Object System.Text.StringBuilder
for ($i = 1; $i -le 721; $i++) { if ($pt.ContainsKey($i)) { [void]$out.AppendLine("$i," + (($pt[$i] | Sort-Object) -join ' ')) } }
[System.IO.File]::WriteAllText("$dir\oras_tms.csv", $out.ToString(), (New-Object System.Text.UTF8Encoding($false)))
"Wrote oras_tms.csv ($($pt.Count) Pokemon)"
Remove-Item $tmp -ErrorAction SilentlyContinue
