$ErrorActionPreference='Continue'
$mp='C:\Program Files\Multipass\bin\multipass.exe'
$listeners=Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue
foreach($pidValue in ($listeners | Select-Object -ExpandProperty OwningProcess -Unique)) {
    $process=Get-CimInstance Win32_Process -Filter "ProcessId = $pidValue"
    if($process.Name -eq 'node.exe' -and $process.CommandLine -match 'server\.js') { Stop-Process -Id $pidValue -Force }
}
for ($i=1; $i -le 20; $i++) { foreach ($h in @('terminal','data-001','data-002','app-srv1','web-srv1')) { & $mp stop "lfcs-q$i-$h" 2>$null } }
