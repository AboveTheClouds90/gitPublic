# OpenCode V2 in Docker (Windows host)

Runs the official OpenCode V2 image (`ghcr.io/anomalyco/opencode`) in a container.
OpenCode only sees your workspace folder, not the rest of your PC.
Known issues and limits are in [problems.md](problems.md).

| On Windows | In the container | What it is |
|---|---|---|
| `WORKSPACE_DIR` (e.g. `C:\code`) | `/workspace` | your folder of projects |
| `WORKSPACE_DIR\PROJECT` (e.g. `C:\code\my-app`) | `/workspace/my-app` | where OpenCode starts |
| `CONFIG_DIR` (default `opencodeDocker\config\`) | `/root/.config/opencode` | folder with your `opencode.json` (global config) |
| Docker volume `opencode-data` | `/root/.local/share/opencode` | sessions, logs, logins |
| Docker volume `opencode-state` | `/root/.local/state/opencode` | service state |

## Prerequisites

- Docker Desktop with the WSL2 backend (the default)
- PowerShell, in this folder (`opencodeDocker\`)

## Setup (once)

- **Create your `.env`:**
  ```powershell
  Copy-Item .env.example .env
  ```
  Then set the two values. Use forward slashes:
  ```
  WORKSPACE_DIR=C:/code
  PROJECT=my-app
  ```
- **API keys** come from your Windows environment variables, never from a file in this repo.
  - The compose file passes in `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` and `LITE_LLM`.
  - To set one (as a user variable):
    ```powershell
    [Environment]::SetEnvironmentVariable("LITE_LLM", "sk-...", "User")
    ```
  - Open a **new** terminal afterwards. Terminals that were already open still have the old value.
  - For another provider, add its variable name under `environment:` in `docker-compose.yml`.
- **Config folder:** to use your own folder instead of `config\`, set `CONFIG_DIR=D:/KI/docker/config` in `.env`.
  The folder must contain `opencode.json` (or `opencode.jsonc`).
- **Or edit the example `config\opencode.json`:**
  - It is set up for a LiteLLM proxy and reads the key from `LITE_LLM` (`"env": ["LITE_LLM"]`).
  - Replace `your-model` (in both places) with a model name your LiteLLM proxy serves.
  - Set `baseURL` to your proxy's address.
    If LiteLLM runs on this PC, keep `host.docker.internal`.
    `localhost` would point at the container itself.
    `4000` is LiteLLM's default port.

## Run

```powershell
docker compose run --rm opencode
```

- Use `run`, not `up`. With `up`, the OpenCode screen doesn't get your keyboard input.
- `--rm` deletes the container on exit. Sessions and logins stay in the `opencode-data` volume.
- **Other project:** change `PROJECT` in `.env`, or for one run:
  ```powershell
  $env:PROJECT="other-app"; docker compose run --rm opencode
  ```
  The value stays set until you close that terminal.

## Where OpenCode reads config from

- The files are **merged**. Later files override only the keys they set.
- From lowest to highest priority:
  1. `CONFIG_DIR\opencode.json` (default `opencodeDocker\config\`): global, for everything
  2. `C:\code\opencode.json`: all projects in the workspace (OpenCode searches up from the project folder)
  3. `C:\code\my-app\opencode.json`: one project
  4. `.opencode\opencode.json` in those folders: overrides the plain `opencode.json` files
- `opencode.jsonc` (JSON with comments) works too.
- The `update` setting is only read from the global config, so it must go in `config\`.

## Update OpenCode

- Set `OPENCODE_VERSION=2.x.y` in `.env`, then:
  ```powershell
  docker compose pull
  ```

## Sources (checked 2026-10-08)

- Config locations, merging and precedence: <https://opencode.ai/v2/docs/config/>, <https://opencode.ai/docs/config/>
- Custom provider format (`providers`, `env`, `package`, `settings.baseURL`, `models`): <https://opencode.ai/v2/docs/providers/>
