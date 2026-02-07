

```bash
wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar xvfz node_exporter-1.7.0.linux-amd64.tar.gz
sudo cp node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
```


Скопіювати конфіг `configs/node_exporter.service` в `/etc/systemd/system/`:

```bash
sudo cp configs/node_exporter.service /etc/systemd/system/
```


```bash
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter
```

Node Exporter запуститься на порту `9100`.


Використати готовий конфіг `configs/prometheus.yml` або додати job до існуючого:

```bash
# 1: Використати готовий конфіг
sudo cp configs/prometheus.yml /etc/prometheus/prometheus.yml

# 2: Додати job вручну до існуючого конфігу
# Відкрити /etc/prometheus/prometheus.yml і додати секцію scrape_configs
```

```bash
sudo systemctl restart prometheus
```


## Альтернатива: Netdata (якщо потрібен веб-інтерфейс)

```bash
bash <(curl -Ss https://my-netdata.io/kickstart.sh)
```

- Збирає всі метрики CPU, RAM, Disk I/O
- Моніторить `/var/lib/mysql` та `/var/lib/postgresql`
- Надає веб-інтерфейс на порту 19999
- Експортує метрики для Prometheus на `/api/v1/allmetrics?format=prometheus`

Розкоментить секцію Netdata в `configs/prometheus.yml` або додати до існуючого конфігу вручну.

