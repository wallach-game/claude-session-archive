<#
 archive.ps1 - archive / wipe / restore Claude Code sessions.
   list    [-Days N]                    sessions older than N days (JSON). N=0 -> all. Marks live/current.
   config  [-Dest path]                 show or set archive folder (config.json next to this script)
   pack    -Ids a,b [-NoMemory]         zip sessions to the archive folder, verify, print JSON result
   wipe    -Ids a,b                     delete session data from ~/.claude (only ids with an archive zip, unless -Force)
   wipe-later -Ids a                    detached: wait for the owning claude process to exit, then wipe
   delete  -Ids a,b                     delete WITHOUT archiving (explicit user choice)
   restore -Zip file.zip                put files back to original locations
#>
param([Parameter(Position=0)][string]$Cmd='list',[int]$Days=0,[string[]]$Ids=@(),[string]$Dest,[string]$Zip,[switch]$NoMemory,[switch]$Force)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem, System.IO.Compression
$C="$HOME\.claude"; $Cfg="$PSScriptRoot\config.json"
if($Ids.Count -eq 1 -and $Ids[0].Contains(',')){ $Ids=$Ids[0].Split(',') }
function Out-Json($o){ $o | ConvertTo-Json -Depth 6 -Compress }
function Get-Dest{ if(Test-Path $Cfg){ (Get-Content $Cfg -Raw|ConvertFrom-Json).dest } }
function Slug($s){ $n=$s.Normalize([Text.NormalizationForm]::FormD); $n=-join($n.ToCharArray()|?{[Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark'}); $n=($n -replace '[^A-Za-z0-9]+','-').Trim('-'); if($n.Length -gt 50){$n=$n.Substring(0,50).Trim('-')}; if(!$n){'untitled'}else{$n} }
function Find-Session($id){ Get-ChildItem "$C\projects\*\*.jsonl" | ?{ $_.BaseName.StartsWith($id) } | select -First 1 }
function Get-Title($path){
  $t=$null;$ai=$null
  foreach($l in [IO.File]::ReadLines($path)){
    if($l.Contains('"custom-title"')){ try{$t=($l|ConvertFrom-Json).customTitle}catch{} }
    elseif($l.Contains('"ai-title"')){ try{$ai=($l|ConvertFrom-Json).aiTitle}catch{} } }
  if($t){$t}elseif($ai){$ai}else{'(untitled)'} }
function Live-Ids{
  $r=@(); if($env:CLAUDE_CODE_SESSION_ID){$r+=$env:CLAUDE_CODE_SESSION_ID}
  Get-ChildItem "$C\sessions\*.json" -ErrorAction SilentlyContinue | %{ try{$j=Get-Content $_.FullName -Raw|ConvertFrom-Json; if(Get-Process -Id $j.pid -ErrorAction SilentlyContinue){$r+=$j.sessionId}}catch{} }
  $r|select -Unique }
# every path that belongs to a session (transcript first)
function Session-Paths($f){
  $id=$f.BaseName; $p=@($f.FullName)
  foreach($x in "$($f.DirectoryName)\$id","$C\file-history\$id","$C\session-env\$id","$C\debug\$id.txt"){ if(Test-Path $x){$p+=$x} }
  $p }
function Render-Md($path,$title){
  $sb=New-Object Text.StringBuilder; [void]$sb.AppendLine("# $title`n")
  foreach($l in [IO.File]::ReadLines($path)){
    if(!($l.Contains('"type":"user"') -or $l.Contains('"type":"assistant"'))){continue}
    try{$d=$l|ConvertFrom-Json}catch{continue}
    if($d.type -notin 'user','assistant' -or $d.isSidechain){continue}
    $c=$d.message.content; $txt=''
    if($c -is [string]){$txt=$c}else{ foreach($b in $c){ if($b.type -eq 'text'){$txt+=$b.text+"`n"} elseif($b.type -eq 'tool_use'){$txt+="_[tool: $($b.name)]_`n"} } }
    if($txt.Trim()){ [void]$sb.AppendLine("## $($d.type) $($d.timestamp)`n`n$($txt.Trim())`n") } }
  $sb.ToString() }
function Archive-Name($f,$title){ "{0:yyyy-MM-dd}_{1}_{2}.zip" -f $f.LastWriteTime,(Slug $title),$f.BaseName.Substring(0,8) }
function Zip-Path($id){ $d=Get-Dest; if(!$d){return $null}; Get-ChildItem $d -Filter "*_$($id.Substring(0,8)).zip" -ErrorAction SilentlyContinue | select -First 1 }

switch($Cmd){
'config' {
  if($Dest){ New-Item -ItemType Directory -Force $Dest|Out-Null; @{dest=(Resolve-Path $Dest).Path}|ConvertTo-Json|Set-Content $Cfg -Encoding utf8 }
  Out-Json @{dest=(Get-Dest)} }
'list' {
  $live=Live-Ids; $cut=(Get-Date).AddDays(-$Days)
  $r=Get-ChildItem "$C\projects\*\*.jsonl" | ?{ $Days -eq 0 -or $_.LastWriteTime -lt $cut } | sort LastWriteTime | %{
    $sz=$_.Length
    foreach($x in (Session-Paths $_|select -Skip 1)){ if(Test-Path $x -PathType Container){$sz+=(Get-ChildItem $x -Recurse -File -ErrorAction SilentlyContinue|measure Length -Sum).Sum}else{$sz+=(Get-Item $x).Length} }
    [pscustomobject]@{id=$_.BaseName;short=$_.BaseName.Substring(0,8);title=(Get-Title $_.FullName);project=$_.Directory.Name;modified=$_.LastWriteTime.ToString('yyyy-MM-dd');ageDays=[int]((Get-Date)-$_.LastWriteTime).TotalDays;sizeMB=[math]::Round($sz/1MB,1);live=($live -contains $_.BaseName);archived=[bool](Zip-Path $_.BaseName)} }
  Out-Json @($r) }
'pack' {
  $dest=Get-Dest; if(!$dest){throw 'archive folder not configured: run config -Dest <path>'}
  $res=@()
  foreach($id in $Ids){
    $f=Find-Session $id; if(!$f){$res+=@{id=$id;ok=$false;error='not found'};continue}
    $title=Get-Title $f.FullName; $out=Join-Path $dest (Archive-Name $f $title); $tmp="$out.part"
    if(Test-Path $tmp){Remove-Item $tmp -Force}
    $files=@(); $z=[IO.Compression.ZipFile]::Open($tmp,'Create')
    try{
      $paths=@(Session-Paths $f)
      if(!$NoMemory){ $m="$($f.DirectoryName)\memory"; if(Test-Path $m){$paths+=$m} }
      foreach($p in $paths){
        $items= if(Test-Path $p -PathType Container){Get-ChildItem $p -Recurse -File}else{Get-Item $p}
        foreach($i in $items){
          $rel=$i.FullName.Substring($C.Length).TrimStart('\') -replace '\\','/'
          [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z,$i.FullName,"data/$rel",'Optimal')
          $files+=@{zip="data/$rel";orig=$i.FullName;size=$i.Length} } }
      $man=@{id=$f.BaseName;title=$title;project=$f.Directory.Name;modified=$f.LastWriteTime.ToString('o');archived=(Get-Date).ToString('o');files=$files}
      foreach($e in @(@('manifest.json',(Out-Json $man)),@('transcript.md',(Render-Md $f.FullName $title)))){
        $en=$z.CreateEntry($e[0]); $w=New-Object IO.StreamWriter($en.Open(),(New-Object Text.UTF8Encoding $false)); $w.Write($e[1]); $w.Dispose() }
    } finally { $z.Dispose() }
    # verify: reopen, every file entry present with identical length
    $ok=$true; $z=[IO.Compression.ZipFile]::OpenRead($tmp)
    try{ foreach($fi in $files){ $en=$z.GetEntry($fi.zip); if(!$en -or $en.Length -ne $fi.size){$ok=$false} } } finally{$z.Dispose()}
    if($ok){ Move-Item $tmp $out -Force; $res+=@{id=$f.BaseName;ok=$true;zip=$out;sizeMB=[math]::Round((Get-Item $out).Length/1MB,2);files=$files.Count} }
    else{ Remove-Item $tmp -Force; $res+=@{id=$f.BaseName;ok=$false;error='verification failed, nothing deleted'} } }
  Out-Json $res }
{$_ -in 'wipe','delete'} {
  $res=@(); $live=Live-Ids
  foreach($id in $Ids){
    $f=Find-Session $id; if(!$f){$res+=@{id=$id;ok=$false;error='not found'};continue}
    if($live -contains $f.BaseName){$res+=@{id=$id;ok=$false;error='session is live - use wipe-later'};continue}
    if($Cmd -eq 'wipe' -and !$Force -and !(Zip-Path $f.BaseName)){$res+=@{id=$id;ok=$false;error='no archive zip found, refusing'};continue}
    try{ foreach($p in (Session-Paths $f)|sort -Descending){ Remove-Item $p -Recurse -Force }; $res+=@{id=$id;ok=$true} }
    catch{$res+=@{id=$id;ok=$false;error=$_.Exception.Message}} }
  Out-Json $res }
'wipe-later' {
  $f=Find-Session $Ids[0]; if(!$f){throw 'not found'}
  if(!(Zip-Path $f.BaseName)){throw 'no archive zip - pack first'}
  $owner=0; Get-ChildItem "$C\sessions\*.json" -ErrorAction SilentlyContinue|%{ try{$j=Get-Content $_.FullName -Raw|ConvertFrom-Json; if($j.sessionId -eq $f.BaseName){$owner=[int]$j.pid}}catch{} }
  # NOTE: wipe refuses live sessions, so the detached job waits for the owner pid to exit first.
  $cmd="`$p=$owner; if(`$p){ while(Get-Process -Id `$p -ErrorAction SilentlyContinue){Start-Sleep 3} } else {Start-Sleep 60}; Start-Sleep 3; `$env:CLAUDE_CODE_SESSION_ID=''; & '$PSCommandPath' wipe -Ids $($f.BaseName) | Out-File '$PSScriptRoot\wipe-later.log' -Append"
  Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-Command',$cmd
  Out-Json @{id=$f.BaseName;scheduled=$true;waitsForPid=$owner} }
'archives' {
  $d=Get-Dest; if(!$d){throw 'archive folder not configured'}
  $r=Get-ChildItem $d -Filter *.zip -ErrorAction SilentlyContinue | sort LastWriteTime -Descending | %{
    $z=[IO.Compression.ZipFile]::OpenRead($_.FullName)
    try{ $m=(New-Object IO.StreamReader($z.GetEntry('manifest.json').Open())).ReadToEnd()|ConvertFrom-Json
      $exists=[bool](Get-ChildItem "$C\projects\*\$($m.id).jsonl" -ErrorAction SilentlyContinue)
      [pscustomobject]@{zip=$_.FullName;file=$_.Name;id=$m.id;short=$m.id.Substring(0,8);title=$m.title;modified=([datetime]$m.modified).ToString('yyyy-MM-dd');sizeMB=[math]::Round($_.Length/1MB,1);onDisk=$exists} }
    catch{ [pscustomobject]@{zip=$_.FullName;file=$_.Name;title='(unreadable)'} } finally{$z.Dispose()} }
  Out-Json @($r) }
'restore' {
  $z=[IO.Compression.ZipFile]::OpenRead($Zip)
  try{
    $man=(New-Object IO.StreamReader($z.GetEntry('manifest.json').Open())).ReadToEnd()|ConvertFrom-Json
    foreach($fi in $man.files){
      $t=$fi.orig; New-Item -ItemType Directory -Force (Split-Path $t)|Out-Null
      if((Test-Path $t) -and $fi.zip -like '*/memory/*'){continue}  # never clobber live memory
      [IO.Compression.ZipFileExtensions]::ExtractToFile($z.GetEntry($fi.zip),$t,$true) }
  } finally{$z.Dispose()}
  Out-Json @{restored=$man.id;title=$man.title} }
}
