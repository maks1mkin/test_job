# Incident Response Plan: SSH Brute Force Attack + Performance Degradation


## 1. Покроковий план реагування

### Етап 1: Ізоляція та оцінка (перші 5-10 хвилин)

**1.1 Для початку я б негайно перевірив активні SSH з'єднання**
```bash

ss -tunap | grep :22
netstat -tnpa | grep :22 | grep ESTABLISHED

# глянув би список юзерів підключених 
who
w -i
last -a | head -20
```

**1.2 Блокування атаки (якщо атака активна)**
Тут важливо швидко прикрити дірку, поки вони не нароблять більше лиха. Я б спочатку глянув який firewall взагалі стоїть і що там налаштовано
```bash
# тимчасово обмежую  SSH тільки до whitelist IP (через firewall)
ufw status
iptables -L INPUT -n -v | grep 22

# додати rate limiting (якщо ще не налаштовано)
iptables -I INPUT -p tcp --dport 22 -i eth0 -m state --state NEW -m recent --set
iptables -I INPUT -p tcp --dport 22 -i eth0 -m state --state NEW -m recent --update --seconds 60 --hitcount 4 -j DROP

# АБО ж тимчасово змінити порт SSH
sed -i 's/^#Port 22/Port 2222/' /etc/ssh/sshd_config
systemctl restart sshd
```

**1.3 Оцінка системних ресурсів**

Тепер треба зрозуміти наскільки все погано. Дивлюсь що взагалі відбувається з системою - чи це тільки SSH пострадав, чи вся машина вмирає

```bash
# CPU і процеси дивимось на наявніть запущенних процесів через можливий бекдор в ssh
top -b -n 1 | head -20
htop
ps aux --sort=-%cpu | head -20
ps aux | grep sshd | wc -l

# Load average
uptime
cat /proc/loadavg

# Memory
free -h
vmstat 1 5

# Disk  
iotop -o -b -n 3
iostat -x 2 5
```

---

### Етап 2: Діагностика та збір доказів для подальшого розуміння масштабу нанесеного інцидентом

На цьому етапі я вважаю важлииво зібрати найбльше інформації для розуміння масштабу проблеми

**2.1 Аналіз SSH логів**

Окей, тепер починається детективна робота. Треба витягти всі логи і зрозуміти хто, звідки і коли нас атакував. Особливо цікаві успішні логіни - якщо такі є, то все погано

```bash
# Failed login attempts
journalctl -u sshd | grep "Failed password" | tail -100
grep "Failed password" /var/log/auth.log | awk '{print $11}' | sort | uniq -c | sort -rn | head -20

# Успішні входи дивимось
grep "Accepted password" /var/log/auth.log | tail -50
journalctl -u sshd | grep "Accepted publickey" | tail -50

# айпішки атакуючих
grep "Failed password" /var/log/auth.log | awk '{print $11}' | sort | uniq -c | sort -rn > /tmp/ssh_attack_ips.txt

# Перевірка fail2ban статусу
fail2ban-client status sshd
fail2ban-client get sshd stats
```

**2.2 Перевірка системних логів**

Перевіряю чи система не крашилась від навантаження, чи ядро не вбивало процеси через OOM. Буває що атака настільки масивна що kernel починає паникувати

```bash
# Системні повідомлення
dmesg -T | tail -100
journalctl -p err -b

# Kernel messages
dmesg | grep -i "kill\|oom\|error"

# Audit logs (якщо встановлено auditd)
ausearch -m USER_LOGIN -sv no
aureport --failed --summary
```

**2.3 Діагностика БД**

База теж страждає - треба зрозуміти чи це через загальне навантаження системи, чи хтось дійсно ломився в базу. Дивлюсь на активні конекшени і повільні запити

