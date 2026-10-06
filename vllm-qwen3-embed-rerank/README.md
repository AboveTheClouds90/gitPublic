# Qwen3 Embedding + Qwen3 Reranker on one GPU with vLLM

Runs two vLLM servers on the same GPU, one per model, on separate ports:

| Model | Port | Endpoints | Tested on hardware |
|---|---|---|---|
| `Qwen/Qwen3-Embedding-0.6B` | 8001 | `/v1/embeddings` | yes, loads and works |
| `Qwen/Qwen3-Reranker-0.6B` | 8002 | `/rerank`, `/v1/rerank`, `/score` | not yet: needs the CUDA Toolkit (step 2) |

Checked against **vLLM 0.31.0** (released 2026-10-05) and the vLLM `latest` docs on 2026-10-06.
The sources are listed at the bottom.

## 1. Install vLLM

```bash
pip install -U "vllm==0.31.0"
vllm --version
```

## 2. Install the CUDA Toolkit (needed for the reranker)

The pip wheels already bring the CUDA *runtime*, which is enough for the embedding model.
At startup the embedding model only prints a warning about the missing `nvcc` / `CUDA_HOME`, and you can ignore it.

The **reranker fails** without the CUDA *Toolkit*, which provides the `nvcc` compiler:

```
RuntimeError: Could not find nvcc and default CUDA_HOME
```

Something in the reranker's startup compiles a GPU kernel on your machine, and that needs `nvcc`.
Install a Toolkit that matches the CUDA version PyTorch was built with:

```bash
python -c "import torch; print(torch.version.cuda)"   # e.g. 12.8
```

On Ubuntu 24.04, use NVIDIA's apt repo. On 22.04, replace `ubuntu2404` with `ubuntu2204`.
Replace `12-8` / `12.8` with your version.

```bash
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt update
sudo apt install -y cuda-toolkit-12-8            # toolkit only, does NOT touch the driver

echo 'export CUDA_HOME=/usr/local/cuda-12.8' >> ~/.bashrc
echo 'export PATH=$CUDA_HOME/bin:$PATH'       >> ~/.bashrc
source ~/.bashrc
nvcc --version                                    # should print 12.8
```

- **Don't use `apt install nvidia-cuda-toolkit`.** Ubuntu's own package is usually an older CUDA version that doesn't match PyTorch.
- **The first reranker start can take a few minutes.** It compiles the kernel once and caches it, so later starts are fast.

## 3. Get the reranker chat template

The reranker needs a chat template that wraps query and document in Qwen's yes/no prompt.
It is the vLLM repo file `examples/pooling/score/template/qwen3_reranker.jinja`.
A copy is also in this directory: [`qwen3_reranker.jinja`](qwen3_reranker.jinja).

**The file must be on the GPU machine.** Download it there to a fixed folder, and always pass the full path.
A relative path like `./qwen3_reranker.jinja` only works if you start vLLM from the folder that contains the file.
Otherwise vLLM fails with *"The supplied chat template string appears path-like, but doesn't exist"*.

```bash
mkdir -p ~/vllm-templates
curl -fL -o ~/vllm-templates/qwen3_reranker.jinja \
  https://raw.githubusercontent.com/vllm-project/vllm/main/examples/pooling/score/template/qwen3_reranker.jinja

ls -l ~/vllm-templates/qwen3_reranker.jinja       # must exist, ~600 bytes
head -1 ~/vllm-templates/qwen3_reranker.jinja     # should print <|im_start|>system
```

If the GPU machine can't reach GitHub, copy the file over from your PC:
`scp vllm-qwen3-embed-rerank/qwen3_reranker.jinja user@gpu-host:~/vllm-templates/`

## 4. Start the embedding server (port 8001)

```bash
vllm serve Qwen/Qwen3-Embedding-0.6B \
  --port 8001 \
  --runner pooling --convert embed \
  --gpu-memory-utilization 0.15 \
  --max-model-len 8192
```

Wait until it is ready:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8001/health   # 200 = ready
```

## 5. Start the reranker server (port 8002)

```bash
vllm serve Qwen/Qwen3-Reranker-0.6B \
  --port 8002 \
  --runner pooling \
  --hf-overrides '{"architectures":["Qwen3ForSequenceClassification"],"classifier_from_token":["no","yes"],"is_original_qwen3_reranker":true}' \
  --chat-template "$HOME/vllm-templates/qwen3_reranker.jinja" \
  --gpu-memory-utilization 0.15 \
  --max-model-len 8192
```

Use `$HOME`, not `~`, inside the quotes, because the shell doesn't expand `~` inside double quotes.

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8002/health   # 200 = ready
```

