$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$delivery = (Resolve-Path -LiteralPath $PSScriptRoot).Path
if (-not $delivery.StartsWith($root + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Delivery path escaped project root.' }
$helper = Join-Path $delivery 'library_file_transfer.py'
$inputPath = Join-Path $delivery 'materialize_input.json'
$archive = Join-Path $delivery 'kiwi_current_correctness_20261014.zip'
$pythonCommand = Get-Command python3.exe,python.exe,py.exe -ErrorAction SilentlyContinue | Select-Object -First 1
$python = $null
$pythonArgs = ''
if ($pythonCommand) {
  $python = $pythonCommand.Source
  if ($pythonCommand.Name -eq 'py.exe') { $pythonArgs = '-3 ' }
} else {
  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313\python.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311\python.exe'),
    'C:\Python313\python.exe','C:\Python312\python.exe','C:\Python311\python.exe'
  )
  foreach ($candidate in $candidates) { if (Test-Path -LiteralPath $candidate -PathType Leaf) { $python = $candidate; break } }
}
if (-not $python) { throw 'Python interpreter not found in standard locations.' }
$start = New-Object System.Diagnostics.ProcessStartInfo
$start.FileName = $python
$start.Arguments = $pythonArgs + '"' + $helper + '" materialize "' + $archive + '"'
$start.UseShellExecute = $false
$start.RedirectStandardInput = $true
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$process = New-Object System.Diagnostics.Process
$process.StartInfo = $start
[void]$process.Start()
$json = Get-Content -LiteralPath $inputPath -Raw
$process.StandardInput.Write($json)
$process.StandardInput.Close()
$stdout = $process.StandardOutput.ReadToEnd()
$stderr = $process.StandardError.ReadToEnd()
$process.WaitForExit()
Remove-Item -LiteralPath $inputPath -Force
if ($process.ExitCode -ne 0) { throw ('Materialization helper failed: ' + $stderr) }
if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) { throw 'Materialized archive missing.' }
$actualSize = (Get-Item -LiteralPath $archive).Length
$actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualSize -ne 292770) { throw ('Archive size mismatch: ' + $actualSize) }
if ($actualHash -ne '1897f9cce5378a2ea124ae15a16d526159ab050b80cd8e81a735a0e88b5e1530') { throw 'Archive SHA-256 mismatch.' }
Add-Type -AssemblyName System.IO.Compression
$zip = [IO.Compression.ZipFile]::OpenRead($archive)
try {
  $names = @($zip.Entries | ForEach-Object { $_.FullName })
  foreach ($name in $names) { if ([IO.Path]::IsPathRooted($name) -or $name.Split('/') -contains '..' -or $name.Contains('\')) { throw 'Unsafe ZIP entry path.' } }
  $metadata = @()
  foreach ($e in $zip.Entries) {
    if ($e.FullName -eq 'apply_manifest.json' -or $e.FullName -eq 'bridge_payload.json') {
      $reader = New-Object IO.StreamReader($e.Open())
      try { $metadata += [pscustomobject]@{name=$e.FullName;text=$reader.ReadToEnd()} } finally { $reader.Dispose() }
    }
  }
} finally { $zip.Dispose() }
[pscustomobject]@{archive=$archive;size_bytes=$actualSize;sha256=$actualHash;entries=$names;metadata=$metadata} | ConvertTo-Json -Depth 12
