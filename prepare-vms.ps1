$ErrorActionPreference = 'Stop'
$mp = 'C:\Program Files\Multipass\bin\multipass.exe'
$hosts = @(
    @{ Name = 'lfcs-terminal'; Ip = '192.168.10.10' },
    @{ Name = 'data-001'; Ip = '192.168.10.80' },
    @{ Name = 'data-002'; Ip = '192.168.10.90' },
    @{ Name = 'app-srv1'; Ip = '192.168.10.70' },
    @{ Name = 'web-srv1'; Ip = '192.168.10.60' }
)
$packages = 'cron vim-tiny nano curl wget git rsync tar gzip bzip2 xz-utils iproute2 iptables lvm2 nginx openssh-server nfs-kernel-server sshfs util-linux procps psmisc acl build-essential pkg-config libssl-dev e2fsprogs strace python3'
$version = (& $mp version | Select-Object -First 1) -replace '[^0-9.]',''
if ([version]$version -lt [version]'1.17.0') { throw 'Multipass 1.17 or later is required for the supported Windows HCS driver.' }
if ((& $mp get local.driver).Trim() -ne 'hcs') { & $mp set local.driver=hcs }

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
    $guestSetup | Set-Content -Encoding ascii -NoNewline (Join-Path $env:TEMP 'lfcs-base-setup.sh')
    & $mp transfer (Join-Path $env:TEMP 'lfcs-base-setup.sh') "$($vm.Name):/tmp/lfcs-base-setup.sh"
    if ($LASTEXITCODE -ne 0) { throw "Could not transfer setup to $($vm.Name)" }
    & $mp exec $vm.Name -- sudo bash -lc 'sed -i "s/\r$//" /tmp/lfcs-base-setup.sh && bash /tmp/lfcs-base-setup.sh'
    if ($LASTEXITCODE -ne 0) { throw "Account/network setup failed on $($vm.Name)" }
}

# Candidate can use SSHFS from the terminal to app-srv1 without a password prompt.
& $mp exec 'lfcs-terminal' -- sudo bash -lc 'if [ ! -s /home/candidate/.ssh/id_ed25519 ]; then sudo -u candidate -H ssh-keygen -q -t ed25519 -N "" -f /home/candidate/.ssh/id_ed25519; fi'
$publicKey = (& $mp exec 'lfcs-terminal' -- sudo cat /home/candidate/.ssh/id_ed25519.pub).Trim()
if (-not $publicKey.StartsWith('ssh-ed25519 ')) { throw 'Could not create candidate SSH key.' }
$publicKey | Set-Content -Encoding ascii -NoNewline (Join-Path $env:TEMP 'lfcs-candidate-key.pub')
foreach ($target in @('data-001','data-002','app-srv1','web-srv1')) {
    & $mp transfer (Join-Path $env:TEMP 'lfcs-candidate-key.pub') "${target}:/tmp/lfcs-candidate-key.pub"
    & $mp exec $target -- sudo bash -lc 'grep -qxF "$(cat /tmp/lfcs-candidate-key.pub)" /home/candidate/.ssh/authorized_keys 2>/dev/null || cat /tmp/lfcs-candidate-key.pub >>/home/candidate/.ssh/authorized_keys; chown -R candidate:candidate /home/candidate/.ssh; chmod 700 /home/candidate/.ssh; chmod 600 /home/candidate/.ssh/authorized_keys'
    if ($LASTEXITCODE -ne 0) { throw "Could not configure candidate SSH on $target" }
}

foreach ($vm in $hosts) { & $mp stop $vm.Name; if ($LASTEXITCODE -ne 0) { throw "Could not stop $($vm.Name)" } }
Write-Host 'HCS base VMs are ready, configured, and stopped for clean per-task clones.'