**Option without `--hf-overrides`:** use the pre-converted checkpoint `tomaarsen/Qwen3-Reranker-0.6B-seq-cls`.
The vLLM example says it is more efficient than the original:

```bash
vllm serve tomaarsen/Qwen3-Reranker-0.6B-seq-cls \
  --port 8002 \
  --runner pooling \
  --chat-template "$HOME/vllm-templates/qwen3_reranker.jinja" \
  --gpu-memory-utilization 0.15 \
  --max-model-len 8192
```

## 6. Test

Embeddings:

```bash
curl -s http://localhost:8001/v1/embeddings -H "Content-Type: application/json" -d '{
  "model": "Qwen/Qwen3-Embedding-0.6B",
  "input": ["Instruct: Given a web search query, retrieve relevant passages that answer the query\nQuery: What is the capital of China?",
            "The capital of China is Beijing."]
}'
```

Rerank (one query, many documents):

```bash
curl -s http://localhost:8002/rerank -H "Content-Type: application/json" -d '{
  "model": "Qwen/Qwen3-Reranker-0.6B",
  "query": "What is the capital of China?",
  "documents": ["The capital of China is Beijing.", "Gravity is a force that attracts two bodies."]
}'
```

Score (the request body from the official vLLM example):

```bash
curl -s http://localhost:8002/score -H "Content-Type: application/json" -d '{
  "model": "Qwen/Qwen3-Reranker-0.6B",
  "queries": ["What is the capital of China?", "Explain gravity"],
  "documents": ["The capital of China is Beijing.", "Gravity is a force that attracts two bodies towards each other."]
}'
```

## 7. Test with Bruno

A ready-made Bruno collection is in [`bruno/`](bruno/):

| Request | Method + URL | Body |
|---|---|---|
| Embed health | `GET {{embedBaseUrl}}/health` | none |
| Rerank health | `GET {{rerankBaseUrl}}/health` | none |
| Embeddings | `POST {{embedBaseUrl}}/v1/embeddings` | `model`, `input` (list of strings), `encoding_format` |
| Rerank | `POST {{rerankBaseUrl}}/rerank` | `model`, `query` (string), `documents` (list) |
| Score | `POST {{rerankBaseUrl}}/score` | `model`, `queries` (list), `documents` (list) |

1. In Bruno, choose **Open Collection** and select the `vllm-qwen3-embed-rerank/bruno` folder.
2. In the top-right environment dropdown, select **local**.
   It sets `embedBaseUrl` to `http://localhost:8001` and `rerankBaseUrl` to `http://localhost:8002`.
   To test a remote GPU box, change these to its address.
3. If you started vLLM with `--api-key`, open **Environments → local** and set `apiKey`.
   It is a secret variable, so Bruno doesn't write it into the `.bru` file.
   Without `--api-key`, leave it empty. vLLM then ignores the `Authorization` header.
4. Run the requests one by one, or right-click the collection and choose **Run** to run all five.
   Each request has tests:
   - the health requests expect `200`
   - Embeddings expects 2 vectors of 1024 dimensions
   - Rerank expects the Beijing document to be ranked first
   - Score expects one score per query/document pair

What the responses look like:

- **Embeddings:** `data[i].embedding` is a list of 1024 floats, in the same order as `input`.
- **Rerank:** `results` is sorted by relevance. Each item has `index`, which points back into `documents`, and `relevance_score`.
- **Score:** `data[i].score` is the score for the pair `queries[i]` + `documents[i]`.

The bodies are the same as the `curl` examples above.
To try your own texts, edit the JSON in each request's **Body** tab.

## Notes

- **`--gpu-memory-utilization` is a fraction of the GPU's total VRAM.** It is not quantization.
  The engine-args docs call it a *per-instance limit* that applies only to the current vLLM instance.
  Keep the values of all instances on the GPU summed below 1.0. On a 47 GB GPU, 0.15 is about 7 GB.
  Each 0.6B model's weights are about 1.2 GB in bf16, and vLLM uses the rest for KV cache.
  0.1 per model is enough for light traffic.
- **Start the servers one after the other, not at the same time.** This is a precaution.
  The docs say instances are independent. Community forum threads report startup failures when two instances profile memory at the same moment (mostly older versions).
- **`--task` has been removed.** Older guides use `--task embed` / `--task score`.
  Current vLLM uses `--runner pooling` plus `--convert embed|classify`.
  The reranker needs no `--convert`, because `--hf-overrides` already makes it a sequence-classification model.
- **Without `--hf-overrides`,** the original `Qwen/Qwen3-Reranker-0.6B` loads as a plain causal LM and its scores are wrong.
- **Prefix queries with an instruction for embeddings** (`Instruct: ...\nQuery: ...`). Do not prefix documents.
  The model card says skipping the instruction can cost about 1–5% retrieval performance.
