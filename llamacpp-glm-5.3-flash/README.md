# GLM-5.3-Flash with llama.cpp on a Proxmox VM (CPU only)

GLM-5.3-Flash is Z.ai's 320B MoE model with 18B active parameters, served here as an OpenAI-compatible API on port 8080.

| Host | Value |
|---|---|
| Hypervisor | Proxmox VE |
| RAM | 512 GB |
| CPU | AMD EPYC 9654, 96 cores, 12-channel DDR5-4800 (460.8 GB/s peak) |
| GPU | none |
| Quant | `UD-Q4_K_XL` (~200 GB, 6 shards) |

At ~200 GB the Q4 weights leave about 300 GB for the 128k KV cache, the prompt cache and the OS.
The VM can also hold `UD-Q5_K_XL` (~240 GB) or `UD-Q6_K_XL` (~292 GB), but those generate tokens more slowly on CPU.

Checked against the Unsloth GLM-5.3-Flash guide and the `unsloth/GLM-5.3-Flash-GGUF` file list on 2026-10-19.
**The configuration is untested on this hardware.**

## 1. Proxmox VM settings

Set these in the VM's Hardware and Options tabs before you start it:

- **CPU type `host`**, which passes AVX-512 / AVX2 through to the guest. The default `x86-64-v2-AVX` is much slower.
- **96 vCPUs**, with **NUMA enabled** if the host has more than one socket.
- **Memory ballooning off.** `--mlock` needs the memory to stay fixed.
- **About 480 GB of RAM for the VM.** The rest is left for the Proxmox host.

## 2. Build llama.cpp

GLM-5.3-Flash needs Unsloth's `glm5next/upstream` branch of llama.cpp (unslothai/llama.cpp PR #61), because mainline does not support it yet.

```bash
apt-get update
apt-get install pciutils build-essential cmake curl libcurl4-openssl-dev -y
git clone --branch glm5next/upstream https://github.com/unslothai/llama.cpp
cmake llama.cpp -B llama.cpp/build \
    -DBUILD_SHARED_LIBS=OFF -DGGML_CUDA=OFF -DGGML_NATIVE=ON
cmake --build llama.cpp/build --config Release -j --clean-first --target llama-cli llama-server llama-gguf-split llama-bench
cp llama.cpp/build/bin/llama-* llama.cpp
```

## 3. Download the Q4 model (~200 GB)

```bash
pip install -U "huggingface_hub[cli]"
hf download unsloth/GLM-5.3-Flash-GGUF \
  --include "*UD-Q4_K_XL*" \
  --local-dir ~/models/GLM-5.3-Flash
```

## 4. Start the server

```bash
./start-server.sh
```

| Flag | Why |
|---|---|
| `-t 30 -tb 96` | 30 threads for generation, which was fastest in `bench-threads.sh`. All 96 for prompt processing. |
| `-c 131072 -np 1` | 128k context with one slot. The model supports up to 1,048,576 tokens. |
| `-fa on -ctk q8_0 -ctv q8_0` | Flash attention plus an 8-bit KV cache, which halves the cache's RAM |
| `--mlock` | Keeps the weights in RAM so they never get swapped out |
| `--cache-ram 32768` | 32 GB prompt cache, so repeated prefixes are reused |
| `reasoning_effort` | `low`, `high` or `max`. The model defaults to `max`. |
| `--temp 1.0 --top-p 0.95` | Unsloth's recommended defaults |

The model is multimodal, but this setup serves text only.
For images, also download `mmproj-F16.gguf` from the same repo and add `--mmproj <path>`.

## 5. Test it

```bash
./test-curls.sh                      # on the VM
HOST=192.168.1.50 ./test-curls.sh    # from another machine, with the VM's IP
```

The script checks `/health`, lists the model, and sends one chat message.
The answer can take a while, because the model thinks before it replies.

## 6. Find the fastest thread count

```bash
./bench-threads.sh
```

Stop the server first.
The script runs `llama-bench` with 8, 16, 24, 32 and 40 threads and saves the table to `bench-threads-<date>.md`.
Pick other counts with `THREADS=40,48,64,96 ./bench-threads.sh`.

- Set `-t` in `start-server.sh` to the fastest `tg128` (output tokens/s).
- Set `-tb` to the fastest `pp512` (prompt tokens/s).

They usually differ.
Generation is limited by memory bandwidth, so it peaks below the core count.
Prompt processing is limited by compute, so it keeps scaling with more threads.

Results: 40 threads gave 8.55 tok/s and 48 gave 8.3. More threads were slower. The lower range peaked at 30.

## 7. Check how the RAM is installed

On the Proxmox host (not in the VM), as root:

```bash
./check-ram.sh
```

The script lists each DIMM slot with its size and speed, then counts the filled slots.
Full bandwidth needs 12 DIMMs, one per channel, running at 4800 MT/s.

## Sources

- Unsloth guide: https://unsloth.ai/docs/models/glm-5.3-flash
- GGUF files: https://huggingface.co/unsloth/GLM-5.3-Flash-GGUF
