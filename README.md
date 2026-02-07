# Коротка оповідь про тестове (-_-)

## TL;DR

```
1.1/ → Bash хардення Ubuntu (UFW, SSH, fail2ban)
1.2/ → Моніторинг (Node Exporter)
2.1/ → Бекапи PostgreSQL (bash + Ansible, шифрування, S3/FTP/SSH)
3/   → Terraform (VPC + EC2 + S3 + IAM)
4/   → План реагування на інциденти (SSH brute-force + DB проблеми)
```

---

## 1.1 - Hardening Script

**Що робить:** Bash скрипт який загартовує Ubuntu :)

**Навіщо:** Щоб не лазити руками по кожному серверу і не забути якийсь крок.

---

## 1.2 - Monitoring

**Що:** Node Exporter на порту 9100 + конфіги для Prometheus.

**Навіщо:** Бачити що відбувається з сервером до того як все впаде. CPU/memory/disk - стандартні метрики.

---

## 2.1 - Backup System

**Що:**
- `db_backup.sh` - дампить PostgreSQL, шифрує (GPG/OpenSSL), заливає в S3/FTP/SSH, прибирає старе
- Ansible роль - деплоїть це на купу серверів, налаштовує cron, credentials, перевіряє що працює

**Навіщо:** 
- Автоматизація щоденних бекапів
- Шифрування щоб не зливати дані
- Ansible щоб не настроювати кожен сервер окремо
- Ротація щоб диск не забився

**Флоу:**
```
Ansible плейбук → ставить пакети → кидає credentials → деплоїть скрипт → cron о 2 ночі → профіт
```

**Чому PostgreSQL only:** Спочатку була задумка для всіх БД, потім залишили тільки PostgreSQL бо він основний.

**Чому 3 типи storage:** Різні ситуації - хтось на AWS, хтось на власному FTP, хтось через SSH копіює.

---

## 3 - Terraform Infrastructure

**Що:**
```
VPC → Public/Private Subnets → EC2 (Ubuntu) → S3 bucket для бекапів
```

**Деталі:**
- Security Groups: SSH тільки з whitelist, PostgreSQL тільки з VPC
- IAM роль замість access keys (безпечніше)
- S3: encryption, versioning, lifecycle (30 днів)
- Все через змінні, ніякого хардкоду

**Навіщо модуль:** Щоб можна було переюзати для dev/staging/prod з різними variables.

**Чому Ubuntu 22.04:** LTS, 5 років підтримки, всі звикли.

**Чому IAM роль:** Access keys в конфігах - це зло, роль безпечніше.

---

## 4 - Incident Response

**Що:** Покроковий план коли щось горить (SSH brute-force атака + база тупить).

**Етапи:**
1. **Ізоляція** - дивлюсь хто підключений, блокую атаку, чекаю ресурси
2. **Діагностика** - копаю логи, дивлюсь на базу, мережу, файлову систему
3. **Фікс** - баню IP, оптимізую базу, кілю підозрілі процеси

**Інструменти:** ss, top, journalctl, fail2ban, iotop, tcpdump - стандартний набір для діагностики.

**Prevention:** SSH hardening, fail2ban з жорсткими правилами, firewall rate limiting, моніторинг.

**Data breach check:** Аудит бази, аналіз трафіку, історія команд, пошук дампів, сканування на rootkit.


---

## Tech Stack

- **OS:** Ubuntu 22.04 LTS (бо stable і всі знають)
- **DB:** PostgreSQL (вимога)
- **IaC:** Terraform (індустрія стандарт)
- **Config:** Ansible (agentless, простий)
- **Scripts:** Bash (воно всюди є)
- **Monitoring:** Prometheus + Node Exporter (де-факто стандарт)
- **Backup:** pg_dump (native для PG)
- **Encryption:** GPG/OpenSSL (перевірені часом)
- **Storage:** S3 (99.999999999% durability)

---

## Security Highlights

✅ SSH тільки по ключам  
✅ Fail2ban  
✅ Firewall whitelist  
✅ Encrypted бекапи  
✅ Encrypted storage (EBS + S3)  
✅ IAM roles (не access keys)  
✅ Proper permissions на credentials (600)  
✅ .gitignore для секретів  

---

## Quick Start

```bash
# Hardening
cd 1.1/ && sudo bash hardening.sh

# Backup через Ansible
cd 2.1/ansible/
cp group_vars/postgresql_example.yml group_vars/prod.yml
#Edit prod.yml
ansible-playbook -i inventory.ini deploy_backup.yml

# Infrastructure
cd 3/
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars
terraform init && terraform plan && terraform apply
```

**Загалом:** Все працює, все автоматизовано, все безпечно. Можна деплоїти і забути (ну майже).

by @mak_sim_kin
