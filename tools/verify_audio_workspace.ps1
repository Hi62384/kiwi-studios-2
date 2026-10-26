$ErrorActionPreference = 'Stop'
$Project = Split-Path -Parent $PSScriptRoot
$Godot = 'C:\Users\User1\Documents\Godot_v4.6.1-stable_win64\Godot_v4.6.1-stable_win64.exe'
if (-not (Test-Path -LiteralPath $Godot)) { throw "Configured project Godot path is missing: $Godot" }
$Logs = Join-Path $Project '.godot\verification\audio_workspace'
New-Item -ItemType Directory -Path $Logs -Force | Out-Null
$ExpectedFiles = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'audio_workspace_files.json') -Raw | ConvertFrom-Json
foreach ($entry in $ExpectedFiles) {
  $source = Join-Path $Project $entry.path
  if (-not (Test-Path -LiteralPath $source)) { throw "Prepared source is missing: $source" }
  $actual = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne $entry.sha256) { throw "Prepared source changed since application: $source" }
}
$summary = @()
function Stop-VerificationTree([int]$ParentId) {
  $children = Get-CimInstance Win32_Process -Filter ("ParentProcessId={0}" -f $ParentId)
  foreach ($child in $children) { Stop-VerificationTree ([int]$child.ProcessId) }
  Stop-Process -Id $ParentId -ErrorAction SilentlyContinue
}
function Run-Godot([string]$Name, [string[]]$Arguments) {
  $freeMB = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024)
  if ($freeMB -lt 2048) { throw "Validation paused: only $freeMB MiB RAM is free; at least 2048 MiB is required. No user applications were closed." }
  $out = Join-Path $Logs ($Name + '.stdout.log')
  $err = Join-Path $Logs ($Name + '.stderr.log')
  $process = Start-Process -FilePath $Godot -ArgumentList $Arguments -WorkingDirectory $Project -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -NoNewWindow
  $ownedHandle = $process.Handle
  $timer = [Diagnostics.Stopwatch]::StartNew()
  while (-not $process.WaitForExit(1000)) {
    $process.Refresh()
    $freeMB = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024)
    if ($timer.Elapsed.TotalSeconds -gt 180 -or $process.WorkingSet64 -gt 1536MB -or $freeMB -lt 512) {
      Stop-VerificationTree $process.Id
      throw "$Name reached a time/memory safety limit; only this verification process and its own child processes were stopped."
    }
  }
  $process.Refresh()
  $content = (Get-Content -LiteralPath $out -Raw -ErrorAction SilentlyContinue) + (Get-Content -LiteralPath $err -Raw -ErrorAction SilentlyContinue)
  $script:summary += [pscustomobject]@{name=$Name;exit_code=$process.ExitCode;stdout=$out;stderr=$err}
  $script:summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Logs 'summary.json') -Encoding UTF8
  Write-Output ("{0}: exit {1}" -f $Name,$process.ExitCode)
  if ($process.ExitCode -ne 0 -or $content -match '(?m)SCRIPT ERROR:|Parse Error:|Compile Error:|^FAIL |failures=[1-9]') { throw "$Name failed; inspect logs in $Logs" }
}
Run-Godot 'import' @('--headless','--editor','--path',$Project,'--quit')
$tests = @('audio_workspace_modules_test','audio_sources_test','audio_test','audio_document_test','audio_history_budget_test','audio_synthesis_test','audio_music_test','audio_midi_test','audio_workspace_ui_test','audio_workspace_extended_test','audio_pattern_geometry_test','audio_wave_transform_test','audio_loudness_test','audio_impulse_test','audio_noise_profile_test','audio_pitch_automation_test','audio_effect_automation_test','timeline_test','timeline_multi_edit_playback_snap_test','scene_data_test','shader_library_ui_test','natural_material_test')
foreach ($test in $tests) { Run-Godot $test @('--headless','--path',$Project,'--script',("res://scripts/actors/tests/{0}.gd" -f $test)) }
Write-Output "AUDIO_WORKSPACE_GROUP_COMPLETE. Logs: $Logs"
