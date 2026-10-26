$ErrorActionPreference = 'Stop'
$root = (Get-Location).Path
$specs = @(
  @{ Rel = 'Workspaces/AudioWorkspace/audio_edit_session.gd'; Candidate = 'tools/delivery_correctness_20261014/audio_edit_session.gd.candidate'; OriginalHash = '00839e99a7c24db48470f78706a079bea11d7e6a14c16a375ab7831966811109'; CandidateHash = 'b8d9efc194826afb26b59127bed358348fbe4dc414ce077ebd11f6b771af96fd' },
  @{ Rel = 'Workspaces/AudioWorkspace/audio_workspace.gd'; Candidate = 'tools/delivery_correctness_20261014/audio_workspace.gd.candidate'; OriginalHash = '77188c840ee5efc7660d48960954570a00a27f9d4b3aeb8bbca8a4fc381adb19'; CandidateHash = '6a016054998c9bb2b220b66a69dfccc708843177848f3b5cfe3ef5a5acf3461a' }
)
$dep = Join-Path $root 'Workspaces/AudioWorkspace/audio_document.gd'
$depExpected = '35cd8906dd0fc4e3679a5071892161d3de1024d140173a467011574283b9ae99'
function Hash-File([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
if ((Hash-File $dep) -ne $depExpected) { throw 'Audio-document dependency hash mismatch; stopped before writes.' }
foreach ($s in $specs) {
  $source = Join-Path $root $s.Rel
  $candidate = Join-Path $root $s.Candidate
  if ((Hash-File $source) -ne $s.OriginalHash) { throw "Original source hash mismatch: $($s.Rel)" }
  if ((Hash-File $candidate) -ne $s.CandidateHash) { throw "Candidate hash mismatch: $($s.Candidate)" }
}
$backupBase = Join-Path $root 'tools/delivery_correctness_20261014/backups'
[IO.Directory]::CreateDirectory($backupBase) | Out-Null
$backupDir = Join-Path $backupBase ((Get-Date -Format 'yyyyMMddTHHmmssfff') + '_batch3_' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($backupDir) | Out-Null
foreach ($s in $specs) {
  $source = Join-Path $root $s.Rel
  $backup = Join-Path $backupDir ((Split-Path $source -Leaf) + '.original')
  [IO.File]::Copy($source, $backup, $false)
  if ((Hash-File $backup) -ne $s.OriginalHash) { throw "Backup readback hash mismatch: $backup" }
}
foreach ($s in $specs) {
  $source = Join-Path $root $s.Rel
  $candidate = Join-Path $root $s.Candidate
  if ((Hash-File $source) -ne $s.OriginalHash) { throw "Source changed after backup: $($s.Rel)" }
  if ((Hash-File $candidate) -ne $s.CandidateHash) { throw "Candidate changed after preflight: $($s.Candidate)" }
  $temp = $source + '.codex-promote-' + [guid]::NewGuid().ToString('N') + '.tmp'
  [IO.File]::Copy($candidate, $temp, $false)
  if ((Hash-File $temp) -ne $s.CandidateHash) { throw "Promotion staging hash mismatch: $temp" }
  $replaceBackup = Join-Path $backupDir ('replace-' + [guid]::NewGuid().ToString('N') + '.original')
  [IO.File]::Replace($temp, $source, $replaceBackup)
  if ((Hash-File $replaceBackup) -ne $s.OriginalHash) { throw "Atomic replacement backup hash mismatch: $replaceBackup" }
  if ((Hash-File $source) -ne $s.CandidateHash) { throw "Promoted source hash mismatch: $($s.Rel)" }
}
if ((Hash-File $dep) -ne $depExpected) { throw 'Audio-document dependency changed during promotion.' }
@(
  [pscustomobject]@{ File = $specs[0].Rel; Hash = (Hash-File (Join-Path $root $specs[0].Rel)); Backup = (Join-Path $backupDir 'audio_edit_session.gd.original') }
  [pscustomobject]@{ File = $specs[1].Rel; Hash = (Hash-File (Join-Path $root $specs[1].Rel)); Backup = (Join-Path $backupDir 'audio_workspace.gd.original') }
  [pscustomobject]@{ File = 'Workspaces/AudioWorkspace/audio_document.gd'; Hash = (Hash-File $dep); Backup = $null }
) | ConvertTo-Json -Compress
