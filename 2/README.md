# Система резервного копіювання PostgreSQL

Автоматичний daily-backup PostgreSQL з шифруванням та віддаленим зберіганням.

## Швидкий старт через bash скриипт

```bash
# 1. Налаштувати
cp config.env.example config.env
nano config.env

# 2. Запустити
chmod +x db_backup.sh
./db_backup.sh

# 3. Автоматизувати
crontab -e
# Додати: 0 2 * * * /path/to/db_backup.sh
```

## Швидкий старт (Ansible)

```bash
cd ansible/
cp group_vars/postgresql_example.yml group_vars/all.yml
nano group_vars/all.yml
ansible-playbook -i inventory.ini deploy_backup.yml
```

---

## Конфігурація (config.env)

```bash
# База даних
DB_HOST="localhost"
DB_PORT="5432"
DB_NAME="mydatabase"
DB_USER="backup_user"
DB_PASSWORD="secure_password"

# Локальне зберігання
LOCAL_BACKUP_PATH="/var/backups/databases"

# Шифрування GPG
ENABLE_ENCRYPTION="true"
ENCRYPTION_PASSWORD="strong_password"

# Віддалене сховище (local/s3/ftp/ssh)
STORAGE_TYPE="local"

# Ротація (днів)
RETENTION_DAYS="7"
```

### S3
```bash
STORAGE_TYPE="s3"
S3_BUCKET="my-bucket"
S3_REGION="us-east-1"
```

### SSH
```bash
STORAGE_TYPE="ssh"
SSH_HOST="backup-server.com"
SSH_USER="backup"
SSH_PATH="/backups"
```

---

## Що робить скрипт

1. **Backup** - `pg_dump` PostgreSQL БД
2. **Encryption** - шифрування GPG/OpenSSL
3. **Upload** - завантаження на S3/FTP/SSH
4. **Rotation** - видалення старих бекапів (>7 днів)
5. **Logging** - логи в `logs/backup_*.log`

---

## Ansible розгортання

**Inventory** (`inventory.ini`):
```ini
[db_servers]
prod-db1.maskimtech.com ansible_user=ubuntu
```

**Змінні** (`group_vars/all.yml`):
```yaml
db_host: localhost
db_port: 5432
db_name: mydatabase
db_user: backup_user
db_password: !vault | encrypted

storage_type: s3
s3_bucket: prod-backups
backup_schedule: "0 2 * * *"
retention_days: 7
```

**Розгортання**:
```bash
ansible-playbook -i inventory.ini deploy_backup.yml --ask-vault-pass
```

**Що встановлює**:
- PostgreSQL client
- Скрипт в `/opt/db_backup/`
- Cron job для щоденного бекапу
- Credentials (`.pgpass`)
- SSH ключі (якщо storage_type=ssh)

---

## Відновлення

```bash
# Розшифрувати
gpg --decrypt backup.sql.gpg > backup.sql

# Відновити
psql -U postgres -d database_name -f backup.sql
```

---

## Безпека

```sql
-- PostgreSQL: користувач тільки для бекапу
CREATE USER backup_user WITH PASSWORD 'password';
GRANT CONNECT ON DATABASE database_name TO backup_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO backup_user;
```

```bash
chmod 600 config.env  # Захист паролів
```

---

## Troubleshooting

```bash
# Перевірити останній лог
tail -50 logs/backup_*.log

# Список бекапів
ls -lh /var/backups/databases/postgresql/

# Тестовий запуск
./db_backup.sh

# Ansible: перевірити на всіх серверах
ansible -i inventory.ini db_servers -a "ls -lh /var/backups/databases/"
```
