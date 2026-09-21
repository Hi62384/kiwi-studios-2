Add-Type -AssemblyName System.Drawing
$fontCollection = New-Object System.Drawing.Text.InstalledFontCollection
try { ConvertTo-Json -InputObject @($fontCollection.Families | ForEach-Object { $_.Name } | Sort-Object -Unique) -Compress }
finally { $fontCollection.Dispose() }
