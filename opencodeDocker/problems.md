# Known problems and limits

Each item: what happens, then what to do.

## Windows-specific

- **Slow file access.** `C:\` folders reach the container through a file-sharing layer between Windows and the Docker VM.
  Big repos, `git status` and `node_modules` can be slow.
  → If it bothers you, keep the workspace inside WSL (e.g. `\\wsl$\Ubuntu\home\you\code`) and run compose from a WSL shell.
- **Git shows files as changed that you didn't touch.** This only matters if OpenCode runs git inside the container.
  - *Line endings:* with `core.autocrlf=true`, Windows git writes CRLF files. The Linux git in the container sees the difference.
    → Add a `.gitattributes` with `* text=auto eol=lf` to the repo.
  - *File permissions:* Windows files can show up with different permission bits.
    → `git config core.filemode false` in the repo.
- **File-change watching can be unreliable** across the Windows mount, so tools that watch files may miss changes.
- **Environment variable doesn't arrive.** A terminal (or IDE) keeps the variables it had when it opened.
  → After setting or changing a variable, open a new terminal. Sometimes you need to restart the IDE.
- **`localhost` in `baseURL` doesn't reach Windows.** Inside the container, `localhost` is the container.
  → Use `host.docker.internal` for anything running on your PC, e.g. LiteLLM.

## Setup

- **Only listed variables reach the container:** `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` and `LITE_LLM`.
  → Add others under `environment:` in `docker-compose.yml`.
- **Typo in `PROJECT`:** Docker creates an empty folder with that name in your workspace, and OpenCode starts there.
  → Check the name, then delete the empty folder.
  The same applies to a typo in `WORKSPACE_DIR`: Docker Desktop creates the missing folder on your PC.
- **`.env` missing:** the compose file falls back to `.\workspace` and starts in its root.
- **Old `opencode-config` volume:** earlier versions of this compose file kept the config in a Docker volume. It is no longer used.
  → Copy out anything you need, then delete it: `docker volume rm opencodedocker_opencode-config`.
  (The volume's prefix is the folder name, so check `docker volume ls`.)

## Safety

- **OpenCode can change or delete anything in `WORKSPACE_DIR`.** It also sees all projects there, not only `PROJECT`.
  → Commit or push before a session. If needed, point `WORKSPACE_DIR` at a smaller folder.
- **The container has full network access.** OpenCode can download, install and call anything.
- **Runs as root inside the container.** On Windows this doesn't matter.
  On a Linux host, new files in your projects would be owned by root.
- **`docker volume rm` of `opencode-data` deletes all sessions and saved logins.**
- **Keys never go into `config\opencode.json` or `.env.example`.** This folder is in a public repo.
  `.env` is in `.gitignore`.

## Not verified

- The setup has not been run end to end yet.
- That the upward config search finds `C:\code\opencode.json` (`/workspace/opencode.json`) is based on the docs only.
- The LiteLLM provider block follows the V2 provider docs. It has not been tested against a real LiteLLM proxy.
- The V2 docs don't say where logins (`auth.json`) are stored or whether `OPENCODE_CONFIG` still works.
  The volume paths are the same as in the original compose file.
