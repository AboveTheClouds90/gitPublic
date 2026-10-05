# Prometheus + Grafana monitoring (native install, Ubuntu/Debian)

Installs Prometheus and Grafana with `apt`, running as systemd services. No Docker, no git clone:
**every step is a block you paste into the VM's terminal.**

It collects the stats that the LLM servers report on their own `/metrics` address:

- **the GLM-5.3 llama.cpp `llama-server`** on this machine (`localhost:8080`, see [../llamaCppInstr.md](../llamaCppInstr.md))
- optionally more llama.cpp servers and **vLLM servers** (HTTPS + API key)

These are numbers over time (tokens/s, requests, cache use, latency), not logs.
Machine stats (CPU, RAM, disk) are not collected. For those, you would add node-exporter on each server.

| Service    | apt package                  | systemd unit     | Port |
|------------|------------------------------|------------------|------|
| Prometheus | `prometheus`                 | `prometheus`     | 9090 |
| Grafana    | `grafana` (Grafana apt repo) | `grafana-server` | 3000 |

> **How to paste a file:** the blocks below that start with `sudo tee ... <<'EOF'` write a
> whole file in one go. Paste the entire block, from the first line through `EOF`.
> Prefer nano? Run `sudo nano <path>`, paste only the file contents (the part between the
> `tee` line and `EOF`), then save with `Ctrl+O`, `Enter` and exit with `Ctrl+X`.
>
> The config files are also in this folder as plain files
> ([prometheus/prometheus.yml](prometheus/prometheus.yml),
> [grafana/provisioning/datasources/prometheus.yml](grafana/provisioning/datasources/prometheus.yml)).

## 1. Install Prometheus

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends prometheus curl
```

`--no-install-recommends` stops apt from pulling in node-exporter automatically.
Prometheus starts by itself after the install.

> Ubuntu's `prometheus` package is often a few versions behind upstream. That's fine
> for this setup. If you need the latest version, use the official binaries from
> https://prometheus.io/download/ instead.

## 2. Write the Prometheus config

Back up the default config:

```bash
sudo cp /etc/prometheus/prometheus.yml /etc/prometheus/prometheus.yml.orig
```

This config is ready to paste as-is. It scrapes the GLM-5.3 `llama-server` from
[../llamaCppInstr.md](../llamaCppInstr.md), running **on this same machine** on port `8080`.
To add vLLM servers, see [Add vLLM servers](#add-vllm-servers-https--api-key) further down.

```bash
sudo tee /etc/prometheus/prometheus.yml > /dev/null <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]

  # llama.cpp llama-server (GLM-5.3) on this machine, started with --metrics
  - job_name: llamacpp
    metrics_path: /metrics
    static_configs:
      - targets: ["localhost:8080"]
        labels:
          server: local
          model: glm-5.3
EOF
```

> If Prometheus runs on a **different** machine than llama-server, replace `localhost:8080`
> with `<llama-server-ip>:8080`.

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

Grafana isn't in Ubuntu's own repos, so apt first has to trust Grafana's signing key and
know where Grafana's package repo is. Paste these one block at a time.

Tools needed for the key download:

```bash
sudo apt-get update
sudo apt-get install -y wget gpg ca-certificates
```

Download Grafana's key and convert it for apt (the last line should list the file):

```bash
sudo mkdir -p /etc/apt/keyrings
wget -O /tmp/grafana.key https://apt.grafana.com/gpg.key
sudo gpg --dearmor -o /etc/apt/keyrings/grafana.gpg /tmp/grafana.key
ls -l /etc/apt/keyrings/grafana.gpg
```

Add the Grafana repo and install:

```bash
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt-get update
sudo apt-get install -y grafana
```

If the `wget` step fails:

| Message | Cause |
|---------|-------|
| `wget: command not found` | the tools step didn't run or failed. Check its output |
| `unable to resolve host address` | no DNS or internet. Test with `ping -c 3 8.8.8.8` and `ping -c 3 google.com` |
| `Connection timed out` | a firewall or proxy blocks outgoing HTTPS. Behind a proxy: `export https_proxy=http://<proxy>:<port>` |
| `certificate verification failed` | `ca-certificates` missing, or a proxy intercepts HTTPS |

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

