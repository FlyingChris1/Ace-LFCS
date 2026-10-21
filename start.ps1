$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$mp = 'C:\Program Files\Multipass\bin\multipass.exe'
if (-not (Test-Path -LiteralPath $mp)) { throw 'Install Multipass first.' }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js is required.' }
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'node_modules\node-pty'))) { throw 'Install the app dependencies first by running npm install in the project folder.' }

$listener = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($listener) {
    $owner = Get-CimInstance Win32_Process -Filter "ProcessId = $($listener.OwningProcess)"
    if ($owner.Name -eq 'node.exe' -and $owner.CommandLine -match 'server\.js') {
        try {
            $page = Invoke-WebRequest -Uri 'http://localhost:8765/' -UseBasicParsing -TimeoutSec 3
            if ($page.Content -match 'LFCS Local Lab') {
                Write-Host 'LFCS Local Lab is already running at http://localhost:8765/'
                return
            }
        } catch { }
    }
    throw "Port 8765 is already in use by PID $($listener.OwningProcess). Stop that process or configure the other service first."
}

node .\server.js
