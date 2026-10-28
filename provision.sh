#!/bin/bash
set -eu
q="$1"
target_host="${2:-$HOSTNAME}"
printf '%s\n' "$target_host" >/etc/lfcs-task-host
mkdir -p /opt/course/1 /opt/course/4 /opt/course/11 /imports /var/backup/backup-015/{small,large,compromised} /var/log-collector/003 /var/output-generator /home/candidate
if grep -q '^manage_etc_hosts:' /etc/cloud/cloud.cfg; then
 sed -i 's/^manage_etc_hosts:.*/manage_etc_hosts: false/' /etc/cloud/cloud.cfg
else
 printf '\nmanage_etc_hosts: false\n' >>/etc/cloud/cloud.cfg
fi
for entry in '192.168.10.10 terminal lfcs-terminal' '192.168.10.80 data-001' '192.168.10.90 data-002' '192.168.10.70 app-srv1' '192.168.10.60 web-srv1'; do
 ip=${entry%% *}; names=${entry#* }
 grep -q "^[[:space:]]*$ip[[:space:]]" /etc/hosts || printf '%s %s\n' "$ip" "$names" >>/etc/hosts
done
groupadd -f dev
groupadd -f op
groupadd -f operators
case "$q" in
1)
 timedatectl set-timezone Etc/UTC
 printf 'net.ipv4.ip_forward=1\n' >/etc/sysctl.d/90-lfcs-q1.conf
 sysctl -w net.ipv4.ip_forward=1 >/dev/null
 ;;
2)
 useradd -m -s /bin/bash asset-manager 2>/dev/null || true
 sed -i '\|bash /home/asset-manager/generate.sh|d' /etc/crontab
 echo '30 20 * * * root bash /home/asset-manager/generate.sh' >>/etc/crontab
 mkdir -p /home/asset-manager; touch /home/asset-manager/{generate,clean}.sh; chown -R asset-manager:asset-manager /home/asset-manager
 systemctl enable --now cron
 ;;
3) mkdir -p /etc/systemd/timesyncd.conf.d; printf '[Time]\n' >/etc/systemd/timesyncd.conf ;;
4) sed -i '1i export VARIABLE1=random-string' /home/candidate/.bashrc; cp /home/candidate/.bashrc /opt/course/4/bashrc.baseline; chown candidate:candidate /home/candidate/.bashrc ;;
5) mkdir -p /tmp/import001; printf 'sample import data\n' >/tmp/import001/data.txt; tar -cjf /imports/import001.tar.bz2 -C /tmp/import001 . ;;
6)
 useradd -m -s /bin/bash user1 2>/dev/null || true
 mkdir -p /home/accounts/user1
 chown user1:user1 /home/accounts/user1
 # Keep the requested changes for the candidate; only the source account and
 # target command exist in the initial state.
 userdel -r user2 2>/dev/null || true
 rm -f /etc/sudoers.d/user2
 printf '#!/bin/bash\necho dangerous\n' >/root/dangerous.sh; chmod 700 /root/dangerous.sh
 ;;
7)
 if [ "$target_host" = data-002 ]; then
   cat >/tmp/lfcs-api.py <<'PY'
#!/usr/bin/python3
from http.server import BaseHTTPRequestHandler,HTTPServer
import sys
port=int(sys.argv[1])
class H(BaseHTTPRequestHandler):
 def do_GET(self):
  body=('listener %d\n'%port).encode(); self.send_response(200); self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body)
 def log_message(self,*a): pass
HTTPServer(('0.0.0.0',port),H).serve_forever()
PY
   for port in 5000 6001 6002; do nohup python3 /tmp/lfcs-api.py "$port" >/dev/null 2>&1 </dev/null & done
 elif [ "$target_host" = app-srv1 ]; then
   nohup python3 -m http.server 7070 --bind 192.168.10.70 >/var/log/lfcs-api-7070.log 2>&1 </dev/null &
 fi
 ;;
8)
 mkdir -p /mnt/backup-black /mnt/backup001 /mnt/backup002
 for d in vdb vdc vdd vde vdf; do test -b "/dev/$d" || { echo "Required virtual disk /dev/$d is missing." >&2; exit 1; }; done
 for d in vdc vdd vde vdf; do mkfs.ext4 -F "/dev/$d" >/dev/null; done
 mount /dev/vdc /mnt/backup001; mount /dev/vdd /mnt/backup002
 mkdir -p /mnt/backup001/.trash /mnt/backup002/.trash
 fallocate -l 50M /mnt/backup001/.trash/old-data.bin || dd if=/dev/zero of=/mnt/backup001/.trash/old-data.bin bs=1M count=50 status=none
 fallocate -l 5M /mnt/backup002/used.bin || dd if=/dev/zero of=/mnt/backup002/used.bin bs=1M count=5 status=none
 app_v1="/mnt/app-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
 app_v2="/mnt/app-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
 mkdir -p "$app_v1" "$app_v2"
 mount /dev/vde "$app_v1"; mount /dev/vdf "$app_v2"
 printf '%s\n%s\n' "$app_v1" "$app_v2" >/etc/lfcs-q8-layout
 cat >/tmp/dark-matter.py <<'PY'
