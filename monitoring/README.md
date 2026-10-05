# Prometheus + Grafana monitoring

A Docker Compose stack for a Linux VM that monitors:

- **the VM itself** (CPU, RAM, disk, network) using node-exporter
- **llama.cpp `llama-server`** (GLM-5.3, see [../llamaCppInstr.md](../llamaCppInstr.md))
- **vLLM** on another server

| Service       | Port | URL                     |
|---------------|------|-------------------------|
| Grafana       | 3000 | `http://<vm-ip>:3000`   |
| Prometheus    | 9090 | `http://<vm-ip>:9090`   |
| node-exporter | 9100 | `http://<vm-ip>:9100`   |

```
monitoring/
├── docker-compose.yml
├── .env.example                      # copy to .env, set Grafana password
├── prometheus/prometheus.yml         # scrape targets
└── grafana/provisioning/datasources/prometheus.yml   # auto-adds Prometheus to Grafana
```

## 1. Install Docker on the VM (Ubuntu/Debian)

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker
docker compose version
```

## 2. Get the files

```bash
git clone https://github.com/AboveTheClouds90/gitPublic.git
cd gitPublic/monitoring
cp .env.example .env
nano .env            # set GRAFANA_ADMIN_PASSWORD
```

## 3. Turn on metrics in the model servers

**llama.cpp:** add `--metrics` to the `llama-server` command:

```bash
./llama.cpp/build/bin/llama-server \
  -m ~/models/GLM-5.3/UD-Q4_K_XL/GLM-5.3-UD-Q4_K_XL-00001-of-0000X.gguf \
  --alias glm-5.3 --metrics \
  -t 48 -c 32768 -b 2048 -ub 2048 \
  --no-mmap --jinja \
  --host 0.0.0.0 --port 8080
```

Check it: `curl http://127.0.0.1:8080/metrics`

**vLLM:** `/metrics` is on by default on the API port. Check it with `curl http://<vllm-host>:8000/metrics`.

## 4. Set the scrape targets

Edit `prometheus/prometheus.yml`:

- `llamacpp`: `host.docker.internal:8080` means llama-server runs **on this same VM**.
  If it runs somewhere else, use `<ip>:8080` instead.
- `vllm`: replace `<vllm-host>` with the vLLM server's IP or hostname.

## 5. Start it

```bash
docker compose up -d
docker compose ps
```

Open `http://<vm-ip>:9090/targets`. All targets should show **UP**.

After you edit `prometheus.yml`, reload it without restarting:

```bash
curl -X POST http://localhost:9090/-/reload
```

## 6. Grafana

1. Open `http://<vm-ip>:3000` and log in with the user and password from `.env`.
   The Prometheus data source is already set up.
2. VM dashboard: **Dashboards → New → Import**, enter ID **`1860`** (Node Exporter Full)
   and select the Prometheus data source.
3. LLM panels: create a new dashboard and add panels with these queries:

| What                                 | Query                                          |
|--------------------------------------|------------------------------------------------|
| llama.cpp generation speed (tok/s)   | `llamacpp:predicted_tokens_seconds`            |
| llama.cpp prompt processing (tok/s)  | `llamacpp:prompt_tokens_seconds`               |
| llama.cpp requests in progress       | `llamacpp:requests_processing`                 |
| vLLM requests running / waiting      | `vllm:num_requests_running`, `vllm:num_requests_waiting` |
| vLLM generated tokens/s              | `rate(vllm:generation_tokens_total[1m])`       |
| vLLM time to first token (p95)       | `histogram_quantile(0.95, rate(vllm:time_to_first_token_seconds_bucket[5m]))` |

Metric names can change between versions. If a query is empty, look up the exact
name with `curl <server>/metrics | grep -v '^#'`.

vLLM also has ready-made Grafana dashboards in its repo, under `examples/`
(search for "grafana"). You can import those as JSON.

## Security

- These ports have **no authentication**, except Grafana. Don't expose 9090, 9100,
  8080 or 8000 to the internet. Allow them only from your own IP or network:

  ```bash
  sudo ufw allow from <your-ip> to any port 3000,9090 proto tcp
  ```

  Docker-published ports **bypass ufw**. To keep Prometheus and node-exporter
  local-only, change their ports to `"127.0.0.1:9090:9090"` and
  `"127.0.0.1:9100:9100"` in `docker-compose.yml`, and reach them through
  Grafana or an SSH tunnel:
  `ssh -L 9090:localhost:9090 user@<vm-ip>`.
- Never commit `.env`. It's already in `.gitignore`.

## Useful commands

```bash
docker compose logs -f prometheus    # follow logs
docker compose pull && docker compose up -d   # update images
docker compose down                  # stop (data is kept in volumes)
docker compose down -v               # stop and DELETE all metrics/dashboards
```
