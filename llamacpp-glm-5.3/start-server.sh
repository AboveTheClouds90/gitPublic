#!/usr/bin/env bash
/llama.cpp/build/bin/llama-server \
  -m ~/models/GLM-5.3/UD-Q4_K_XL/GLM-5.3-UD-Q4_K_XL-00001-of-00011.gguf \
  --alias glm-5.3 \
  -c 131072 -np 1 \
  -t 48 -tb 48 -b 2048 -ub 2048 \
  -fa on -ctk q8_0 -ctv q8_0 \
  -lm mlock --cache-ram 32768 \
  --jinja --reasoning-effort high \
  --temp 1.0 --top-p 1.0 --min-p 0.01 \
  --timeout 14400 \
  --host 0.0.0.0 --port 8080