## 4. Turn on metrics in llama-server

llama-server only serves `/metrics` when it's started with `--metrics`. Restart it like this
(this is the command from [../llamaCppInstr.md](../llamaCppInstr.md) plus `--alias` and `--metrics`):

```bash
./llama.cpp/build/bin/llama-server \
  -m ~/models/GLM-5.3/UD-Q4_K_XL/GLM-5.3-UD-Q4_K_XL-00001-of-0000X.gguf \
  --alias glm-5.3 --metrics \
  -t 48 -c 32768 -b 2048 -ub 2048 \
  --no-mmap --jinja \
  --host 0.0.0.0 --port 8080
```

Check that it answers. You should see lines starting with `llamacpp:`:

```bash
curl -s http://localhost:8080/metrics | head
```

### More llama.cpp servers

All llama.cpp servers go into the one `llamacpp` job, one entry each, with a
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
- **Firewall on each remote llama.cpp server:** let the monitoring VM reach the port, and only the VM:

  ```bash
  sudo ufw allow from <monitoring-vm-ip> to any port 8080 proto tcp
  ```

  If you also use these servers from OpenCode on other machines, allow those IPs as well.
- In Grafana, split charts by server with `by (server)`, for example
  `sum by (server) (llamacpp:requests_processing)`. You can also add a dashboard variable
  with the query `label_values(server)` to get a server dropdown.

After every config change:

```bash
promtool check config /etc/prometheus/prometheus.yml && sudo systemctl reload prometheus
```

### Add vLLM servers (HTTPS + API key)

**1. Store each vLLM server's key** in its own file that only Prometheus can read. This
keeps keys out of the config file and out of your shell history:

```bash
sudo install -d -m 750 -o root -g prometheus /etc/prometheus/secrets
sudo nano /etc/prometheus/secrets/vllm-host-1.key     # paste only the key, save
sudo chown root:prometheus /etc/prometheus/secrets/*.key
sudo chmod 640 /etc/prometheus/secrets/*.key
```

**2. Append a job per vLLM server** to the config. Replace `<vllm-host-1>` and `<https-port>`
first (without a port, 443 is used). The key is set per job, so each server with its own key
gets its own job. `tee -a` adds to the end of the file instead of overwriting it:

```bash
sudo tee -a /etc/prometheus/prometheus.yml > /dev/null <<'EOF'

  # vLLM server over HTTPS with an API key
  - job_name: vllm-host-1
    scheme: https
    metrics_path: /metrics
    authorization:
      type: Bearer
      credentials_file: /etc/prometheus/secrets/vllm-host-1.key
    static_configs:
      - targets: ["<vllm-host-1>:<https-port>"]
        labels:
          server: vllm-host-1
EOF
promtool check config /etc/prometheus/prometheus.yml && sudo systemctl reload prometheus
```

For a second server, repeat both steps with `vllm-host-2`. On each vLLM server, allow the
monitoring VM through the firewall:
`sudo ufw allow from <monitoring-vm-ip> to any port <https-port> proto tcp`.

**If a vLLM target isn't UP**, check these:

**Does `/metrics` need the key at all?** vLLM's own `--api-key` usually only protects the
`/v1/...` routes, so `/metrics` often answers without a key. A reverse proxy in front of
vLLM (nginx, Caddy, ...) may protect everything. Test both:

```bash
curl -s https://<vllm-host-1>:<https-port>/metrics | head
curl -s -H "Authorization: Bearer <api-key>" https://<vllm-host-1>:<https-port>/metrics | head
```

If the first one already returns metrics, you can delete the `authorization:` block (and the
key file) for that job.

**Is the proxy's path different?** If the proxy serves vLLM under a sub-path, e.g.
`https://host/vllm/v1/...`, set `metrics_path: /vllm/metrics`. Some proxies don't forward
`/metrics` at all, so check the proxy config.

