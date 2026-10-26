$ErrorActionPreference = 'Stop'
$root = (Get-Location).Path
$specs = @(
  @{ Rel = 'Workspaces/AudioWorkspace/audio_conductor.gd'; Candidate = 'tools/delivery_correctness_20261014/audio_conductor.gd.candidate'; OriginalHash = '89cecfd1ffa18cc632d182f9e3871054fa83f62dd629754c154b45bd5bead601'; CandidateHash = '1c95b65473b6b9cd8e9cb6c195ab0a07fda7694458fb266ae1932d7c9ba9fad9' },
  @{ Rel = 'Workspaces/AudioWorkspace/audio_workspace.gd'; Candidate = 'tools/delivery_correctness_20261014/audio_workspace.gd.candidate'; OriginalHash = '8a3460a540374162be3ef8febd0eb85c72b1336791e1b5ba04873ac4d3c3459e'; CandidateHash = 'c81414778a8df4ef6c33cc647990ea51f18e7be7c464bf7d13d0a76499ec181e' }
)
$tempo = Join-Path $root 'Workspaces/AudioWorkspace/audio_tempo_map.gd'
$tempoExpected = 'ec25e892a6f1e6870d101cf893bd4cc8344928f45507f43b8fcbb8b3d9afa45b'
function Hash-File([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
if ((Hash-File $tempo) -ne $tempoExpected) { throw 'Tempo-map dependency hash mismatch; stopped before writes.' }
foreach ($s in $specs) {
  $source = Join-Path $root $s.Rel
  $candidate = Join-Path $root $s.Candidate
  if ((Hash-File $source) -ne $s.OriginalHash) { throw "Original source hash mismatch: $($s.Rel)" }
  if ((Hash-File $candidate) -ne $s.CandidateHash) { throw "Candidate hash mismatch: $($s.Candidate)" }
}
$backupBase = Join-Path $root 'tools/delivery_correctness_20261014/backups'
[IO.Directory]::CreateDirectory($backupBase) | Out-Null
$backupDir = Join-Path $backupBase ((Get-Date -Format 'yyyyMMddTHHmmssfff') + '_' + [guid]::NewGuid().ToString('N'))
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
if ((Hash-File $tempo) -ne $tempoExpected) { throw 'Tempo-map dependency changed during promotion.' }
@(
  [pscustomobject]@{ File = $specs[0].Rel; Hash = (Hash-File (Join-Path $root $specs[0].Rel)); Backup = (Join-Path $backupDir 'audio_conductor.gd.original') }
  [pscustomobject]@{ File = $specs[1].Rel; Hash = (Hash-File (Join-Path $root $specs[1].Rel)); Backup = (Join-Path $backupDir 'audio_workspace.gd.original') }
  [pscustomobject]@{ File = 'Workspaces/AudioWorkspace/audio_tempo_map.gd'; Hash = (Hash-File $tempo); Backup = $null }
) | ConvertTo-Json -Compress
