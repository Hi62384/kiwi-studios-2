$ErrorActionPreference = 'Stop'
$root = (Get-Location).Path
$specs = @(
  @{ Rel = 'Workspaces/AudioWorkspace/audio_renderer.gd'; Candidate = 'tools/delivery_correctness_20261014/audio_renderer.gd.candidate'; OriginalHash = '6f42c49dd2e2a9b3d4e169d363acd59ed3e83e3ba83c50c2f7da802ab0476d52'; CandidateHash = '40dbf1fc8bab6f1ddc34a04d9d3f1457b770c71621630764c0cca55a16ac4a4c' },
  @{ Rel = 'Workspaces/AudioWorkspace/audio_workspace.gd'; Candidate = 'tools/delivery_correctness_20261014/audio_workspace.gd.candidate'; OriginalHash = 'c81414778a8df4ef6c33cc647990ea51f18e7be7c464bf7d13d0a76499ec181e'; CandidateHash = '77188c840ee5efc7660d48960954570a00a27f9d4b3aeb8bbca8a4fc381adb19' }
)
$dep = Join-Path $root 'Workspaces/AudioWorkspace/audio_source_cache.gd'
$depExpected = '13be57e05a8ba5ef6fd8cfb5b8b7a3776cdf59ad22950b5baeeac5ce696a3227'
function Hash-File([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
if ((Hash-File $dep) -ne $depExpected) { throw 'Source-cache dependency hash mismatch; stopped before writes.' }
foreach ($s in $specs) {
  $source = Join-Path $root $s.Rel
  $candidate = Join-Path $root $s.Candidate
  if ((Hash-File $source) -ne $s.OriginalHash) { throw "Original source hash mismatch: $($s.Rel)" }
  if ((Hash-File $candidate) -ne $s.CandidateHash) { throw "Candidate hash mismatch: $($s.Candidate)" }
}
$backupBase = Join-Path $root 'tools/delivery_correctness_20261014/backups'
[IO.Directory]::CreateDirectory($backupBase) | Out-Null
$backupDir = Join-Path $backupBase ((Get-Date -Format 'yyyyMMddTHHmmssfff') + '_batch2_' + [guid]::NewGuid().ToString('N'))
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
if ((Hash-File $dep) -ne $depExpected) { throw 'Source-cache dependency changed during promotion.' }
@(
  [pscustomobject]@{ File = $specs[0].Rel; Hash = (Hash-File (Join-Path $root $specs[0].Rel)); Backup = (Join-Path $backupDir 'audio_renderer.gd.original') }
  [pscustomobject]@{ File = $specs[1].Rel; Hash = (Hash-File (Join-Path $root $specs[1].Rel)); Backup = (Join-Path $backupDir 'audio_workspace.gd.original') }
  [pscustomobject]@{ File = 'Workspaces/AudioWorkspace/audio_source_cache.gd'; Hash = (Hash-File $dep); Backup = $null }
) | ConvertTo-Json -Compress