- **`--max-model-len 8192`** caps the context, which is 32k by default for these models. That saves memory. Raise it if your documents are long.
- **Add `--api-key <key>`** to both commands if the ports are reachable from outside the machine.

## Sources

### Where each flag comes from

None of the `vllm serve` flags come from the Hugging Face model cards.
Those cards only show older Python examples.
All flags come from vLLM's own docs and examples in the GitHub repo `vllm-project/vllm`, on the `main` branch, checked on 2026-10-06.
Open the file on GitHub and go to the line number.

| Flag / fact | Source (repo `vllm-project/vllm`, branch `main`) | Line |
|---|---|---|
| `Qwen/Qwen3-Embedding-0.6B` is supported as an embedding model (`Qwen3ForCausalLM`, marked C) | `docs/models/pooling_models/embed.md` | 53 |
| C = "Automatically converted into an embedding model via `--convert embed`". This means `--convert embed` is probably redundant but harmless. | `docs/models/pooling_models/embed.md` | 99 |
| What `--convert <type>` does in general | `docs/models/pooling_models/README.md` | 249–263 |
| Reranker `--hf_overrides '{"architectures": ["Qwen3ForSequenceClassification"], "classifier_from_token": ["no","yes"], "is_original_qwen3_reranker": true}'` | `docs/models/pooling_models/scoring.md` | 88 |
| `Qwen/Qwen3-Reranker-0.6B` and `tomaarsen/Qwen3-Reranker-0.6B-seq-cls` listed, with the `qwen3_reranker.jinja` template | `docs/models/pooling_models/scoring.md` | 52 |
| Full reranker command with `--runner pooling` and `--chat-template`, the seq-cls alternative, and the `/score` body | `examples/pooling/score/qwen3_reranker_online.py` | 21, 25 |
| Same overrides in Python, with comments explaining each key | `examples/pooling/score/qwen3_reranker_offline.py` | 52+ |
| Reranker chat template (copied into this directory) | `examples/pooling/score/template/qwen3_reranker.jinja` | — |

What the Hugging Face model cards say:

- **`Qwen/Qwen3-Embedding-0.6B`:** the "vLLM Usage" section uses `LLM(model=..., task="embed")`. `task` has since been removed from vLLM.
  This card is the source for the `Instruct: …\nQuery: …` query format, the 1–5% note, the 32k context and the 1024 dimensions.
  <https://huggingface.co/Qwen/Qwen3-Embedding-0.6B>
- **`Qwen/Qwen3-Reranker-0.6B`:** the "vLLM Usage" section has **no** `hf_overrides`.
  It scores in Python by generating and reading the "yes"/"no" token probabilities.
  It is a valid approach, but it doesn't give you an HTTP rerank server.
  <https://huggingface.co/Qwen/Qwen3-Reranker-0.6B>
- **Background on why the reranker is converted to a classifier:** Hugging Face discussion #3 on `Qwen/Qwen3-Reranker-0.6B`.
  <https://huggingface.co/Qwen/Qwen3-Reranker-0.6B/discussions/3>

### Other sources

| What | Where |
|---|---|
| vLLM 0.31.0 is the latest release (2026-10-05) | PyPI "vllm" → Release history: <https://pypi.org/project/vllm/#history> |
| `--gpu-memory-utilization` is a per-instance limit; `--runner`, `--convert`, `--hf-overrides`, `--max-model-len` | vLLM docs "Engine Arguments": <https://docs.vllm.ai/en/latest/configuration/engine_args/> |
| `--task` removed; endpoint list (`/v1/embeddings`, `/rerank`, `/score`, …) | vLLM docs "Pooling Models": <https://docs.vllm.ai/en/latest/models/pooling_models/> |
| `.bru` file syntax (`meta`, `post`, `auth:bearer`, `body:json`, `tests`, `vars:secret`) | Bruno docs "Bru Lang": <https://docs.usebruno.com/bru-lang/overview>; parser test files in GitHub `usebruno/bruno` under `packages/bruno-lang/v2/tests` |
| Community reports on running two instances on one GPU | vLLM Forums "2 vllm containers on a single GPU": <https://discuss.vllm.ai/t/2-vllm-containers-on-a-single-gpu/608> |

Line numbers are as of 2026-10-06. They can move when vLLM updates its docs, so if a line doesn't match, search the file for `is_original_qwen3_reranker` or `--convert embed`.

**Hardware status:** the embedding command was run on a GPU and works. The reranker command has not run successfully yet (see step 2).
The `/rerank` request body follows the documented Jina/Cohere-style API and is not copied from a Qwen-specific example.
