$ErrorActionPreference = 'Stop'
$env:MULTIPASS_SERVER_ADDRESS = 'localhost:30051'
Set-Location $PSScriptRoot

$mp = 'C:\Program Files\Multipass\bin\multipass.exe'
if (-not (Test-Path -LiteralPath $mp)) { throw 'Install Multipass first.' }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js is required.' }
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'node_modules\node-pty'))) { throw 'Install the app dependencies first by running npm install in the project folder.' }

$multipassService = Get-Service -Name Multipass -ErrorAction SilentlyContinue
if (-not $multipassService -or $multipassService.Status -ne 'Running') {
    Write-Warning 'Multipass is not running. Task 8 can still run through Docker/QEMU; Multipass-based tasks will need the service restored.'
} else {
    & $mp list *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Multipass is not reachable at $env:MULTIPASS_SERVER_ADDRESS. Task 8 can still run through Docker/QEMU; configure the Multipass port before using other tasks."
    }
}

$listener = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($listener) {
    $owner = Get-CimInstance Win32_Process -Filter "ProcessId = $($listener.OwningProcess)"
    if ($owner.Name -eq 'node.exe' -and $owner.CommandLine -match 'server\.js') {
        Write-Host 'Restarting the existing LFCS app to refresh its Multipass connection. The exercise VM state will be preserved.'
        Stop-Process -Id $listener.OwningProcess -Force
        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            Start-Sleep -Milliseconds 250
            $stillListening = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue
            if (-not $stillListening) { break }
        }
        if ($stillListening) { throw 'Could not release port 8765 after stopping the old LFCS app process.' }
    } else {
        throw "Port 8765 is already in use by PID $($listener.OwningProcess). Stop that process or configure the other service first."
    }
}

node .\server.js
