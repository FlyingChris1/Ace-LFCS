$ErrorActionPreference='Continue'
$mp='C:\Program Files\Multipass\bin\multipass.exe'
for ($i=1; $i -le 20; $i++) { foreach ($h in @('terminal','data-001','data-002','app-srv1','web-srv1')) { & $mp delete --purge "lfcs-q$i-$h" 2>$null } }
Write-Host 'Removed task VMs. Base VMs are untouched.'