```bash
# PostgreSQL slow queries
tail -100 /var/log/postgresql/postgresql-*-main.log | grep "duration:"

# Активні з'єднання з базой
sudo -u postgres psql -c "SELECT count(*) FROM pg_stat_activity;"
sudo -u postgres psql -c "SELECT pid, usename, application_name, client_addr, state, query_start FROM pg_stat_activity WHERE state = 'active';"

# Slow queries
sudo -u postgres psql -c "SELECT pid, now() - query_start AS duration, query FROM pg_stat_activity WHERE state = 'active' AND now() - query_start > interval '5 seconds' ORDER BY duration DESC;"

# Lock monitoring
sudo -u postgres psql -c "SELECT * FROM pg_locks WHERE NOT granted;"

# Database load
sudo -u postgres psql -c "SELECT * FROM pg_stat_database WHERE datname = 'your_database';"
```

**2.4 Мережева активність**

Перелічую всі підозрілі з'єднання. Якщо бачу якісь дивні outbound connection на невідомі IP - це вже реально тривожний дзвіночок про можливий backdoor

```bash
# Встановлені з'єднання
ss -s
netstat -an | grep ESTABLISHED | wc -l

# Top IP addresses
netstat -ntu | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -20

# Bandwidth per connection
iftop -n -P
nethogs

# DNS запити (можлива ознака зараження)
tcpdump -i any -n port 53 -c 100
```

**2.5 Перевірка файлової системи**

Шукаю сліди взлому. Якщо вони встигли зайти - могли накидати своїх скриптів, додати крони або навіть поставити rootkit. Особливо уважно дивлюсь на SUID файли - класичний вектор атаки

```bash
# Нещодавно змінені файли
find /etc /root /home -type f -mtime -1 -ls
find /tmp /var/tmp -type f -mtime -1 -ls

# SUID файли (можливі бекдори)
find / -perm -4000 -type f -ls 2>/dev/null

# Перевірка crontab
crontab -l
ls -la /etc/cron.*
cat /etc/crontab

# Systemd timers
systemctl list-timers --all

# Процеси без parent
ps -elf | awk '$5 == 1 && $4 != 1 {print}'
```

---

### Етап 3: Митігація та відновлення 

Ну відповідно після виявлення, перша дія - блокування атаки і латання дірок які текли від цих пострілів :)

**3.1 Блокування атакуючих IP**

Беру список всіх айпішників з логів і просто банлю їх нафіг. Якщо fail2ban не справився - руками через iptables додаю. Краще перестрахуватись

```bash
# Додати IP до fail2ban
while read ip count; do
  fail2ban-client set sshd banip $ip
done < /tmp/ssh_attack_ips.txt

# АБО через iptables
awk '$1 > 10 {print $2}' /tmp/ssh_attack_ips.txt | while read ip; do
  iptables -A INPUT -s $ip -j DROP
done
iptables-save > /etc/iptables/rules.v4
```

**3.2 Оптимізація БД (якщо slow queries)**

Базі треба допомогти прийти до тями. Вбиваю всі запити що висять довше 10 хвилин - вони все одно вже не варті того щоб чекати. Потім vacuum щоб почистити мертві рядки

```bash
# Kill довгі запити
sudo -u postgres psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'active' AND now() - query_start > interval '10 minutes';"

# Vacuum та analyze
sudo -u postgres psql -d your_database -c "VACUUM ANALYZE;"

# Перезапуск БД (у крайньому випадку, якшо прям дуже багато аномалій)
systemctl restart postgresql
```

**3.3 Зменшення навантаження**

Якщо бачу підозрілого юзера з купою процесів - без розмов киляю все що від нього. Потім рестартую SSH вже з жорсткішими лімітами. Краще пару легальних юзерів почекають ніж сервер впаде

```bash
# Kill зайві SSH процеси (обережно робимо!)
pkill -KILL -u suspicious_user

# Restart SSH з обмеженням
echo "MaxStartups 3:50:10" >> /etc/ssh/sshd_config
echo "MaxSessions 3" >> /etc/ssh/sshd_config
systemctl restart sshd
```

---

## 2. Основні команди діагностики  

