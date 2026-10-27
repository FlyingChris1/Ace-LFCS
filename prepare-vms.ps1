$ErrorActionPreference = 'Stop'
$env:MULTIPASS_SERVER_ADDRESS = 'localhost:30051'
$mp = 'C:\Program Files\Multipass\bin\multipass.exe'
if (-not (Test-Path -LiteralPath $mp)) {
    throw "Multipass was not found at '$mp'. Install Multipass before preparing the lab VMs."
}

# Multipass's Windows service owns the socket used by the CLI. Check it before
# running commands so a stopped service does not produce confusing null errors.
$multipassService = Get-Service -Name Multipass -ErrorAction SilentlyContinue
if ($multipassService -and $multipassService.Status -ne 'Running') {
    throw "The Multipass service is $($multipassService.Status). Start it from an elevated PowerShell with: Start-Service Multipass"
}

$versionOutput = & $mp version 2>&1
if ($LASTEXITCODE -ne 0 -or -not $versionOutput) {
    throw "Cannot connect to the Multipass service. Start the 'Multipass' service (for example, run 'Start-Service Multipass' in an elevated PowerShell), then rerun this script."
}
function Write-LfScript([string]$Path, [string]$Content) {
    $normalized = $Content -replace "`r`n", "`n" -replace "`r", "`n"
    [System.IO.File]::WriteAllText($Path, $normalized, [System.Text.Encoding]::ASCII)
}
function Invoke-MultipassRetry([string[]]$Arguments) {
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        & $mp @Arguments
        if ($LASTEXITCODE -eq 0) { return }
        if ($attempt -lt 5) { Start-Sleep -Seconds (2 * $attempt) }
    }
    throw "Multipass command failed after retries: $($Arguments -join ' ')"
}
$hosts = @(
    @{ Name = 'lfcs-terminal'; Ip = '192.168.10.10' },
    @{ Name = 'data-001'; Ip = '192.168.10.80' },
    @{ Name = 'data-002'; Ip = '192.168.10.90' },
    @{ Name = 'app-srv1'; Ip = '192.168.10.70' },
    @{ Name = 'web-srv1'; Ip = '192.168.10.60' }
)
$packages = 'cron vim-tiny nano curl wget git rsync tar gzip bzip2 xz-utils iproute2 iptables lvm2 nginx openssh-server nfs-kernel-server sshfs util-linux procps psmisc acl build-essential pkg-config libssl-dev e2fsprogs strace python3'
$version = ($versionOutput | Select-Object -First 1) -replace '[^0-9.]',''
if ([version]$version -lt [version]'1.17.0') { throw 'Multipass 1.17 or later is required for the supported Windows HCS driver.' }
$driverOutput = & $mp get local.driver 2>&1
if ($LASTEXITCODE -ne 0 -or -not $driverOutput) {
    throw "Could not read the Multipass driver setting. Confirm the Multipass service is running, then rerun this script."
}
if (($driverOutput | Select-Object -First 1).ToString().Trim() -ne 'hcs') { & $mp set local.driver=hcs }

