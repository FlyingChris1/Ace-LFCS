#!/bin/bash
set -u
q="$1"
target_host=$(cat /etc/lfcs-task-host 2>/dev/null || hostname)
fail(){ echo "FAIL|$1"; exit 1; }
pass(){ echo "PASS|$1"; exit 0; }
case "$q" in
1)
 test "$(cat /opt/course/1/kernel 2>/dev/null)" = "$(uname -r)" || fail 'Kernel release file is wrong.'
 test "$(cat /opt/course/1/ip_forward 2>/dev/null)" = "$(cat /proc/sys/net/ipv4/ip_forward)" || fail 'ip_forward file is wrong.'
 timezone=$(cat /opt/course/1/timezone 2>/dev/null)
 timezone_name=$(timedatectl show -p Timezone --value)
 timezone_abbreviation=$(date +%Z)
 test "$timezone" = "$timezone_name" || test "$timezone" = "$timezone_abbreviation" || fail 'Timezone file is wrong.'
 pass 'All three system values match.' ;;
2)
 jobs=$(crontab -u asset-manager -l 2>/dev/null) || fail 'asset-manager has no crontab.'
 grep -Eq '^30 20 \* \* \* bash /home/asset-manager/generate\.sh$' <<<"$jobs" || fail 'The migrated 20:30 job is missing or runs as the wrong user.'
 grep -Eq '^15 11 \* \* (1,4|mon,thu) bash /home/asset-manager/clean\.sh$' <<<"$jobs" || fail 'The Monday/Thursday job is missing.'
 ! grep -Eq '^[[:space:]]*30[[:space:]]+20[[:space:]]+\*[[:space:]]+\*[[:space:]]+\*[[:space:]]+root[[:space:]]+bash /home/asset-manager/generate\.sh' /etc/crontab /etc/cron.d/* 2>/dev/null || fail 'The migrated job is still system-wide.'
 pass 'Both cron jobs are owned by asset-manager.' ;;
3)
 f=/etc/systemd/timesyncd.conf
 grep -Eq '^NTP=0\.pool\.ntp\.org[[:space:]]+1\.pool\.ntp\.org$' "$f" || fail 'Main NTP servers are wrong.'
 grep -Eq '^FallbackNTP=ntp\.ubuntu\.com[[:space:]]+0\.debian\.pool\.ntp\.org$' "$f" || fail 'Fallback NTP servers are wrong.'
 grep -Eq '^PollIntervalMaxSec=1000$' "$f" || fail 'Maximum polling interval is wrong.'
 grep -Eq '^ConnectionRetrySec=20$' "$f" || fail 'Connection retry interval is wrong.'
 pass 'All timesyncd settings match.' ;;
4)
 f=/opt/course/4/script.sh
 test -x "$f" || fail 'script.sh is missing or not executable.'
 bash -n "$f" || fail 'script.sh has a shell syntax error.'
 grep -Eq '(^|[[:space:]])VARIABLE2=["\x27]?v2' "$f" || fail 'VARIABLE2 is not set locally to v2.'
 grep -Eq 'export[[:space:]]+VARIABLE3=.*VARIABLE1.*extended' "$f" || fail 'VARIABLE3 is not exported from VARIABLE1.'
 cmp -s /home/candidate/.bashrc /opt/course/4/bashrc.baseline || fail 'The existing .bashrc was changed.'
 out=$(sudo -u candidate -H bash -lc 'bash /opt/course/4/script.sh' 2>&1) || fail 'script.sh did not run successfully.'
 test "$out" = $'v2\nrandom-string-extended' || fail 'script.sh output is incorrect.'
 pass 'The script output, variable scope, and unchanged .bashrc are correct.' ;;
5)
 test -s /imports/import001.tar.gz || fail 'gzip archive is missing.'
 gzip -t /imports/import001.tar.gz || fail 'gzip archive is corrupt.'
 tar -tjf /imports/import001.tar.bz2 | sort > /tmp/lfcs-source-list || fail 'Original archive cannot be read.'
 tar -tzf /imports/import001.tar.gz | sort > /tmp/lfcs-target-list || fail 'New archive cannot be read.'
 diff -q /tmp/lfcs-source-list /tmp/lfcs-target-list >/dev/null || fail 'The archive contents differ.'
 diff -q /tmp/lfcs-source-list /imports/import001.tar.bz2_list >/dev/null || fail 'The sorted source file list is wrong.'
 diff -q /tmp/lfcs-target-list /imports/import001.tar.gz_list >/dev/null || fail 'The sorted output file list is wrong.'
 pass 'Both archives and sorted file lists match.' ;;
6)
 id user1 >/dev/null 2>&1 || fail 'user1 is missing.'
 test "$(id -gn user1)" = dev || fail 'user1 primary group is not dev.'
 test "$(getent passwd user1 | cut -d: -f6)" = /home/accounts/user1 || fail 'user1 home is wrong.'
 test -d /home/accounts/user1 || fail 'user1 home directory does not exist.'
 id user2 >/dev/null 2>&1 || fail 'user2 is missing.'
 test "$(getent passwd user2 | cut -d: -f6)" = /home/accounts/user2 || fail 'user2 home is wrong.'
 test -d /home/accounts/user2 || fail 'user2 home directory does not exist.'
 test "$(getent passwd user2 | cut -d: -f7)" = /bin/bash || fail 'user2 shell is not bash.'
 id -nG user2 | tr ' ' '\n' | grep -qx dev || fail 'user2 is not in dev.'
 id -nG user2 | tr ' ' '\n' | grep -qx op || fail 'user2 is not in op.'
 sudo -l -U user2 2>/dev/null | grep -Eiq 'NOPASSWD:.*(bash|/root/dangerous\.sh)' || fail 'user2 cannot run the requested command without a password.'
 pass 'Users, groups, home directories, shell, and sudo access match.' ;;
7)
 if [ "$target_host" = data-002 ]; then
   iptables -C INPUT -i eth0 -p tcp --dport 5000 -j DROP 2>/dev/null || fail 'TCP port 5000 is not blocked on eth0.'
   iptables -t nat -C PREROUTING -i eth0 -p tcp --dport 6000 -j REDIRECT --to-ports 6001 2>/dev/null || fail 'TCP port 6000 is not redirected to 6001.'
   iptables -C INPUT -i eth0 -p tcp -s 192.168.10.80 --dport 6002 -j ACCEPT 2>/dev/null || fail 'The permitted source rule for port 6002 is missing.'
   iptables -C INPUT -i eth0 -p tcp --dport 6002 -j DROP 2>/dev/null || fail 'Port 6002 is not blocked for other sources.'
   iptables -C OUTPUT -d 192.168.10.70 -j DROP 2>/dev/null || iptables -C OUTPUT -d 192.168.10.70 -p tcp -j DROP 2>/dev/null || fail 'Outbound traffic to 192.168.10.70 is not blocked.'
   ! curl -fsS --max-time 2 http://192.168.10.70:7070/ >/dev/null 2>&1 || fail 'Outbound traffic to app-srv1 is still reachable.'
 elif [ "$target_host" = data-001 ]; then
   test "$(curl -fsS --max-time 2 http://192.168.10.90:6000/)" = 'listener 6001' || fail 'Port 6000 does not reach the local 6001 service.'
   test "$(curl -fsS --max-time 2 http://192.168.10.90:6002/)" = 'listener 6002' || fail 'The permitted data-001 source cannot reach port 6002.'
   ! curl -fsS --max-time 2 http://192.168.10.90:5000/ >/dev/null 2>&1 || fail 'Port 5000 is still reachable.'
 elif [ "$target_host" = app-srv1 ]; then
   ! curl -fsS --max-time 2 http://192.168.10.90:6002/ >/dev/null 2>&1 || fail 'Port 6002 accepts a non-permitted source.'
 else fail 'Unknown network test host.'; fi
 pass 'Firewall rules and source/destination network behavior are correct.' ;;
8)
 mountpoint -q /mnt/backup-black || fail 'The backup filesystem is not mounted.'
 test "$(blkid -o value -s TYPE /dev/vdb 2>/dev/null)" = ext4 || fail '/dev/vdb is not formatted ext4.'
 test "$(readlink -f "$(findmnt -nro SOURCE -T /mnt/backup-black)")" = "$(readlink -f /dev/vdb)" || fail '/dev/vdb is not mounted at /mnt/backup-black.'
 test -f /mnt/backup-black/completed || fail 'The completed file is missing.'
 test -d /mnt/backup001/.trash || fail 'Higher-use disk fixture is missing.'
 test -z "$(find /mnt/backup001/.trash -mindepth 1 -print -quit)" || fail 'The .trash folder on /dev/vdc is not empty.'
 mapfile -t app_mounts </etc/lfcs-q8-layout
 app_v1=${app_mounts[0]:-}; app_v2=${app_mounts[1]:-}
 test -n "$app_v1" && test -n "$app_v2" || fail 'The process filesystem fixture is missing.'
 ! pgrep -x dark-matter-v2 >/dev/null || fail 'The higher-memory dark-matter-v2 process is still running.'
 ! mountpoint -q "$app_v2" || fail 'The filesystem holding dark-matter-v2 is still mounted.'
 mountpoint -q "$app_v1" || fail 'The filesystem holding dark-matter-v1 should remain mounted.'
 pgrep -x dark-matter-v1 >/dev/null || fail 'dark-matter-v1 should remain running.'
 pass 'Disk format, mount, cleanup, and process filesystem state are correct.' ;;
9)
 test ! -e /var/backup/backup-015/old || fail 'The pre-2020 file remains.'
 test -e /var/backup/backup-015/small/smallfile || fail 'The small file was not moved.'
 test -e /var/backup/backup-015/large/largefile || fail 'The large file was not moved.'
 test -e /var/backup/backup-015/compromised/openfile || fail 'The permission-777 file was not moved.'
 test ! -e /var/backup/backup-015/small/largefile && test ! -e /var/backup/backup-015/large/smallfile || fail 'Files were sorted into incorrect directories.'
 pass 'Files were removed or moved to the requested directories.' ;;
10)
 if [ "$target_host" = terminal ]; then
   findmnt -rn -T /app-srv1/data-export | grep -q 'fuse\.sshfs' || fail 'The SSHFS mount is missing.'
   findmnt -rn -T /app-srv1/data-export | grep -Eq '(192\.168\.10\.70|app-srv1):/data-export' || fail 'SSHFS is mounted from the wrong host or directory.'
   findmnt -rn -T /app-srv1/data-export | grep -q 'rw' || fail 'The SSHFS mount is not read-write.'
   findmnt -rn -T /app-srv1/data-export | grep -q 'allow_other' || fail 'SSHFS does not enable allow_other.'
   printf 'grader write check\n' >/app-srv1/data-export/.lfcs-write-check 2>/dev/null || fail 'The SSHFS mount cannot write to the remote export.'
   grep -Eq '^/nfs/share[[:space:]]+192\.168\.10\.0/24\([^)]*ro' /etc/exports || fail 'The read-only NFS export for 192.168.10.0/24 is missing.'
   exportfs -v 2>/dev/null | grep -A1 '/nfs/share' | grep -q 'ro' || fail 'NFS is not currently exported read-only.'
 else
   findmnt -rn -T /nfs/terminal/share | grep -q 'nfs' || fail 'The NFS mount is missing.'
   findmnt -rn -T /nfs/terminal/share | grep -Eq '(192\.168\.10\.10|terminal):/nfs/share' || fail 'NFS is mounted from the wrong server or directory.'
   findmnt -rn -T /nfs/terminal/share | grep -q 'ro' || fail 'The NFS mount is not read-only.'
   test -s /data-export/.lfcs-write-check || fail 'The SSHFS write did not reach app-srv1.'
 fi
 pass 'SSHFS and read-only NFS mounts are correct.' ;;
11)
 test "$(docker inspect -f '{{.State.Status}}' frontend_v1 2>/dev/null)" = exited || fail 'frontend_v1 is not stopped.'
 docker inspect frontend_v2 >/dev/null 2>&1 || fail 'frontend_v2 is missing.'
 expected_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' frontend_v2)
 test "$(tr -d '\r\n' </opt/course/11/ip-address 2>/dev/null)" = "$expected_ip" || fail 'frontend_v2 IP file does not match Docker.'
 expected_mount=$(docker inspect -f '{{(index .Mounts 0).Destination}}' frontend_v2)
 test "$(docker inspect -f '{{len .Mounts}}' frontend_v2)" = 1 || fail 'frontend_v2 should have exactly one mount.'
 test "$(tr -d '\r\n' </opt/course/11/mount-destination 2>/dev/null)" = "$expected_mount" || fail 'frontend_v2 mount destination file is wrong.'
 test "$(docker inspect -f '{{.Config.Image}}' frontend_v3 2>/dev/null)" = 'nginx:alpine' || fail 'frontend_v3 image is wrong or container missing.'
 test "$(docker inspect -f '{{.State.Running}}' frontend_v3 2>/dev/null)" = true || fail 'frontend_v3 is not running detached.'
 test "$(docker inspect -f '{{.HostConfig.Memory}}' frontend_v3)" = 31457280 || fail 'frontend_v3 memory limit is not 30 MiB.'
 docker port frontend_v3 80/tcp 2>/dev/null | grep -q ':1234$' || fail 'frontend_v3 does not map host port 1234 to container port 80.'
 pass 'Container state, inspection files, image, memory, and port mapping are correct.' ;;
12)
 d=/home/candidate/repositories/auto-verifier
 test -d "$d/.git" || fail 'Repository was not cloned to the requested path.'
 test "$(git -C "$d" branch --show-current)" = main || fail 'The final branch is not main.'
 found=0
 for b in dev4 dev5 dev6; do if git -C "$d" show "$b:config.yaml" 2>/dev/null | grep -qx 'user_registration_level: open'; then found=$b; fi; done
 test "$found" != 0 || fail 'No supplied dev branch contains the open registration setting.'
 grep -qx 'user_registration_level: open' "$d/config.yaml" || fail 'The qualifying branch was not merged into main.'
 git -C "$d" merge-base --is-ancestor "$found" main || fail 'The qualifying branch is not merged into main.'
 test -e "$d/logs/.keep" || fail 'logs/.keep is missing.'
 test "$(git -C "$d" log -1 --pretty=%s)" = 'added log directory' || fail 'The commit message is wrong.'
 pass 'The qualifying branch is merged and the log directory is committed.' ;;
13)
 ! pgrep -x collector2 >/dev/null || fail 'collector2 is still running.'
 test ! -e /bin/collector2 || fail 'collector2 executable remains.'
 pgrep -x collector1 >/dev/null && pgrep -x collector3 >/dev/null || fail 'collector1 and collector3 should keep running.'
 test -x /bin/collector1 && test -x /bin/collector3 || fail 'A nonmatching collector executable was removed.'
 pass 'Only the process using the forbidden syscall was stopped and removed.' ;;
14)
 test "$(wc -l </var/output-generator/1.out 2>/dev/null | xargs)" = 20342 || fail 'stdout capture must contain 20342 lines.'
 test "$(wc -l </var/output-generator/2.out 2>/dev/null | xargs)" = 12336 || fail 'stderr capture must contain 12336 lines.'
 test "$(wc -l </var/output-generator/3.out 2>/dev/null | xargs)" = 32678 || fail 'Combined capture must contain 32678 lines.'
 cmp -s /var/output-generator/3.out <(cat /var/output-generator/1.out /var/output-generator/2.out) || fail 'Combined output does not contain both streams in order.'
 test "$(cat /var/output-generator/4.out 2>/dev/null | xargs)" = 123 || fail 'Exit status capture must be 123.'
 pass 'All output captures and the exit status are correct.' ;;
15)
 test -x /usr/bin/links || fail 'links is not installed at /usr/bin/links.'
 /usr/bin/links -version 2>&1 | grep -qi 'links' || fail 'Installed links binary does not run.'
 test -f /tools/links-2.14/config.log || fail 'Source was not configured and built in /tools/links-2.14.'
 grep -Eq -- '--prefix(=|[[:space:]])/usr' /tools/links-2.14/config.status || fail 'Build prefix is not /usr.'
 grep -Eq -- '--(disable-ipv6|without-ipv6)' /tools/links-2.14/config.status || fail 'IPv6 was not disabled during configuration.'
 pass 'links 2.14 is installed from the supplied source with IPv6 disabled.' ;;
16)
 nginx -t >/dev/null 2>&1 || fail 'Nginx configuration is invalid.'
 test "$(curl -fsS --max-time 3 http://192.168.10.60:1111/ 2>/dev/null)" = 'app1' || fail 'The original app1 backend on port 1111 is not intact.'
 test "$(curl -fsS --max-time 3 http://192.168.10.60:2222/ 2>/dev/null)" = 'app2' || fail 'The original app2 backend on port 2222 is not intact.'
 test "$(curl -fsS --max-time 3 http://192.168.10.60:2222/special 2>/dev/null)" = 'app2 special' || fail 'The original app2 /special endpoint is not intact.'
 test "$(curl -fsS --max-time 3 http://127.0.0.1:8001/anything 2>/dev/null)" = 'app2 special' || fail 'Port 8001 does not proxy to the special app.'
 responses=''
 for i in $(seq 1 12); do responses+="$(curl -fsS --max-time 3 http://127.0.0.1:8000/ 2>/dev/null) "; done
 grep -qw app1 <<<"$responses" || fail 'Port 8000 never reaches app1.'
 grep -qw app2 <<<"$responses" || fail 'Port 8000 never reaches app2.'
 pass 'Port 8001 reaches the special app and port 8000 balances both backends.' ;;
17)
 sshd -t || fail 'OpenSSH configuration is invalid.'
 rootcfg=$(sshd -T -C user=root,host=localhost,addr=127.0.0.1 2>/dev/null) || fail 'Could not evaluate sshd config.'
 martacfg=$(sshd -T -C user=marta,host=localhost,addr=127.0.0.1 2>/dev/null) || fail 'Could not evaluate marta SSH config.'
 cillacfg=$(sshd -T -C user=cilla,host=localhost,addr=127.0.0.1 2>/dev/null) || fail 'Could not evaluate cilla SSH config.'
 grep -qx 'x11forwarding no' <<<"$rootcfg" || fail 'X11Forwarding is not disabled globally.'
 grep -qx 'passwordauthentication no' <<<"$rootcfg" || fail 'Password authentication is not disabled globally.'
 grep -qx 'passwordauthentication yes' <<<"$martacfg" || fail 'Marta cannot authenticate by password.'
 grep -qx 'passwordauthentication no' <<<"$cillacfg" || fail 'Password authentication remains enabled for cilla.'
 for cfg in "$martacfg" "$cillacfg"; do grep -qx 'banner /etc/ssh/sshd-banner' <<<"$cfg" || fail 'The banner is not enabled for both requested users.'; done
 pass 'Effective OpenSSH settings match for root, marta, and cilla.' ;;
18)
 vgs vol1 >/dev/null 2>&1 || fail 'vol1 is missing.'
 pvs --noheadings -o pv_name,vg_name | awk '$1=="/dev/vdh" && $2=="vol1"{found=1} END{exit found}' || fail '/dev/vdh is still in vol1.'
 device=$(readlink -f /dev/vdh)
 pvs --noheadings -o pv_name,vg_name | awk -v d="$device" '$1==d && $2=="vol1"{found=1} END{exit found}' || fail '/dev/vdh is still in vol1.'
 pvs --noheadings -o pv_name,vg_name | awk -v d="$device" '$1==d && $2=="vol2"{found=1} END{exit !found}' || fail '/dev/vdh is not in vol2.'
 test "$(lvs --noheadings -o lv_name vol2/p1 2>/dev/null | xargs)" = p1 || fail 'Logical volume p1 is missing.'
 test "$(blkid -o value -s TYPE /dev/vol2/p1 2>/dev/null)" = ext4 || fail 'p1 is not formatted ext4.'
 pass 'VG membership, logical volume, and ext4 filesystem are correct.' ;;
19)
 d=/var/log-collector/003
 test -s "$d/nginx.log.extracted" || fail 'Extracted nginx log is missing.'
 grep -E '"(GET|POST|PUT|DELETE) /app/user[^ ]* HTTP/[^\"]+" .*"hacker-bot/1\.2"' "$d/nginx.log" > /tmp/lfcs-nginx-expected || fail 'Could not read source nginx log.'
 diff -q /tmp/lfcs-nginx-expected "$d/nginx.log.extracted" >/dev/null || fail 'Extracted nginx lines do not exactly match the request.'
 sed -E 's/^container\.web.*Running.*24h$/SENSITIVE LINE REMOVED/' "$d/server.log" > /tmp/lfcs-server-expected
 diff -q /tmp/lfcs-server-expected "$d/server.log" >/dev/null || fail 'server.log redactions are incomplete or incorrect.'
 pass 'Both log transformations match the requested patterns exactly.' ;;
20)
 grep -Eq '^[[:space:]]*jackie[[:space:]]+hard[[:space:]]+nproc[[:space:]]+1024([[:space:]]|$)' /etc/security/limits.conf /etc/security/limits.d/*.conf 2>/dev/null || fail 'Jackie hard nproc limit is not configured as 1024.'
 grep -Eq '^[[:space:]]*@operators[[:space:]]+hard[[:space:]]+maxlogins[[:space:]]+1([[:space:]]|$)' /etc/security/limits.conf /etc/security/limits.d/*.conf 2>/dev/null || fail 'operators maxlogins is not set to 1.'
 ! grep -Eq '^[[:space:]]*ulimit[[:space:]]+-S[[:space:]]+-u' /home/jackie/.bashrc || fail 'The temporary .bashrc workaround remains.'
 pass 'Hard process and group login limits are configured.' ;;
*) fail 'Unknown exercise.' ;;
esac