import ctypes, signal, sys
name = sys.argv[1]
size = int(sys.argv[2]) * 1024 * 1024
ctypes.CDLL(None).prctl(15, ctypes.c_char_p(name.encode()), 0, 0, 0)
memory = bytearray(size)
for offset in range(0, size, 4096): memory[offset] = 1
while True: signal.pause()
PY
cp -L "$(command -v python3)" "$app_v1/dark-matter-v1"
cp -L "$(command -v python3)" "$app_v2/dark-matter-v2"
 chmod +x "$app_v1/dark-matter-v1" "$app_v2/dark-matter-v2"
 (exec "$app_v1/dark-matter-v1" /tmp/dark-matter.py dark-matter-v1 8) </dev/null >/dev/null 2>&1 &
 (exec "$app_v2/dark-matter-v2" /tmp/dark-matter.py dark-matter-v2 48) </dev/null >/dev/null 2>&1 &
 ;;
9)
 for n in old smallfile largefile openfile; do touch "/var/backup/backup-015/$n"; done
 touch -d '2019-01-01' /var/backup/backup-015/old
 truncate -s 1000 /var/backup/backup-015/smallfile
 truncate -s 12000 /var/backup/backup-015/largefile
 truncate -s 5000 /var/backup/backup-015/openfile
 chmod 777 /var/backup/backup-015/openfile
 ;;
10)
 if [ "$target_host" = terminal ]; then
   mkdir -p /nfs/share /data-export
   for n in 1 2 3; do printf 'NFS fixture %s\n' "$n" >"/nfs/share/$n.log"; done
   mkdir -p /app-srv1/data-export
   chown candidate:candidate /app-srv1/data-export
   sed -i 's/^#user_allow_other/user_allow_other/' /etc/fuse.conf
   systemctl enable --now nfs-kernel-server
   ssh-keygen -R app-srv1 -f /home/candidate/.ssh/known_hosts >/dev/null 2>&1 || true
   ssh-keygen -R 192.168.10.70 -f /home/candidate/.ssh/known_hosts >/dev/null 2>&1 || true
   ssh-keyscan -H app-srv1 192.168.10.70 >>/home/candidate/.ssh/known_hosts 2>/dev/null || true
   chown candidate:candidate /home/candidate/.ssh/known_hosts
   install -d -o root -g root -m 700 /root/.ssh
   install -o root -g root -m 600 /home/candidate/.ssh/id_ed25519 /root/.ssh/id_ed25519
   install -o root -g root -m 600 /home/candidate/.ssh/known_hosts /root/.ssh/known_hosts
   printf 'Host app-srv1\n    User candidate\n    IdentityFile /root/.ssh/id_ed25519\n    IdentitiesOnly yes\n' >/root/.ssh/config
   chmod 600 /root/.ssh/config
 else
   mkdir -p /data-export /nfs/terminal/share
   touch /data-export/datRTG_1.gz /data-export/datRTG_2.gz
   chown -R candidate:candidate /data-export
 fi
 ;;
11)
 apt-get update -qq
 DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io
 systemctl enable --now docker
 docker pull nginx:alpine >/dev/null
 docker run -d --name frontend_v1 nginx:alpine >/dev/null
 docker run -d --name frontend_v2 -v /var/lib/frontend-data:/usr/share/nginx/html nginx:alpine >/dev/null
 ;;
12)
 mkdir -p /repositories/auto-verifier /home/candidate/repositories
 chown -R candidate:candidate /home/candidate/repositories
 sudo -u candidate git config --global user.email candidate@lfcs.lab
 sudo -u candidate git config --global user.name Candidate
 git config --global --add safe.directory /home/candidate/repositories/auto-verifier
 cd /repositories/auto-verifier; git init -q -b main; git config user.email lab@example.invalid; git config user.name Lab
 echo 'user_registration_level: disabled' >config.yaml; git add .; git commit -qm base
 for b in dev4 dev5 dev6; do git checkout -qb "$b"; echo "user_registration_level: $b" >config.yaml; git add .; git commit -qm "$b"; done
 git checkout main; git checkout -q dev5; echo 'user_registration_level: open' >config.yaml; git commit -qam qualifying; git checkout -q main
 chown -R candidate:candidate /repositories/auto-verifier
 ;;
13)
 mkdir -p /usr/local/lib/lfcs
 cat >/tmp/collector.c <<'EOF'
#include <signal.h>
#include <unistd.h>
int main(int argc,char **argv){if(argc>1&&argv[1][0]=='1'){for(;;){kill(getpid(),0);sleep(1);}}for(;;)sleep(1);}
EOF
 gcc /tmp/collector.c -o /bin/collector1
 gcc /tmp/collector.c -o /bin/collector2
 gcc /tmp/collector.c -o /bin/collector3
 (exec -a collector1 /bin/collector1 0) </dev/null >/dev/null 2>&1 &
 (exec -a collector2 /bin/collector2 1) </dev/null >/dev/null 2>&1 &
 (exec -a collector3 /bin/collector3 0) </dev/null >/dev/null 2>&1 &
 ;;