foreach ($vm in $hosts) {
    $existing = (& $mp list --format csv 2>$null) -match "^$($vm.Name),"
    if (-not $existing) {
        Write-Host "Creating $($vm.Name)"
        & $mp launch 22.04 --name $vm.Name --zone zone1 --cpus 2 --memory 3G --disk 20G
        if ($LASTEXITCODE -ne 0) { throw "Could not launch $($vm.Name)" }
    } else {
        $info = & $mp info $vm.Name
        if ($info -match 'State:\s+Stopped') { & $mp start $vm.Name }
    }
    Write-Host "Installing baseline on $($vm.Name)"
    & $mp exec $vm.Name -- sudo bash -lc "if [ ! -e /var/lib/lfcs-base-ready ]; then export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq $packages && touch /var/lib/lfcs-base-ready; fi"
    if ($LASTEXITCODE -ne 0) { throw "Package setup failed on $($vm.Name)" }
    $guestSetup = @"
id candidate >/dev/null 2>&1 || useradd -m -s /bin/bash candidate
echo 'candidate ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/candidate
chmod 440 /etc/sudoers.d/candidate
mkdir -p /opt/course /imports /var/backup /var/log-collector /var/output-generator /home/candidate/.ssh
chown -R candidate:candidate /home/candidate
cat >/etc/netplan/99-lfcs-lab.yaml <<'EOF'
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      addresses:
        - $($vm.Ip)/24
EOF
chmod 600 /etc/netplan/99-lfcs-lab.yaml
if grep -q '^manage_etc_hosts:' /etc/cloud/cloud.cfg; then
    sed -i 's/^manage_etc_hosts:.*/manage_etc_hosts: false/' /etc/cloud/cloud.cfg
else
    printf '\nmanage_etc_hosts: false\n' >>/etc/cloud/cloud.cfg
fi
for entry in '192.168.10.10 terminal lfcs-terminal' '192.168.10.80 data-001' '192.168.10.90 data-002' '192.168.10.70 app-srv1' '192.168.10.60 web-srv1'; do
    ip=`${entry%% *}; names=`${entry#* }
    grep -q "^[[:space:]]*`$ip[[:space:]]" /etc/hosts || printf '%s %s\n' "`$ip" "`$names" >>/etc/hosts
done
ip address show dev eth0 | grep -q '$($vm.Ip)/24' || ip address add $($vm.Ip)/24 dev eth0
cat >/usr/local/sbin/lfcs-lab-address <<'EOF'
#!/bin/sh
ip address show dev eth0 | grep -q '$($vm.Ip)/24' || ip address add $($vm.Ip)/24 dev eth0
EOF
chmod 755 /usr/local/sbin/lfcs-lab-address
cat >/etc/systemd/system/lfcs-lab-address.service <<'EOF'
[Unit]
Description=LFCS private exercise network address
After=cloud-final.service network-online.target
Wants=network-online.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/lfcs-lab-address
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable lfcs-lab-address.service
systemctl enable --now ssh
"@
    $setupPath = Join-Path $env:TEMP 'lfcs-base-setup.sh'
    Write-LfScript $setupPath $guestSetup
    & $mp transfer $setupPath "$($vm.Name):/tmp/lfcs-base-setup.sh"
    if ($LASTEXITCODE -ne 0) { throw "Could not transfer setup to $($vm.Name)" }
    & $mp exec $vm.Name -- sudo bash /tmp/lfcs-base-setup.sh
    if ($LASTEXITCODE -ne 0) { throw "Account/network setup failed on $($vm.Name)" }
}

# Candidate can use SSHFS from the terminal to app-srv1 without a password prompt.
$keySetupPath = Join-Path $env:TEMP 'lfcs-key-setup.sh'
$keySetup = @'
#!/bin/bash
set -e
if [ ! -s /home/candidate/.ssh/id_ed25519 ]; then
    sudo -u candidate -H ssh-keygen -q -t ed25519 -N '' -f /home/candidate/.ssh/id_ed25519
fi
'@
Write-LfScript $keySetupPath $keySetup
& $mp transfer $keySetupPath 'lfcs-terminal:/tmp/lfcs-key-setup.sh'
if ($LASTEXITCODE -ne 0) { throw 'Could not transfer SSH key setup script.' }
& $mp exec 'lfcs-terminal' -- sudo bash /tmp/lfcs-key-setup.sh
if ($LASTEXITCODE -ne 0) { throw 'Could not create the candidate SSH key.' }
$publicKey = (& $mp exec 'lfcs-terminal' -- sudo cat /home/candidate/.ssh/id_ed25519.pub).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Could not read the candidate SSH public key.' }
if (-not $publicKey.StartsWith('ssh-ed25519 ')) { throw 'Could not create candidate SSH key.' }
$publicKeyPath = Join-Path $env:TEMP 'lfcs-candidate-key.pub'
Write-LfScript $publicKeyPath $publicKey
$privateKey = (& $mp exec 'lfcs-terminal' -- sudo cat /home/candidate/.ssh/id_ed25519).Trim()
if (-not $privateKey.StartsWith('-----BEGIN OPENSSH PRIVATE KEY-----')) { throw 'Could not read candidate SSH private key.' }
$privateKeyPath = Join-Path $env:TEMP 'lfcs-candidate-key'
Write-LfScript $privateKeyPath $privateKey
$authorizedKeysSetupPath = Join-Path $env:TEMP 'lfcs-authorized-keys-setup.sh'
$authorizedKeysSetup = @'
#!/bin/bash
set -e
if ! grep -Fxq -f /tmp/lfcs-candidate-key.pub /home/candidate/.ssh/authorized_keys 2>/dev/null; then
    cat /tmp/lfcs-candidate-key.pub >>/home/candidate/.ssh/authorized_keys
fi
if [ -s /tmp/lfcs-candidate-key ]; then
    install -o candidate -g candidate -m 600 /tmp/lfcs-candidate-key /home/candidate/.ssh/id_ed25519
fi
chown -R candidate:candidate /home/candidate/.ssh
chmod 700 /home/candidate/.ssh
chmod 600 /home/candidate/.ssh/authorized_keys
'@
Write-LfScript $authorizedKeysSetupPath $authorizedKeysSetup
foreach ($target in @('data-001','data-002','app-srv1','web-srv1')) {
    Invoke-MultipassRetry @('transfer', $publicKeyPath, "${target}:/tmp/lfcs-candidate-key.pub")
    Invoke-MultipassRetry @('transfer', $privateKeyPath, "${target}:/tmp/lfcs-candidate-key")
    Invoke-MultipassRetry @('transfer', $authorizedKeysSetupPath, "${target}:/tmp/lfcs-authorized-keys-setup.sh")
    Invoke-MultipassRetry @('exec', $target, '--', 'sudo', 'bash', '/tmp/lfcs-authorized-keys-setup.sh')
}
Remove-Item -LiteralPath $privateKeyPath -Force

foreach ($vm in $hosts) { & $mp stop $vm.Name; if ($LASTEXITCODE -ne 0) { throw "Could not stop $($vm.Name)" } }
Write-Host 'HCS base VMs are ready, configured, and stopped for clean per-task clones.'
