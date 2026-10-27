$ErrorActionPreference = 'Stop'

$port = 30051
$address = "localhost:$port"
$cli = 'C:\Program Files\Multipass\bin\multipass.exe'
$daemon = 'C:\Program Files\Multipass\bin\multipassd.exe'
$serviceKey = 'HKLM:\System\CurrentControlSet\Services\Multipass'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell (Run as administrator).'
}
if (-not (Test-Path -LiteralPath $cli) -or -not (Test-Path -LiteralPath $daemon)) {
    throw 'Multipass was not found in C:\Program Files\Multipass\bin.'
}

# Refuse to overwrite another listener or a Windows-reserved port. Allow the
# Multipass service itself so the script can be safely re-run.
$service = Get-Service -Name Multipass -ErrorAction Stop
$listeners = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
foreach ($listener in $listeners) {
    $owner = Get-CimInstance Win32_Process -Filter "ProcessId = $($listener.OwningProcess)"
    if ($owner.Name -ne 'multipassd.exe') {
        throw "TCP port $port is already in use by $($owner.Name). Choose another free port before configuring Multipass."
    }
    if ($service.Status -ne 'Running') {
        throw "A manually started multipassd.exe is using port $port. Stop that process with Ctrl+C, then rerun this script."
    }
}
foreach ($family in @('ipv4', 'ipv6')) {
    $ranges = & netsh int $family show excludedportrange protocol=tcp
    foreach ($line in $ranges) {
        if ($line -match '^\s*(\d+)\s+(\d+)') {
            if ($port -ge [int]$Matches[1] -and $port -le [int]$Matches[2]) {
                throw "TCP port $port is reserved by Windows for $family. Choose another free port."
            }
        }
    }
}

$oldImagePath = (Get-ItemProperty -LiteralPath $serviceKey -Name ImagePath).ImagePath
if (-not $oldImagePath) { throw 'Could not read the current Multipass service command line.' }
$oldMachineAddress = [Environment]::GetEnvironmentVariable('MULTIPASS_SERVER_ADDRESS', 'Machine')
$backupName = 'ImagePathBeforeLfcsPort'
if (-not (Get-ItemProperty -LiteralPath $serviceKey -Name $backupName -ErrorAction SilentlyContinue)) {
    New-ItemProperty -LiteralPath $serviceKey -Name $backupName -Value $oldImagePath -PropertyType String | Out-Null
}

$serviceArgs = $oldImagePath -replace '^"[^"]+"\s*', ''
$serviceArgs = $serviceArgs -replace '\s+--address(?:\s+\S+)?', ''
$newImagePath = '"{0}" {1} --address {2}' -f $daemon, $serviceArgs.Trim(), $address

Set-ItemProperty -LiteralPath $serviceKey -Name ImagePath -Value $newImagePath
[Environment]::SetEnvironmentVariable('MULTIPASS_SERVER_ADDRESS', $address, 'Machine')
$env:MULTIPASS_SERVER_ADDRESS = $address

try {
    Set-Service -Name Multipass -StartupType Automatic
    $service = Get-Service -Name Multipass
    if ($service.Status -ne 'Stopped') {
        Stop-Service -Name Multipass -Force
        $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20))
    }
    Start-Service -Name Multipass
    (Get-Service -Name Multipass).WaitForStatus('Running', [TimeSpan]::FromSeconds(20))
    & $cli list | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Multipass did not respond on the configured address.' }
    Write-Host "Multipass is running on $address. The address is saved system-wide and the LFCS scripts use it explicitly."
} catch {
    Set-ItemProperty -LiteralPath $serviceKey -Name ImagePath -Value $oldImagePath
    [Environment]::SetEnvironmentVariable('MULTIPASS_SERVER_ADDRESS', $oldMachineAddress, 'Machine')
    throw "Multipass could not be switched to $address. The original service command was restored. Details: $($_.Exception.Message)"
}
