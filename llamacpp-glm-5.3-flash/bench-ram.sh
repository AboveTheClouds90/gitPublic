#!/usr/bin/env bash
# Measures RAM bandwidth from inside the VM with the STREAM benchmark.
# Use this when you can't run check-ram.sh on the Proxmox host.
# Stop llama-server first, so it doesn't use bandwidth during the test.
#
# Look at the Triad line, in MB/s (350000 MB/s = 350 GB/s). The EPYC 9654
# peaks at 460.8 GB/s with 12 channels, and STREAM usually reaches 70-85% of that:
#   above ~300 GB/s   12 channels at full speed
#   ~200-250 GB/s     probably 8 channels
#   below ~200 GB/s   fewer channels, slower DIMMs, or VM overhead
#
# Other thread counts: THREADS="16 30 48 96" ./bench-ram.sh
THREADS=${THREADS:-16 30 48 96}
DIR=${DIR:-$HOME/stream}

mkdir -p "$DIR"
if [ ! -x "$DIR/stream" ]; then
  curl -fsSL -o "$DIR/stream.c" https://www.cs.virginia.edu/stream/FTP/Code/stream.c
  # 400M doubles per array, 3 arrays = ~9.6 GB, far bigger than the 384 MB L3
  gcc -O3 -march=native -fopenmp -mcmodel=medium \
    -DSTREAM_ARRAY_SIZE=400000000 -DNTIMES=10 \
    "$DIR/stream.c" -o "$DIR/stream" || exit 1
fi

for t in $THREADS; do
  echo "=== $t threads"
  OMP_NUM_THREADS=$t OMP_PROC_BIND=spread OMP_PLACES=cores "$DIR/stream" | grep -E '^(Function|Copy|Triad):?'
done
