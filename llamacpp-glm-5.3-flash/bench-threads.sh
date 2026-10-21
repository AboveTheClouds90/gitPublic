#!/usr/bin/env bash
# Compares thread counts (8, 16, 24, 32, 40) for GLM-5.3-Flash with llama-bench.
# A first run with 40, 48, 64, 96 was fastest at 40 (8.55 tok/s), so this tests below it.
# Other counts: THREADS=40,48,64,96 ./bench-threads.sh
# Stop llama-server first, so the two don't fight over the cores.
#
# Results (tokens/s, higher is better):
#   pp512 = prompt processing, how fast it reads input
#   tg128 = token generation, how fast it writes output
# Each thread count runs 3 times. Expect roughly 10-20 minutes plus model load.
#
# If llama-bench isn't in ./llama.cpp: LLAMA_BIN=./llama.cpp/build/bin ./bench-threads.sh
LLAMA_BIN=${LLAMA_BIN:-./llama.cpp}
THREADS=${THREADS:-8,16,24,32,40}

$LLAMA_BIN/llama-bench \
  -m ~/models/GLM-5.3-Flash/UD-Q4_K_XL/GLM-5.3-Flash-UD-Q4_K_XL-00001-of-00006.gguf \
  -t $THREADS \
  -b 2048 -ub 2048 \
  -fa 1 -ctk q8_0 -ctv q8_0 \
  -p 512 -n 128 -r 3 \
  -o md | tee bench-threads-$(date +%F-%H%M).md
