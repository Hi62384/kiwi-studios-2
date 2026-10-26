$ErrorActionPreference = 'Stop'
$Project = Split-Path -Parent $PSScriptRoot
$Godot = 'C:\Users\User1\Documents\Godot_v4.6.1-stable_win64\Godot_v4.6.1-stable_win64.exe'
$Descriptor = Join-Path $PSScriptRoot 'audio_runtime_fixture.json'
$ExpectedDescriptorHash = '0a29728072f914a513a9bb15e5fcf21e7a4bcb943b8d489800a6a96e78d7b335'
if (-not (Test-Path -LiteralPath $Godot)) { throw 'Configured Godot executable is missing.' }
if ((Get-FileHash -LiteralPath $Descriptor -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExpectedDescriptorHash) { throw 'Runtime fixture descriptor changed; review it before running.' }
$Spec = Get-Content -LiteralPath $Descriptor -Raw | ConvertFrom-Json
$FailurePattern = '(?m)SCRIPT ERROR:|Parse Error:|Compile Error:|^FAIL |failures=[1-9]|^Audio (synthesis|music|MIDI) checks: [1-9][0-9]* failures\b'
function Outcome-Failure([object]$Code,[int]$Expected,[string]$Text,[string]$Limit) {
  if ($Limit) { return $Limit }
  if ($null -eq $Code) { return 'Missing process exit code.' }
  if ([int]$Code -ne $Expected) { return "Unexpected process exit code: $Code (expected $Expected)." }
  if ($Text -cmatch $FailurePattern) { return 'The test emitted a runtime error or positive failure count.' }
  return ''
}
$MatcherCases = @(
  @{code=0;expected=0;text='AUDIO_DOCUMENT checks=89 failures=0';limit='';bad=$false},
  @{code=0;expected=0;text='Audio synthesis checks: 0 failures, 50 presets';limit='';bad=$false},
  @{code=0;expected=0;text='PASS failed nested import preserves outer transaction';limit='';bad=$false},
  @{code=7;expected=7;text='EXIT_CAPTURE_PROBE expected_exit=7';limit='';bad=$false},
  @{code=0;expected=0;text='SCRIPT ERROR: example';limit='';bad=$true},
  @{code=0;expected=0;text='Parse Error: example';limit='';bad=$true},
  @{code=0;expected=0;text='Compile Error: example';limit='';bad=$true},
  @{code=0;expected=0;text='FAIL example';limit='';bad=$true},
  @{code=0;expected=0;text='AUDIO_DOCUMENT checks=89 failures=2';limit='';bad=$true},
  @{code=0;expected=0;text='Audio synthesis checks: 2 failures, 50 presets';limit='';bad=$true},
  @{code=0;expected=0;text='Audio music checks: 10 failures';limit='';bad=$true},
  @{code=0;expected=0;text='Audio MIDI checks: 1 failures';limit='';bad=$true},
  @{code=$null;expected=0;text='AUDIO_DOCUMENT checks=89 failures=0';limit='';bad=$true},
  @{code=1;expected=0;text='AUDIO_DOCUMENT checks=89 failures=0';limit='';bad=$true},
  @{code=0;expected=0;text='AUDIO_DOCUMENT checks=89 failures=0';limit='60-second phase deadline';bad=$true},
  @{code=0;expected=0;text='AUDIO_DOCUMENT checks=89 failures=0';limit='256 MiB working-set limit';bad=$true}
)
foreach ($case in $MatcherCases) {
  $detected = Outcome-Failure $case.code $case.expected $case.text $case.limit
  if (([bool]$detected) -ne ([bool]$case.bad)) { throw 'Harness outcome self-test failed.' }
}
Write-Output ("Harness outcome self-tests: {0} cases passed." -f $MatcherCases.Count)
$RunId = (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$Run = Join-Path $Project ('.godot\verification\audio_runtime\' + $RunId)
$Fixture = Join-Path $Run 'fixture'
$Logs = Join-Path $Run 'logs'
New-Item -ItemType Directory -Path $Fixture,$Logs -Force | Out-Null
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$summary = @()
function Fixture-Path([string]$Relative) {
  if ($Relative.Contains('..') -or [IO.Path]::IsPathRooted($Relative)) { throw 'Invalid fixture-relative path.' }
  return (Join-Path $Fixture $Relative)
}
foreach ($entry in $Spec.source_files) {
  $source = Join-Path $Project $entry.path
  $target = Fixture-Path $entry.path
  if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.sha256) { throw "Source changed since preparation: $($entry.path)" }
  New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
  Copy-Item -LiteralPath $source -Destination $target
  if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.sha256) { throw "Source changed during fixture copy: $($entry.path)" }
}
foreach ($entry in $Spec.support_files) {
  $target = Fixture-Path $entry.path
  New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
  [IO.File]::WriteAllText($target,[string]$entry.content,$Utf8)
}
# Only these child processes inherit test-specific application-data directories.
# No persistent settings or system environment variables are changed.
$PrivateData = Join-Path $Fixture 'private_data'
New-Item -ItemType Directory -Path $PrivateData -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $PrivateData '.gdignore'),'',$Utf8)
$env:APPDATA = $PrivateData
$env:LOCALAPPDATA = $PrivateData
function Free-MiB { return [math]::Floor((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024) }
function Owned-Children([int]$ParentId) {
  $all = @()
  foreach ($child in (Get-CimInstance Win32_Process -Filter ("ParentProcessId={0}" -f $ParentId))) {
    $all += [int]$child.ProcessId
    $all += @(Owned-Children ([int]$child.ProcessId))
  }
  return $all
}
function Stop-Own-Tree([Diagnostics.Process]$Process) {
  foreach ($childId in @(Owned-Children $Process.Id)) { Stop-Process -Id $childId -ErrorAction SilentlyContinue }
  if (-not $Process.HasExited) { $Process.Kill() }
}
function Run-Runtime([string]$Name,[string]$Script,[int]$ExpectedExit = 0) {
  $free = Free-MiB
  if ($free -lt 640) { throw "Runtime check paused: $free MiB free; 640 MiB required before each phase." }
  $stdout = Join-Path $Logs ($Name + '.stdout.log')
  $stderr = Join-Path $Logs ($Name + '.stderr.log')
  $arguments = @('--headless','--path',('"' + $Fixture + '"'),'--script',$Script)
  # Use Process.Start directly. Windows PowerShell Start-Process can return
  # a Process wrapper whose ExitCode stays null after the child has exited.
  $startInfo = New-Object Diagnostics.ProcessStartInfo
  $startInfo.FileName = $Godot
  $startInfo.Arguments = $arguments -join ' '
  $startInfo.WorkingDirectory = $Fixture
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $process = New-Object Diagnostics.Process
  $process.StartInfo = $startInfo
  if (-not $process.Start()) { throw "Could not start $Name" }
  $ownedHandle = $process.Handle
  $outputFile = [IO.File]::Open($stdout,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  $errorFile = [IO.File]::Open($stderr,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  $outputTask = $process.StandardOutput.BaseStream.CopyToAsync($outputFile)
  $errorTask = $process.StandardError.BaseStream.CopyToAsync($errorFile)
  $timer = [Diagnostics.Stopwatch]::StartNew()
  $peak = 0L
  $lowestFree = $free
  $limit = ''
  while (-not $process.WaitForExit(100)) {
    $process.Refresh()
    $working = [long]$process.WorkingSet64
    foreach ($childId in @(Owned-Children $process.Id)) {
      $child = Get-Process -Id $childId -ErrorAction SilentlyContinue
      if ($null -ne $child) { $working += [long]$child.WorkingSet64 }
    }
    $peak = [math]::Max($peak,[math]::Max($working,[long]$process.PeakWorkingSet64))
    $free = Free-MiB
    $lowestFree = [math]::Min($lowestFree,$free)
    if ($peak -gt 256MB) { $limit = '256 MiB owned-process-tree working-set limit' }
    elseif ($free -lt 384) { $limit = '384 MiB system-free-memory floor' }
    elseif ($timer.Elapsed.TotalSeconds -gt 60) { $limit = '60-second phase deadline' }
    if ($limit) { Stop-Own-Tree $process; $process.WaitForExit(); break }
  }
  $process.WaitForExit()
  $exitCode = $process.ExitCode
  $outputTask.Wait(); $errorTask.Wait()
  $outputFile.Dispose(); $errorFile.Dispose()
  # Exited processes can no longer expose counters on some .NET builds.
  # Retain observed peak telemetry without discarding the real exit status.
  try { $peak = [math]::Max($peak,[long]$process.PeakWorkingSet64) } catch { if (-not $process.HasExited) { throw } }
  if ($peak -gt 256MB -and -not $limit) { $limit = '256 MiB peak working-set limit' }
  $content = (Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue) + (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue)
  $script:summary += [pscustomobject]@{name=$Name;exit_code=$exitCode;expected_exit=$ExpectedExit;seconds=[math]::Round($timer.Elapsed.TotalSeconds,3);peak_tree_mib=[math]::Round($peak/1MB,2);lowest_free_mib=$lowestFree;limit=$limit;stdout=$stdout;stderr=$stderr}
  $script:summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Logs 'summary.json') -Encoding UTF8
  Write-Output ("{0}: exit {1}; peak {2:N1} MiB; lowest free {3} MiB" -f $Name,$exitCode,($peak/1MB),$lowestFree)
  if ($limit) { throw "$Name stopped at $limit. Only its own process tree was stopped. Logs: $Logs" }
  $failure = Outcome-Failure $exitCode $ExpectedExit $content $limit
  if ($failure) { throw "${Name} failed: $failure Logs: $Logs" }
  $process.Dispose()
}
Write-Output 'RUNTIME-ONLY COPIED-SOURCE CHECK: no editor import, no full application, no codecs or real recording devices.'
Write-Output "Fixture and logs: $Run"
Run-Runtime 'exit_capture_probe' 'res://exit_capture_probe.gd' 7
Run-Runtime 'bootstrap' 'res://bootstrap.gd'
foreach ($test in $Spec.tests) { Run-Runtime $test ("res://scripts/actors/tests/{0}.gd" -f $test) }
Write-Output "AUDIO_RUNTIME_SUBSET_COMPLETE. Six module/synthesis/document/MIDI tests only. Logs: $Logs"
