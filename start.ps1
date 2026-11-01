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

$serverScript = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'server.js')).Path
$existingApps = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq 'node.exe' -and $_.CommandLine -and
    $_.CommandLine.IndexOf($serverScript, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
})
foreach ($app in $existingApps) {
    Write-Host "Restarting the existing LFCS app (PID $($app.ProcessId)); exercise VM state will be preserved."
    Stop-Process -Id $app.ProcessId -Force
}
if ($existingApps.Count -gt 0) {
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        Start-Sleep -Milliseconds 250
        $stillRunning = @(Get-CimInstance Win32_Process | Where-Object {
            $_.Name -eq 'node.exe' -and $_.CommandLine -and
            $_.CommandLine.IndexOf($serverScript, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        if ($stillRunning.Count -eq 0) { break }
    }
    if ($stillRunning.Count -gt 0) { throw 'Could not stop the previous LFCS app process.' }
}

$stateDir = Join-Path $PSScriptRoot '.lab-state'
$portFile = Join-Path $stateDir 'ui-port.txt'
$preferredPort = 8765
if (Test-Path -LiteralPath $portFile) {
    $savedPort = 0
    if ([int]::TryParse((Get-Content -LiteralPath $portFile -Raw).Trim(), [ref]$savedPort) -and $savedPort -ge 8765 -and $savedPort -le 9000) {
        $preferredPort = $savedPort
    }
}
$portCandidates = @($preferredPort) + @(8765..9000 | Where-Object { $_ -ne $preferredPort })
$selectedPort = $null
foreach ($port in $portCandidates) {
    $probe = $null
    try {
        $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
        $probe.Start()
        $selectedPort = $port
        break
    } catch {
        # Windows may reserve a port for Hyper-V/WSL even when no process listens on it.
    } finally {
        if ($probe) { $probe.Stop() }
    }
}
if (-not $selectedPort) { throw 'No available localhost port found between 8765 and 9000.' }
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
Set-Content -LiteralPath $portFile -Value "$selectedPort" -NoNewline
$env:LFCS_PORT = "$selectedPort"
if ($selectedPort -ne 8765) { Write-Host "Port 8765 is unavailable; using http://localhost:$selectedPort instead." }

node $serverScript