| Категорія | Команди |
|-----------|---------|
| **Network** | `ss -tunap`, `netstat -tnpa`, `iftop`, `nethogs`, `tcpdump` |
| **CPU/Memory** | `top`, `htop`, `ps aux --sort=-%cpu`, `free -h`, `vmstat` |
| **Disk I/O** | `iotop`, `iostat -x`, `df -h`, `lsof` |
| **Logs** | `journalctl -u sshd`, `grep "Failed" /var/log/auth.log`, `dmesg -T` |
| **Firewall** | `fail2ban-client status`, `iptables -L -n -v`, `ufw status` |
| **Database** | `pg_stat_activity`, `pg_locks`, slow query log |
| **Security** | `last`, `who`, `w`, `ausearch`, `find` для SUID |

---

## 3. Заходи захисту (щоб більше не повторювалось)

### 3.1 SSH Hardening

Ось тут я налаштовую SSH як треба з самого початку, якшо той був змінений під час атаки.

```bash
# /etc/ssh/sshd_config
PermitRootLogin no
PasswordAuthentication no          # Тільки SSH keys
PubkeyAuthentication yes
MaxAuthTries 3
MaxSessions 3
MaxStartups 3:50:10
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
Port 7676                          # Нестандартний порт
AllowUsers deploy admin            # Whitelist користувачів

# Restart SSH
systemctl restart sshd
```

### 3.2 Fail2Ban налаштування

Налаштовую fail2ban щоб він автоматично банив тих хто намагається брутфорсити. 3 спроби і ти в бані на годину - цілком справедливо

```bash
# /etc/fail2ban/jail.local
[sshd]
enabled = true
port = 2222
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
findtime = 600
bantime = 3600
action = iptables-multiport[name=sshd, port="2222", protocol=tcp]

systemctl restart fail2ban
```

### 3.3 Firewall rules

Ставлю нормальний firewall. За замовчуванням все блокуємо, відкриваємо тільки те що дійсно потрібно. SSH тільки з білого списку IP

```bash
# UFW
ufw default deny incoming
ufw default allow outgoing
ufw allow from <trusted_ip> to any port 2222
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable

# АБО iptables rate limiting
iptables -A INPUT -p tcp --dport 2222 -m conntrack --ctstate NEW -m recent --set
iptables -A INPUT -p tcp --dport 2222 -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 4 -j DROP
```

### 3.4 Моніторинг та алертинг

Щоб наступного разу не дізнатись про проблему коли вже все горить - налаштовую нормальний моніторинг з алертами в Slack/Telegram

```bash
# Налаштувати моніторинг:
# - CPU/Memory/Disk alerts
# - Failed SSH attempts > 50/min
# - Database slow queries > 5s
# - Connections spike

# Використати: Prometheus + Alertmanager, Grafana
```

### 3.5 Database optimization

Налаштовую базу щоб вона краще справлялась з навантаженням. Обмежую кількість з'єднань і логую повільні запити щоб бачити що гальмує

```bash
# PostgreSQL: /etc/postgresql/*/main/postgresql.conf
shared_buffers = 256MB
effective_cache_size = 1GB
max_connections = 100
work_mem = 4MB
maintenance_work_mem = 64MB
log_min_duration_statement = 1000  # Log queries > 1s

# Connection pooling
# Використати PgBouncer або Pgpool-II
```

### 3.6 OSSEC/AIDE для file integrity

Щоб бачити якщо хтось міняє системні файли - ставлю AIDE. Він робить checksum всіх важливих файлів і кричить якщо щось змінилось

```bash
# Встановити OSSEC або AIDE
apt-get install aide
aideinit
aide --check
```

---

## 4. Перевірка витоку даних (найстрашніше)

### 4.1 Перевірка доступу до БД

Тут треба дуже уважно подивитись чи не лізли в базу. Якщо бачу підключення не з localhost - вже підозріло. Дивлюсь що за запити виконувались і звідки

