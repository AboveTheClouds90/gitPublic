#!/usr/bin/env bash
./llama.cpp/llama-server \
  -m ~/models/GLM-5.3-Flash/UD-Q4_K_XL/GLM-5.3-Flash-UD-Q4_K_XL-00001-of-00006.gguf \
  --alias glm-5.3-flash \
  -c 131072 -np 1 \
  -t 96 -tb 96 -b 2048 -ub 2048 \
  -fa on -ctk q8_0 -ctv q8_0 \
  --mlock --cache-ram 32768 \
  --jinja --chat-template-kwargs '{"reasoning_effort":"high"}' \
  --temp 1.0 --top-p 0.95 --min-p 0.01 \
  --timeout 14400 \
  --host 0.0.0.0 --port 8080
