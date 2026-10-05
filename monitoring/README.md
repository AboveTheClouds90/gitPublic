# Prometheus + Grafana monitoring (native install, Ubuntu/Debian)

Installs everything with `apt`, running as systemd services. No Docker, no git clone:
**every step is a block you paste into the VM's terminal.** Monitors:

- **the VM itself** (CPU, RAM, disk, network) using node-exporter
- **one or more llama.cpp `llama-server`s** (e.g. GLM-5.3, see [../llamaCppInstr.md](../llamaCppInstr.md))
- **one or more vLLM servers**

| Service       | apt package                 | systemd unit               | Port |
|---------------|-----------------------------|----------------------------|------|
| Prometheus    | `prometheus`                | `prometheus`               | 9090 |
| node-exporter | `prometheus-node-exporter`  | `prometheus-node-exporter` | 9100 |
| Grafana       | `grafana` (Grafana apt repo)| `grafana-server`           | 3000 |

> **How to paste a file:** the blocks below that start with `sudo tee ... <<'EOF'` write a
> whole file in one go. Paste the entire block, from the first line through `EOF`.
> Prefer nano? Run `sudo nano <path>`, paste only the file contents (the part between the
> `tee` line and `EOF`), then save with `Ctrl+O`, `Enter` and exit with `Ctrl+X`.
>
> The config files are also in this folder as plain files
> ([prometheus/prometheus.yml](prometheus/prometheus.yml),
> [grafana/provisioning/datasources/prometheus.yml](grafana/provisioning/datasources/prometheus.yml)).

## 1. Install Prometheus + node-exporter

```bash
sudo apt-get update
sudo apt-get install -y prometheus prometheus-node-exporter curl
```

Both start automatically.

> Ubuntu's `prometheus` package is often a few versions behind upstream. That's fine
> for this setup. If you need the latest version, use the official binaries from
> https://prometheus.io/download/ instead.

## 2. Write the Prometheus config

Back up the default config:

```bash
sudo cp /etc/prometheus/prometheus.yml /etc/prometheus/prometheus.yml.orig
```

**Before pasting**, copy the block into a text editor and replace the `<...>` placeholders
with your servers' IPs or hostnames. Delete the entries you don't need. You can also paste
it as-is and fix it afterwards with `sudo nano /etc/prometheus/prometheus.yml`.

```bash
sudo tee /etc/prometheus/prometheus.yml > /dev/null <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]

  # Machine stats (CPU, RAM, disk, network), from prometheus-node-exporter.
  # Install prometheus-node-exporter on each LLM server too and list them here.
  - job_name: node
    static_configs:
      - targets: ["localhost:9100"]
        labels:
          server: monitoring-vm
      - targets: ["<llm-server-1>:9100"]
        labels:
          server: llm-server-1
      - targets: ["<llm-server-2>:9100"]
        labels:
          server: llm-server-2

  # llama.cpp llama-server instances, each started with --metrics.
  # One entry per server; add or remove blocks as needed.
  - job_name: llamacpp
    metrics_path: /metrics
    static_configs:
      - targets: ["<llm-server-1>:8080"]
        labels:
          server: llm-server-1
          model: glm-5.3
      - targets: ["<llm-server-2>:8080"]
        labels:
          server: llm-server-2
          model: <model-name>

  # vLLM instances; /metrics is on by default on the API port.
  - job_name: vllm
    metrics_path: /metrics
    static_configs:
      - targets: ["<vllm-host-1>:8000"]
        labels:
          server: vllm-host-1
      - targets: ["<vllm-host-2>:8000"]
        labels:
          server: vllm-host-2
EOF
```

YAML is picky about indentation. Use spaces, never tabs. Check and apply:

```bash
promtool check config /etc/prometheus/prometheus.yml && sudo systemctl restart prometheus
```

Optional: keep 30 days of data (the default is 15):

```bash
sudo sed -i 's|^ARGS=.*|ARGS="--storage.tsdb.retention.time=30d"|' /etc/default/prometheus
sudo systemctl restart prometheus
```

## 3. Install Grafana (official apt repo)

```bash
sudo apt-get install -y apt-transport-https software-properties-common wget gpg
sudo mkdir -p /etc/apt/keyrings
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt-get update
sudo apt-get install -y grafana
```

Add Prometheus as a data source automatically:

```bash
sudo tee /etc/grafana/provisioning/datasources/prometheus.yml > /dev/null <<'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
EOF
```

Start Grafana:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now grafana-server
```

## 4. Turn on metrics in the model servers

**llama.cpp:** add `--metrics` to every `llama-server` command:

```bash
./llama.cpp/build/bin/llama-server \
  -m ~/models/GLM-5.3/UD-Q4_K_XL/GLM-5.3-UD-Q4_K_XL-00001-of-0000X.gguf \
  --alias glm-5.3 --metrics \
  -t 48 -c 32768 -b 2048 -ub 2048 \
  --no-mmap --jinja \
  --host 0.0.0.0 --port 8080
```

**vLLM:** `/metrics` is on by default on the API port.

From the monitoring VM, check that each server answers:

```bash
curl -s http://<llm-server-1>:8080/metrics | head
curl -s http://<vllm-host-1>:8000/metrics | head
```

### Multiple LLM servers

Each server is one entry under the matching job (`llamacpp`, `vllm` or `node`), with a
`server` label so you can tell them apart:

```yaml
  - job_name: llamacpp
    metrics_path: /metrics
    static_configs:
      - targets: ["10.0.0.11:8080"]
        labels: { server: gpu-box-1, model: glm-5.3 }
      - targets: ["10.0.0.12:8080"]
        labels: { server: gpu-box-2, model: qwen3-coder }
```

- If one machine runs several llama-servers on different ports, add one entry per port
  (`10.0.0.11:8080`, `10.0.0.11:8081`, ...).
- For CPU, RAM and disk stats of each LLM server, install the exporter **on that server**
  with `sudo apt-get install -y prometheus-node-exporter` and add it under the `node` job.
- **Firewall on each LLM server:** let the monitoring VM reach the ports, and only the VM:

  ```bash
  sudo ufw allow from <monitoring-vm-ip> to any port 8080,9100 proto tcp   # llama.cpp
  sudo ufw allow from <monitoring-vm-ip> to any port 8000,9100 proto tcp   # vLLM
  ```

- In Grafana, split charts by server with `by (server)`, for example
  `sum by (server) (llamacpp:requests_processing)`. You can also add a dashboard variable
  with the query `label_values(server)` to get a server dropdown.

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

The LLM servers' ports (8080, 8000, 9100) must be reachable **from this VM**, and only
from it. See "Multiple LLM servers" above.

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
