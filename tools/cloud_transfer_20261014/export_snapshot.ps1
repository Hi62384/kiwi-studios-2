$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$outputDir = Join-Path $PSScriptRoot 'output'
$maxZipBytes = 32MB
$extensions = @('.gd','.gdshader','.tscn','.tres','.json','.md','.txt','.py','.ps1','.cmd','.bat','.toml','.cfg','.ini','.yml','.yaml','.csv','.cs','.h','.cpp','.glsl')
$includeFiles = @('AGENTS.md','project.godot','tasks.txt')
$includeRoots = @('Workspaces','scripts','tests','scenes','CustomNodes','resources','docs','tools')
$skipDirectoryNames = @('.git','.godot','.gradle','.venv','__pycache__','cache','caches','output','save','saves','gameprojects','game_projects')
$skipExtensions = @('.wav','.ogg','.mp3','.flac','.aac','.m4a','.png','.jpg','.jpeg','.webp','.gif','.bmp','.tif','.tiff','.svg','.obj','.fbx','.glb','.gltf','.blend','.mesh','.res','.import','.zip','.exe','.dll','.so','.bin','.model','.safetensors','.pt','.pth','.onnx','.ckpt','.weights','.tresbinary')
if (Test-Path -LiteralPath $outputDir) { throw "Output path already exists; refusing overwrite: $outputDir" }
New-Item -ItemType Directory -Path $outputDir | Out-Null

$selected = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
foreach ($relativeRoot in $includeRoots) {
    $fullRoot = Join-Path $projectRoot $relativeRoot
    if (-not (Test-Path -LiteralPath $fullRoot -PathType Container)) { continue }
    $pending = [System.Collections.Generic.Stack[string]]::new()
    $pending.Push($fullRoot)
    while ($pending.Count -gt 0) {
        $dir = $pending.Pop()
        $item = Get-Item -LiteralPath $dir -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        foreach ($child in Get-ChildItem -LiteralPath $dir -Force) {
            if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            if ($child.PSIsContainer) {
                if ($skipDirectoryNames -notcontains $child.Name.ToLowerInvariant()) { $pending.Push($child.FullName) }
                continue
            }
            $ext = $child.Extension.ToLowerInvariant()
            if ($skipExtensions -contains $ext) { continue }
            if ($extensions -contains $ext) { $selected.Add($child) }
        }
    }
}
foreach ($name in $includeFiles) {
    $p = Join-Path $projectRoot $name
    if (Test-Path -LiteralPath $p -PathType Leaf) {
        $item = Get-Item -LiteralPath $p -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { $selected.Add($item) }
    }
}
$selected = [System.Collections.Generic.List[System.IO.FileInfo]]@($selected | Sort-Object FullName -Unique)
$manifestEntries = [System.Collections.Generic.List[object]]::new()
foreach ($file in $selected) {
    $relative = [IO.Path]::GetRelativePath($projectRoot, $file.FullName).Replace('\','/')
    if ($relative -match '(^|/)(\.env|credentials?|secrets?|private[_-]?keys?)(/|\.|$)' -or $relative -match '(^|/)(id_rsa|id_ed25519)(\.|$)') { continue }
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifestEntries.Add([ordered]@{path=$relative;size_bytes=$file.Length;sha256=$hash})
}
$total = ($manifestEntries | Measure-Object -Property size_bytes -Sum).Sum
$manifest = [ordered]@{format='kiwi-source-snapshot.v1';project='kiwi-studios-2';created_utc=[DateTime]::UtcNow.ToString('o');file_count=$manifestEntries.Count;total_size_bytes=[long]$total;files=$manifestEntries}
$manifestPath = Join-Path $outputDir 'manifest.json'
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding utf8

$part = 1
$partFiles = [System.Collections.Generic.List[string]]::new()
$zipPath = Join-Path $outputDir ('kiwi-source-{0:D2}.zip' -f $part)
$archive = [System.IO.Compression.ZipArchive]::new([IO.File]::Open($zipPath,[IO.FileMode]::Create),[IO.Compression.ZipArchiveMode]::Create)
try {
    $manifestBytes = [IO.File]::ReadAllBytes($manifestPath)
    $entry = $archive.CreateEntry('manifest.json',[IO.Compression.CompressionLevel]::Optimal)
    $stream = $entry.Open(); $stream.Write($manifestBytes,0,$manifestBytes.Length); $stream.Dispose()
    foreach ($row in $manifestEntries) {
        $source = Join-Path $projectRoot ($row.path.Replace('/','\'))
        $entryName = 'source/' + $row.path
        $entry = $archive.CreateEntry($entryName,[IO.Compression.CompressionLevel]::Optimal)
        $inStream = [IO.File]::OpenRead($source); $outStream = $entry.Open()
        try { $inStream.CopyTo($outStream) } finally { $outStream.Dispose(); $inStream.Dispose() }
        if ((Get-Item -LiteralPath $zipPath).Length -gt $maxZipBytes) {
            $archive.Dispose()
            Remove-Item -LiteralPath $zipPath -Force
            if ($partFiles.Count -eq 0) { throw "A single-file compressed snapshot part exceeded 32 MiB: $($row.path)" }
            $part++
            $zipPath = Join-Path $outputDir ('kiwi-source-{0:D2}.zip' -f $part)
            $archive = [System.IO.Compression.ZipArchive]::new([IO.File]::Open($zipPath,[IO.FileMode]::Create),[IO.Compression.ZipArchiveMode]::Create)
            $entry = $archive.CreateEntry('manifest.json',[IO.Compression.CompressionLevel]::Optimal)
            $stream = $entry.Open(); $stream.Write($manifestBytes,0,$manifestBytes.Length); $stream.Dispose()
            $entry = $archive.CreateEntry($entryName,[IO.Compression.CompressionLevel]::Optimal)
            $inStream = [IO.File]::OpenRead($source); $outStream = $entry.Open()
            try { $inStream.CopyTo($outStream) } finally { $outStream.Dispose(); $inStream.Dispose() }
        }
    }
} finally { if ($archive) { $archive.Dispose() } }
Get-ChildItem -LiteralPath $outputDir -Filter 'kiwi-source-*.zip' | ForEach-Object { $partFiles.Add($_.FullName) }
if ($partFiles.Count -gt 1) { Remove-Item -LiteralPath (Join-Path $outputDir 'kiwi-source-01.zip') -Force }
[pscustomobject]@{manifest=$manifestPath;files=$manifestEntries.Count;source_bytes=[long]$total;archives=($partFiles | ForEach-Object { [pscustomobject]@{path=$_;size_bytes=(Get-Item -LiteralPath $_).Length} })} | ConvertTo-Json -Depth 5
