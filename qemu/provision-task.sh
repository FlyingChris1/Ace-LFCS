#!/usr/bin/env bash
set -euo pipefail

for disk in vdb vdc vdd vde vdf; do
    test -b "/dev/$disk" || { echo "Missing Virtio disk /dev/$disk" >&2; exit 1; }
done

mkdir -p /mnt/backup-black /mnt/backup001 /mnt/backup002
for disk in vdc vdd vde vdf; do
    mkfs.ext4 -F "/dev/$disk" >/dev/null
done
mount /dev/vdc /mnt/backup001
mount /dev/vdd /mnt/backup002
mkdir -p /mnt/backup001/.trash /mnt/backup002/.trash
fallocate -l 50M /mnt/backup001/.trash/old-data.bin
fallocate -l 5M /mnt/backup002/used.bin

app_v1="/mnt/app-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
app_v2="/mnt/app-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
mkdir -p "$app_v1" "$app_v2"
mount /dev/vde "$app_v1"
mount /dev/vdf "$app_v2"
printf '%s\n%s\n' "$app_v1" "$app_v2" >/etc/lfcs-q8-layout

cat >/tmp/dark-matter.py <<'PY'
import ctypes
import signal
import sys

name = sys.argv[1]
size = int(sys.argv[2]) * 1024 * 1024
ctypes.CDLL(None).prctl(15, ctypes.c_char_p(name.encode()), 0, 0, 0)
memory = bytearray(size)
for offset in range(0, size, 4096):
    memory[offset] = 1
while True:
    signal.pause()
PY

python_bin="$(readlink -f "$(command -v python3)")"
cp "$python_bin" "$app_v1/dark-matter-v1"
cp "$python_bin" "$app_v2/dark-matter-v2"
chmod 755 "$app_v1/dark-matter-v1" "$app_v2/dark-matter-v2"
(exec "$app_v1/dark-matter-v1" /tmp/dark-matter.py dark-matter-v1 8) </dev/null >/dev/null 2>&1 &
(exec "$app_v2/dark-matter-v2" /tmp/dark-matter.py dark-matter-v2 48) </dev/null >/dev/null 2>&1 &

for _ in $(seq 1 20); do
    pgrep -x dark-matter-v1 >/dev/null && pgrep -x dark-matter-v2 >/dev/null && break
    sleep 1
done
pgrep -x dark-matter-v1 >/dev/null
pgrep -x dark-matter-v2 >/dev/null
v1_exe=$(readlink -f "/proc/$(pgrep -xo dark-matter-v1)/exe")
v2_exe=$(readlink -f "/proc/$(pgrep -xo dark-matter-v2)/exe")
[[ "$v1_exe" == "$app_v1/dark-matter-v1" ]]
[[ "$v2_exe" == "$app_v2/dark-matter-v2" ]]
echo "Processes ready: $app_v1/dark-matter-v1 and $app_v2/dark-matter-v2"