```bash
# PostgreSQL audit
sudo -u postgres psql -c "SELECT * FROM pg_stat_activity ORDER BY query_start;"
sudo -u postgres psql -c "SELECT * FROM pg_stat_statements ORDER BY calls DESC LIMIT 50;"

# Перевірити pg_hba.conf
cat /var/lib/postgresql/*/main/pg_hba.conf

# Перевірити успішні підключення ззовні
grep "connection authorized" /var/log/postgresql/postgresql-*-main.log | grep -v "127.0.0.1\|localhost"
```

### 4.2 Аналіз мережевого трафіку

Шукаю ознаки того що дані могли вивантажити. Дивлюсь на підозрілі outbound з'єднання, особливо на FTP/SMB порти або якісь рандомні IP

```bash
# Перевірити outbound з'єднання (можливий data exfiltration)
netstat -tnpa | grep ESTABLISHED | grep -v ":80\|:443\|:22"

# Capture трафік для аналізу
tcpdump -i any -w /tmp/traffic_capture.pcap -c 10000
tshark -r /tmp/traffic_capture.pcap -Y "ftp-data || smb || mysql"

# Перевірити DNS запити до підозрілих доменів
tcpdump -i any -n port 53 | grep -E "\.ru|\.cn|pastebin|temp|file"
```

### 4.3 Перевірка скомпрометованих облікових записів

Перевіряю чи не зайшли під чужими акаунтами. Дивлюсь історію команд - якщо бачу wget/curl з якихось пастбінів або base64 - це вже точно щось нехороше

```bash
# Успішні SSH логіни за останню добу
last -a | head -50
journalctl -u sshd --since "1 day ago" | grep "Accepted"

# Історія команд підозрілих користувачів
cat /home/*/.bash_history | grep -E "wget|curl|nc|base64|chmod|sudo"

# Sudo usage
journalctl -u sudo | grep -v "your_admin_user"
```

### 4.4 Перевірка backup logs

Дивлюсь чи хтось не робив дампи бази. Класична схема - зайшли, зробили pg_dump, викачали собі всю базу і пішли. Якщо знайду .sql файли в /tmp - все дуже погано

```bash
# Чи робились дампи БД підозрілими процесами
ps aux | grep pg_dump
grep "pg_dump\|mysqldump" /var/log/syslog

# Перевірити /tmp на дампи
find /tmp /var/tmp -type f -name "*.sql" -o -name "*.dump"
```

### 4.5 Перевірка файлових операцій

Якщо є auditd - це золото, можу побачити всі операції з файлами. Шукаю доступ до /etc/passwd, до директорій PostgreSQL і взагалі до всього що може містити дані

```bash
# Audit logs (якщо увімкнено auditd)
ausearch -f /etc/passwd
ausearch -f /var/lib/postgresql
ausearch -k database_access

# lsof для відкритих файлів БД
lsof | grep postgres | grep -E "\.sql|backup"
```

### 4.6 Перевірка на backdoors

Тепер найважливіше - чи не залишили вони собі backdoor для повернення. Шукаю підозрілі SUID файли, нові сервіси, netcat listeners. Прогоняю rkhunter на всяк випадок

```bash
# Нові SUID файли
find / -perm -4000 -type f -mtime -7 -ls 2>/dev/null

# Нові systemd services
systemctl list-unit-files --type=service --state=enabled | grep -v "@"

# Netcat listeners або reverse shells
netstat -tnlp | grep -v ":22\|:80\|:443\|:5432"
lsof -i -P -n | grep LISTEN

# Rootkits scan
rkhunter --check
chkrootkit
```

### 4.7 Звіт про інцидент

Коли все згасили і почистили - треба написати докладний звіт. Це важливо і для себе (щоб не забути що було) і для команди і для менеджменту (щоб вибити бюджет на нормальну безпеку гг)

Підготувати документ:
- Таймлайн подій (timestamps)
- Список скомпрометованих IP/accounts
- Перелік змінених файлів
- Виконані команди (з логів)
- Дані які потенційно могли бути викрадені
- Вжиті заходи
- Рекомендації

---