14)
 rm -f /var/output-generator/{1,2,3,4}.out
 chown candidate:candidate /var/output-generator
 cat >/bin/output-generator <<'EOF'
#!/usr/bin/python3
import os

stamp = '2021/07/20 08:58:20'
run_id = 'a99947a1-2f68-475e-9326-32dbd4876f60'

def write_all(fd, data):
    view = memoryview(data)
    while view:
        written = os.write(fd, view)
        view = view[written:]

stdout = ''.join(f'{stamp} {i} - {run_id}\n' for i in range(20342)).encode()
stderr = ''.join(f'{stamp} {i} - {run_id}\n' for i in range(20342, 32678)).encode()
write_all(1, stdout)
write_all(2, stderr)
raise SystemExit(123)
EOF
 chmod +x /bin/output-generator
 ;;
15) mkdir -p /tools
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libevent-dev libgnutls28-dev libgpm-dev zlib1g-dev
    curl -fsSL https://links.twibright.com/download/links-2.14.tar.bz2 -o /tools/links-2.14.tar.bz2
    ;;
16)
 cat >/etc/nginx/sites-available/app1 <<'EOF'
server {
        listen 1111 default_server;
        listen [::]:1111 default_server;

        server_name _;

        location / {
                return 200 'app1\n';
        }
}
EOF
 cat >/etc/nginx/sites-available/app2 <<'EOF'
server {
        listen 2222 default_server;
        listen [::]:2222 default_server;

        server_name _;

        location /special {
                return 200 'app2 special\n';
        }

        location / {
                return 200 'app2\n';
        }
}
EOF
 ln -sfn /etc/nginx/sites-available/app1 /etc/nginx/sites-enabled/app1
 ln -sfn /etc/nginx/sites-available/app2 /etc/nginx/sites-enabled/app2
 nginx -t
 systemctl enable --now nginx
 systemctl restart nginx
 for _ in $(seq 1 20); do curl -fsS http://192.168.10.60:1111/ >/dev/null 2>&1 && curl -fsS http://192.168.10.60:2222/special >/dev/null 2>&1 && break; sleep 1; done
 ;;
17)
 useradd -m -s /bin/bash marta 2>/dev/null || true; useradd -m -s /bin/bash cilla 2>/dev/null || true
 echo 'marta:marta' | chpasswd; echo 'cilla:cilla' | chpasswd
 printf 'Hello our favorite user!\n' >/etc/ssh/sshd-banner
 rm -f /etc/ssh/sshd_config.d/*.conf
 sed -i '/^[[:space:]]*X11Forwarding[[:space:]]/d; /^[[:space:]]*PasswordAuthentication[[:space:]]/d' /etc/ssh/sshd_config
 printf '\nX11Forwarding yes\nPasswordAuthentication yes\n' >>/etc/ssh/sshd_config
 ;;
18)
 mkdir -p /var/lib/lfcs-lvm
 for d in vdg vdh; do truncate -s 100M "/var/lib/lfcs-lvm/$d.img"; dev=$(losetup --find --show "/var/lib/lfcs-lvm/$d.img"); ln -sf "$dev" "/dev/$d"; done
 pvcreate -ff -y /dev/vdg /dev/vdh >/dev/null
 vgcreate vol1 /dev/vdg /dev/vdh >/dev/null
 lvcreate --size 12M --name p1 vol1 >/dev/null
 ;;
19)
 python3 - <<'PY'
from pathlib import Path
import random
p=Path('/var/log-collector/003')
random.seed(1903)
rows=[]
for i in range(360):
 if i < 27:
  url='/app/user/%d'%i
  agent='hacker-bot/1.2'
 else:
  url=random.choice(['/app/admin/%d'%i,'/health','/status/%d'%i])
  agent=random.choice(['hacker-bot/1.2','Mozilla/5.0','curl/7.81'])
 rows.append('127.0.0.1 - - [21/Oct/2026:10:%02d:%02d +0000] "GET %s HTTP/1.1" 200 128 "-" "%s"'%(i%60,i%60,url,agent))
p.joinpath('nginx.log').write_text('\n'.join(rows)+'\n')
server=[]
for i in range(180):
 if i < 44:
  server.append('container.web Running service 24h')
 else:
  server.append(random.choice(['container.web Running service 12h','container.web Stopped service 24h','container.api Running service 24h','container.web Idle service 24h']))
p.joinpath('server.log').write_text('\n'.join(server)+'\n')
PY
 ;;
20)
 useradd -m -s /bin/bash jackie 2>/dev/null || true
 usermod -aG operators jackie
 echo 'jackie:brown' | chpasswd
 echo 'ulimit -S -u 1024' >>/home/jackie/.bashrc
 ;;
esac
