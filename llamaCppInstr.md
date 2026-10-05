# Running GLM-5.3 with llama.cpp

```bash
# 1. Create and activate the environment
conda create -n llama -c conda-forge python=3.12 cmake compilers git -y
conda activate llama
pip install -U huggingface_hub

# 2. Get and build llama.cpp
git clone https://github.com/ggml-org/llama.cpp
cd llama.cpp
cmake -B build -DGGML_NATIVE=ON -DLLAMA_CURL=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build build -j 32
cd ..

# 3. Download the Q4 model (~430 GB)
hf download unsloth/GLM-5.3-GGUF \
  --include "*UD-Q4_K_XL*" \
  --local-dir ~/models/GLM-5.3

# 4. Find the first shard's exact name
ls ~/models/GLM-5.3/UD-Q4_K_XL/

# 5. Start the server
./llama.cpp/build/bin/llama-server \
  -m ~/models/GLM-5.3/UD-Q4_K_XL/GLM-5.3-UD-Q4_K_XL-00001-of-0000X.gguf \
  --alias glm-5.3 --metrics \
  -t 48 -c 32768 -b 2048 -ub 2048 \
  --no-mmap --jinja \
  --host 0.0.0.0 --port 8080
```
