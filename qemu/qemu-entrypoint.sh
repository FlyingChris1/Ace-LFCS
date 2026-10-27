#!/usr/bin/env bash
set -euo pipefail

state=/state
base=/opt/lfcs/jammy-server-cloudimg-amd64.img
mkdir -p "$state"

if [ ! -s "$state/root.qcow2" ]; then
    qemu-img create -f qcow2 -F qcow2 -b "$base" "$state/root.qcow2" 10G
fi
for disk in vdb vdc vdd vde vdf; do
    if [ ! -e "$state/$disk.raw" ]; then
        qemu-img create -f raw "$state/$disk.raw" 100M
    fi
done

if [ ! -s "$state/seed.iso" ]; then
    : "${LFCS_SSH_PUBLIC_KEY:?LFCS_SSH_PUBLIC_KEY is required on first boot}"
    cat >"$state/user-data" <<EOF
#cloud-config
hostname: lfcs-q8-terminal
manage_etc_hosts: true
users:
  - default
  - name: candidate
    gecos: LFCS Candidate
    groups: [adm, sudo]
    shell: /bin/bash
    lock_passwd: true
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    ssh_authorized_keys:
      - $LFCS_SSH_PUBLIC_KEY
EOF
    cat >"$state/meta-data" <<'EOF'
instance-id: lfcs-q8-terminal
local-hostname: lfcs-q8-terminal
EOF
    cloud-localds "$state/seed.iso" "$state/user-data" "$state/meta-data"
fi

if [ ! -s "$state/OVMF_VARS.fd" ]; then
    cp /usr/share/OVMF/OVMF_VARS.fd "$state/OVMF_VARS.fd"
fi

exec qemu-system-x86_64 \
    -machine q35,accel=tcg \
    -cpu max -smp 2 -m 1536 \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd \
    -drive if=pflash,format=raw,file="$state/OVMF_VARS.fd" \
    -drive if=none,id=osdisk,file="$state/root.qcow2",format=qcow2 \
    -device virtio-blk-pci,drive=osdisk,bootindex=0 \
    -drive if=none,id=disk-vdb,file="$state/vdb.raw",format=raw \
    -device virtio-blk-pci,drive=disk-vdb,serial=lfcs-vdb \
    -drive if=none,id=disk-vdc,file="$state/vdc.raw",format=raw \
    -device virtio-blk-pci,drive=disk-vdc,serial=lfcs-vdc \
    -drive if=none,id=disk-vdd,file="$state/vdd.raw",format=raw \
    -device virtio-blk-pci,drive=disk-vdd,serial=lfcs-vdd \
    -drive if=none,id=disk-vde,file="$state/vde.raw",format=raw \
    -device virtio-blk-pci,drive=disk-vde,serial=lfcs-vde \
    -drive if=none,id=disk-vdf,file="$state/vdf.raw",format=raw \
    -device virtio-blk-pci,drive=disk-vdf,serial=lfcs-vdf \
    -device virtio-scsi-pci,id=scsi0 \
    -drive if=none,id=cidata,file="$state/seed.iso",format=raw,media=cdrom \
    -device scsi-cd,drive=cidata,bus=scsi0.0 \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device virtio-net-pci,netdev=net0 \
    -display none -serial stdio -monitor none -no-reboot
