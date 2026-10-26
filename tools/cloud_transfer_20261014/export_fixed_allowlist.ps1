$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$transferRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$runId = '{0}_{1}' -f (Get-Date -Format 'yyyyMMdd_HHmmss'), ([Guid]::NewGuid().ToString('N'))
$outputDir = Join-Path $transferRoot ('output_fixed_' + $runId)
New-Item -ItemType Directory -Path $outputDir | Out-Null
$relativePaths = @(
'audio_analysis.gd','audio_asset_index.gd','audio_automation_canvas.gd','audio_automation_lane.gd','audio_automation_recording.gd','audio_composer.gd','audio_composer_controls.gd','audio_conductor.gd','audio_conductor_controls.gd','audio_document.gd','audio_doppler.gd','audio_edit_session.gd','audio_effects.gd','audio_file_preview.gd','audio_impulse.gd','audio_instruments.gd','audio_jobs.gd','audio_library.gd','audio_midi.gd','audio_midi_timeline.gd','audio_pattern_canvas.gd','audio_pcm_file.gd','audio_playback.gd','audio_preset.gd','audio_provider.gd','audio_provider_service.gd','audio_recording_prepare.gd','audio_region_edit.gd','audio_renderer.gd','audio_source_cache.gd','audio_step_controls.gd','audio_synthesis.gd','audio_templates.gd','audio_tempo_map.gd','audio_timeline_canvas.gd','audio_waveform_canvas.gd','audio_workspace.gd'
) | ForEach-Object { 'Workspaces/AudioWorkspace/' + $_ }
$relativePaths += @(
'actor_animation.gd','actor_animation_track.gd','actor_audio.gd','actor_audio_recorder.gd','actor_audio_system.gd','actor_catalog.gd','actor_clip.gd','actor_data.gd','actor_definition.gd','actor_dimension_dialog.gd','actor_file_import.gd','actor_font_picker.gd','actor_image_generator.gd','actor_inspector_state.gd','actor_keyframe.gd','actor_media_export.gd','actor_media_preview.gd','actor_object_data.gd','actor_object_definition.gd','actor_object_reference.gd','actor_project_file_picker.gd','actor_project_resource_save_dialog.gd','actor_property.gd','actor_property_batch.gd','actor_registry.gd','actor_resource_slot.gd','actor_runtime.gd','actor_scene_data.gd','actor_scene_exporter.gd','actor_screen_recorder.gd','actor_section.gd','actor_shader_time.gd','actor_text_settings.gd','actor_timeline.gd','actor_ui_gizmo.gd','actor_video.gd','audio_encoder_process.gd','editor_audio_settings.gd','windows_system_audio.gd'
) | ForEach-Object { 'scripts/actors/core/' + $_ }
if ($relativePaths.Count -ne 76 -or ($relativePaths | Sort-Object -Unique).Count -ne 76) { throw 'Allowlist count or uniqueness check failed.' }
$files = [System.Collections.Generic.List[object]]::new()
foreach ($relative in $relativePaths) {
    $candidate = Join-Path $projectRoot ($relative.Replace('/','\'))
    $resolved = (Resolve-Path -LiteralPath $candidate).Path
    if (-not $resolved.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Path escapes canonical project root.' }
    $current = Get-Item -LiteralPath $resolved -Force
    if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse point rejected.' }
    if ($current.Extension -ne '.gd') { throw 'Unexpected extension rejected.' }
    $bytes = [IO.File]::ReadAllBytes($resolved)
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    if ($text -match '(?im)-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----|(?im)\b(?:api[_-]?key|access[_-]?token|client[_-]?secret|password)\s*[:=]\s*["''][^"'']{8,}') {
        throw ('Suspicious credential-like literal in approved source path: ' + $relative)
    }
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { $digest = $hasher.ComputeHash($bytes) } finally { $hasher.Dispose() }
    $hash = ([BitConverter]::ToString($digest)).Replace('-', '').ToLowerInvariant()
    $files.Add([ordered]@{path=$relative;size_bytes=$bytes.Length;sha256=$hash})
}
$total = [long]0
foreach ($entry in $files) { $total += [long]$entry['size_bytes'] }
$manifest = [ordered]@{format='kiwi-fixed-source-snapshot.v1';project='kiwi-studios-2';created_utc=[DateTime]::UtcNow.ToString('o');file_count=$files.Count;total_size_bytes=[long]$total;files=$files}
$manifestPath = Join-Path $outputDir 'manifest.json'
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding utf8
$zipPath = Join-Path $outputDir 'kiwi-audio-actor-core-source.zip'
Add-Type -AssemblyName System.IO.Compression
$stream = [IO.File]::Open($zipPath,[IO.FileMode]::Create)
$archive = [System.IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create)
try {
    $manifestEntry = $archive.CreateEntry('manifest.json',[IO.Compression.CompressionLevel]::Optimal)
    $out = $manifestEntry.Open(); $manifestBytes=[IO.File]::ReadAllBytes($manifestPath); $out.Write($manifestBytes,0,$manifestBytes.Length); $out.Dispose()
    foreach ($row in $files) {
        $source = Join-Path $projectRoot ($row.path.Replace('/','\'))
        $entry = $archive.CreateEntry('source/' + $row.path,[IO.Compression.CompressionLevel]::Optimal)
        $input = [IO.File]::OpenRead($source); $out=$entry.Open()
        try { $input.CopyTo($out) } finally { $out.Dispose(); $input.Dispose() }
    }
} finally { $archive.Dispose() }
$zipInfo = Get-Item -LiteralPath $zipPath
if ($zipInfo.Length -gt 32MB) { throw 'Archive exceeds 32 MiB limit.' }
[pscustomobject]@{archive=$zipPath;manifest=$manifestPath;file_count=$files.Count;source_bytes=[long]$total;archive_bytes=$zipInfo.Length} | ConvertTo-Json -Depth 4
