# Using the local GLM-5.3 llama-server with OpenCode

This assumes `llama-server` is running as described in [llamaCppInstr.md](llamaCppInstr.md)
(port `8080`, `--jinja` enabled — required for tool calling).

## 0. Give the model a stable name (recommended)

Add `--alias glm-5.3` to the `llama-server` command so `/v1/models` reports a short,
predictable model ID instead of the shard filename:

```bash
./llama.cpp/build/bin/llama-server \
  -m ~/models/GLM-5.3/UD-Q4_K_XL/GLM-5.3-UD-Q4_K_XL-00001-of-0000X.gguf \
  --alias glm-5.3 \
  -t 48 -c 32768 -b 2048 -ub 2048 \
  --no-mmap --jinja \
  --host 0.0.0.0 --port 8080
```

Check it:

```bash
curl http://127.0.0.1:8080/v1/models
```

If OpenCode runs on a different machine than the server, replace `127.0.0.1` below with the
server's IP (the server already listens on `0.0.0.0`).

Config file location (both versions): `~/.config/opencode/opencode.jsonc` (global)
or `opencode.json(c)` in the project root.

`limit.context` must not exceed the server's `-c` value (32768 here). If you raise `-c`, raise it here too.

---

## OpenCode v2

V2 renamed the provider block: `provider` → `providers`, `npm` → `package`,
`options` → `settings`, and models get an explicit `modelID` + `capabilities`.

```jsonc
// ~/.config/opencode/opencode.jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "model": "llamacpp/glm-5.3",
  "providers": {
    "llamacpp": {
      "name": "llama-server (local)",
      "package": "@opencode/ai/providers/openai-compatible",
      "settings": {
        "baseURL": "http://127.0.0.1:8080/v1"
      },
      "models": {
        "glm-5.3": {
          "name": "GLM-5.3 UD-Q4_K_XL (local)",
          "modelID": "glm-5.3",
          "capabilities": {
            "tools": true,
            "input": ["text"],
            "output": ["text"]
          },
          "limit": {
            "context": 32768,
            "output": 8192
          }
        }
      }
    }
  }
}
```

- `"model": "llamacpp/glm-5.3"` = `<provider key>/<model key>`, makes it the default.
- `modelID` is what gets sent to the server — it must match the `--alias`.
- The migration guide also shows `"package": "aisdk:@ai-sdk/openai-compatible"`; either should work.

### If the model doesn't show up / "Model unavailable"

Several early V2 releases (e.g. 2.0.15, 2.0.16) had bugs where custom providers in
`providers` were parsed but never added to the model list
([#42856](https://github.com/anomalyco/opencode/issues/42856),
[#51252](https://github.com/anomalyco/opencode/issues/51252),
[#51285](https://github.com/anomalyco/opencode/issues/51285)).
First update OpenCode. If it still fails, the workaround reported in #51252 is to keep the
V2 `providers` block **and** add the equivalent V1 `provider` block next to it:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "model": "llamacpp/glm-5.3",
  "providers": {
    "llamacpp": {
      "name": "llama-server (local)",
      "package": "@opencode/ai/providers/openai-compatible",
      "settings": { "baseURL": "http://127.0.0.1:8080/v1" },
      "models": {
        "glm-5.3": {
          "name": "GLM-5.3 UD-Q4_K_XL (local)",
          "modelID": "glm-5.3",
          "capabilities": { "tools": true, "input": ["text"], "output": ["text"] },
          "limit": { "context": 32768, "output": 8192 }
        }
      }
    }
  },
  // V1 fallback, same provider
  "provider": {
    "llamacpp": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "llama-server (local)",
      "options": { "baseURL": "http://127.0.0.1:8080/v1" },
      "models": {
        "glm-5.3": {
          "name": "GLM-5.3 UD-Q4_K_XL (local)",
          "limit": { "context": 32768, "output": 8192 }
        }
      }
    }
  }
}
```

Also: don't let the automatic V1→V2 migration rewrite an existing config blindly — it has
been reported to overwrite `baseURL` with the wrong value
([#50286](https://github.com/anomalyco/opencode/issues/50286)). Check `settings.baseURL` afterwards.

---

## OpenCode v1 (for reference)

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "model": "llamacpp/glm-5.3",
  "provider": {
    "llamacpp": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "llama-server (local)",
      "options": {
        "baseURL": "http://127.0.0.1:8080/v1"
      },
      "models": {
        "glm-5.3": {
          "name": "GLM-5.3 UD-Q4_K_XL (local)",
          "limit": {
            "context": 32768,
            "output": 8192
          }
        }
      }
    }
  }
}
```

In v1 the model key itself (`glm-5.3`) is sent to the server, so it must match `--alias`.

---

## Use it

```bash
opencode            # uses the default "model" from the config
# or pick it in the TUI with /models -> "GLM-5.3 UD-Q4_K_XL (local)"
```

Sources:
[OpenCode providers docs](https://opencode.ai/docs/providers/),
[OpenCode V2 models docs](https://opencode.ai/v2/docs/models/),
[OpenCode V2 migration guide](https://opencode.ai/v2/docs/migrate-v1/)
