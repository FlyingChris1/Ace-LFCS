$ErrorActionPreference='Continue'
$mp='C:\Program Files\Multipass\bin\multipass.exe'
Get-CimInstance Win32_Process -Filter "name = 'node.exe'" | Where-Object { $_.CommandLine -like '*LFCS\LAB\server.js*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
for ($i=1; $i -le 20; $i++) { foreach ($h in @('terminal','data-001','data-002','app-srv1','web-srv1')) { & $mp stop "lfcs-q$i-$h" 2>$null } }
