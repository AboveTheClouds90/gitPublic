#!/usr/bin/env bash
# Compares thread counts (40, 48, 64, 96) for GLM-5.3 with llama-bench.
# Stop llama-server first: the model is ~430 GB and won't fit in RAM twice.
#
# Results (tokens/s, higher is better):
#   pp512 = prompt processing, how fast it reads input
#   tg128 = token generation, how fast it writes output
# Each thread count runs 3 times. Expect roughly 15-30 minutes plus model load.
#
# If llama.cpp isn't in /llama.cpp: LLAMA_BIN=./llama.cpp/build/bin ./bench-threads.sh
LLAMA_BIN=${LLAMA_BIN:-/llama.cpp/build/bin}

$LLAMA_BIN/llama-bench \
  -m ~/models/GLM-5.3/UD-Q4_K_XL/GLM-5.3-UD-Q4_K_XL-00001-of-00011.gguf \
  -t 40,48,64,96 \
  -b 2048 -ub 2048 \
  -fa 1 -ctk q8_0 -ctv q8_0 \
  -p 512 -n 128 -r 3 \
  -o md | tee bench-threads-$(date +%F-%H%M).md
