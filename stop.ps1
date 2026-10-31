$ErrorActionPreference='Continue'
$env:MULTIPASS_SERVER_ADDRESS='localhost:30051'
$mp='C:\Program Files\Multipass\bin\multipass.exe'
$null = & docker.exe stop lfcs-q8-terminal-qemu 2>$null
$serverScript=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'server.js')).Path
$apps=Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq 'node.exe' -and $_.CommandLine -and
    $_.CommandLine.IndexOf($serverScript,[System.StringComparison]::OrdinalIgnoreCase) -ge 0
}
foreach($app in $apps) { Stop-Process -Id $app.ProcessId -Force }
for ($i=1; $i -le 20; $i++) { foreach ($h in @('terminal','data-001','data-002','app-srv1','web-srv1')) { & $mp stop "lfcs-q$i-$h" 2>$null } }