**Certificate.** A normal certificate (e.g. Let's Encrypt) needs nothing extra. For a
**self-signed** certificate or one from your own CA, copy the CA certificate (`.crt`/`.pem`)
to the VM and add this to the job:

```yaml
    tls_config:
      ca_file: /etc/prometheus/secrets/my-ca.crt
      # server_name: vllm1.example.com   # if you connect by IP but the cert has a hostname
```

`insecure_skip_verify: true` (under `tls_config`) also works, but it turns off certificate
checking. Use it only for a quick test.

**Common errors** on `http://<vm-ip>:9090/targets`:

| Error on the targets page | Meaning |
|---------------------------|---------|
| `401 Unauthorized` / `403 Forbidden` | wrong or missing key, or the key file isn't readable by the `prometheus` user |
| `404 Not Found`           | wrong `metrics_path`, or the proxy doesn't forward `/metrics` |
| `x509: certificate signed by unknown authority` | self-signed cert: add `tls_config.ca_file` |
| `x509: certificate is valid for X, not Y` | set `tls_config.server_name`, or use the hostname from the cert |
| `server gave HTTP response to HTTPS client` | the server is plain HTTP: remove `scheme: https` |

Check the key file can be read by Prometheus:

```bash
sudo -u prometheus cat /etc/prometheus/secrets/vllm-host-1.key > /dev/null && echo OK
```

## 5. Check it

```bash
systemctl status prometheus grafana-server --no-pager
```

Open `http://<vm-ip>:9090/targets`. All targets should show **UP**.

## 6. Grafana

1. Open `http://<vm-ip>:3000` and log in as `admin` / `admin`. **Change the password when
   it asks you to.** (Forgot it? `sudo grafana cli admin reset-admin-password <new-pw>`)
2. The Prometheus data source is already set up from step 3.
3. Create a new dashboard and add panels with these queries:

| What                                 | Query                                          |
|--------------------------------------|------------------------------------------------|
| llama.cpp generation speed (tok/s)   | `llamacpp:predicted_tokens_seconds`            |
| llama.cpp prompt processing (tok/s)  | `llamacpp:prompt_tokens_seconds`               |
| llama.cpp requests in progress       | `llamacpp:requests_processing`                 |
| vLLM requests running / waiting      | `vllm:num_requests_running`, `vllm:num_requests_waiting` |
| vLLM generated tokens/s              | `rate(vllm:generation_tokens_total[1m])`       |
| vLLM time to first token (p95)       | `histogram_quantile(0.95, rate(vllm:time_to_first_token_seconds_bucket[5m]))` |
| Server reachable (1 = up, 0 = down)  | `up{job=~"llamacpp\|vllm.*"}`                  |

Metric names can change between versions. If a query is empty, look up the exact
name with `curl -s <server>/metrics | grep -v '^#'`.

vLLM also has ready-made Grafana dashboards in its repo, under `examples/`
(search for "grafana"). You can import those as JSON.

## Security

Prometheus (9090) has **no login** and listens on all interfaces by default. Use a firewall
on the monitoring VM:

```bash
sudo ufw allow OpenSSH
sudo ufw allow from <your-ip> to any port 3000 proto tcp   # Grafana, only from you
sudo ufw enable
```

With only those rules, 9090 stays closed from outside. Grafana still reaches it through
`localhost`. To open the Prometheus UI, use an SSH tunnel:

```bash
ssh -L 9090:localhost:9090 user@<vm-ip>    # then open http://localhost:9090
```

## Useful commands

```bash
journalctl -u prometheus -f                 # Prometheus logs
journalctl -u grafana-server -f             # Grafana logs
sudo systemctl restart prometheus grafana-server
sudo apt-get update && sudo apt-get upgrade # updates both
```

Config and data locations:

| What                  | Path                                |
|-----------------------|-------------------------------------|
| Prometheus config     | `/etc/prometheus/prometheus.yml`    |
| Prometheus flags      | `/etc/default/prometheus`           |
| Prometheus data       | `/var/lib/prometheus/metrics2/`     |
| Grafana config        | `/etc/grafana/grafana.ini`          |
| Grafana provisioning  | `/etc/grafana/provisioning/`        |
| Grafana data          | `/var/lib/grafana/`                 |
