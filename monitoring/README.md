# Prometheus + Grafana monitoring (native install, Ubuntu/Debian)

Installs everything with `apt`, running as systemd services. No Docker. Monitors:

- **the VM itself** (CPU, RAM, disk, network) using node-exporter
- **llama.cpp `llama-server`** (GLM-5.3, see [../llamaCppInstr.md](../llamaCppInstr.md))
- **vLLM** on another server

| Service       | apt package                 | systemd unit               | Port |
|---------------|-----------------------------|----------------------------|------|
| Prometheus    | `prometheus`                | `prometheus`               | 9090 |
| node-exporter | `prometheus-node-exporter`  | `prometheus-node-exporter` | 9100 |
| Grafana       | `grafana` (Grafana apt repo)| `grafana-server`           | 3000 |

```
monitoring/
├── prometheus/prometheus.yml                         -> /etc/prometheus/prometheus.yml
└── grafana/provisioning/datasources/prometheus.yml   -> /etc/grafana/provisioning/datasources/
```

## 1. Get the files

```bash
sudo apt-get update
sudo apt-get install -y git curl
git clone https://github.com/AboveTheClouds90/gitPublic.git
cd gitPublic/monitoring
```

## 2. Install Prometheus + node-exporter

```bash
sudo apt-get install -y prometheus prometheus-node-exporter
```

Both start automatically. Next, replace the default Prometheus config with the one from this repo.
First edit `prometheus/prometheus.yml` and set your targets (see step 4).

```bash
sudo cp /etc/prometheus/prometheus.yml /etc/prometheus/prometheus.yml.orig
sudo cp prometheus/prometheus.yml /etc/prometheus/prometheus.yml
promtool check config /etc/prometheus/prometheus.yml
sudo systemctl restart prometheus
```

Optional: keep 30 days of data (the default is 15). Edit `/etc/default/prometheus`:

```bash
ARGS="--storage.tsdb.retention.time=30d"
```

Then run `sudo systemctl restart prometheus`.

> Ubuntu's `prometheus` package is often a few versions behind upstream. That's fine
> for this setup. If you need the latest version, use the official binaries from
> https://prometheus.io/download/ instead.

## 3. Install Grafana (official apt repo)

```bash
sudo apt-get install -y apt-transport-https software-properties-common wget gpg
sudo mkdir -p /etc/apt/keyrings
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt-get update
sudo apt-get install -y grafana
```

Add Prometheus as a data source automatically, then start Grafana:

```bash
sudo cp grafana/provisioning/datasources/prometheus.yml /etc/grafana/provisioning/datasources/
sudo systemctl daemon-reload
sudo systemctl enable --now grafana-server
```

## 4. Turn on metrics in the model servers and set targets

**llama.cpp:** add `--metrics` to the `llama-server` command:

```bash
./llama.cpp/build/bin/llama-server \
  -m ~/models/GLM-5.3/UD-Q4_K_XL/GLM-5.3-UD-Q4_K_XL-00001-of-0000X.gguf \
  --alias glm-5.3 --metrics \
  -t 48 -c 32768 -b 2048 -ub 2048 \
  --no-mmap --jinja \
  --host 0.0.0.0 --port 8080
```

**vLLM:** `/metrics` is on by default on the API port.

Check both:

```bash
curl -s http://localhost:8080/metrics | head
curl -s http://<vllm-host>:8000/metrics | head
```

In `/etc/prometheus/prometheus.yml`:

- `llamacpp`: `localhost:8080` assumes llama-server runs on this VM. If not, use its IP.
- `vllm`: replace `<vllm-host>` with the vLLM server's IP or hostname.

After every config change:

```bash
promtool check config /etc/prometheus/prometheus.yml && sudo systemctl reload prometheus
```

## 5. Check it

```bash
systemctl status prometheus prometheus-node-exporter grafana-server --no-pager
```

Open `http://<vm-ip>:9090/targets`. All targets should show **UP**.

## 6. Grafana

1. Open `http://<vm-ip>:3000` and log in as `admin` / `admin`. **Change the password when
   it asks you to.** (Forgot it? `sudo grafana cli admin reset-admin-password <new-pw>`)
2. The Prometheus data source is already set up from step 3.
3. VM dashboard: **Dashboards → New → Import**, enter ID **`1860`** (Node Exporter Full)
   and select the Prometheus data source.
4. LLM panels: create a new dashboard and add panels with these queries:

| What                                 | Query                                          |
|--------------------------------------|------------------------------------------------|
| llama.cpp generation speed (tok/s)   | `llamacpp:predicted_tokens_seconds`            |
| llama.cpp prompt processing (tok/s)  | `llamacpp:prompt_tokens_seconds`               |
| llama.cpp requests in progress       | `llamacpp:requests_processing`                 |
| vLLM requests running / waiting      | `vllm:num_requests_running`, `vllm:num_requests_waiting` |
| vLLM generated tokens/s              | `rate(vllm:generation_tokens_total[1m])`       |
| vLLM time to first token (p95)       | `histogram_quantile(0.95, rate(vllm:time_to_first_token_seconds_bucket[5m]))` |

Metric names can change between versions. If a query is empty, look up the exact
name with `curl -s <server>/metrics | grep -v '^#'`.

vLLM also has ready-made Grafana dashboards in its repo, under `examples/`
(search for "grafana"). You can import those as JSON.

## Security

Prometheus (9090) and node-exporter (9100) have **no login**, and both listen on all
interfaces by default. Use a firewall:

```bash
sudo ufw allow OpenSSH
sudo ufw allow from <your-ip> to any port 3000 proto tcp   # Grafana, only from you
sudo ufw enable
```

With only those rules, 9090 and 9100 stay closed from outside. Grafana still reaches them
through `localhost`. To open the Prometheus UI, use an SSH tunnel:

```bash
ssh -L 9090:localhost:9090 user@<vm-ip>    # then open http://localhost:9090
```

If vLLM runs on another machine, its port 8000 must be reachable **from this VM**.
On the vLLM server, allow it from the VM's IP only.

## Useful commands

```bash
journalctl -u prometheus -f                 # Prometheus logs
journalctl -u grafana-server -f             # Grafana logs
sudo systemctl restart prometheus grafana-server prometheus-node-exporter
sudo apt-get update && sudo apt-get upgrade # updates all three
```

Config and data locations:

| What                  | Path                                |
|-----------------------|-------------------------------------|
| Prometheus config     | `/etc/prometheus/prometheus.yml`    |
| Prometheus flags      | `/etc/default/prometheus`           |
| Prometheus data       | `/var/lib/prometheus/metrics2/`     |
| node-exporter flags   | `/etc/default/prometheus-node-exporter` |
| Grafana config        | `/etc/grafana/grafana.ini`          |
| Grafana provisioning  | `/etc/grafana/provisioning/`        |
| Grafana data          | `/var/lib/grafana/`                 |
