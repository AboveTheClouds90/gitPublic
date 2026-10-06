# Qwen3 Embedding + Qwen3 Reranker on one GPU with vLLM

Runs two vLLM servers on the same GPU, one per model, on separate ports:

| Model | Port | Endpoints |
|---|---|---|
| `Qwen/Qwen3-Embedding-0.6B` | 8001 | `/v1/embeddings` |
| `Qwen/Qwen3-Reranker-0.6B` | 8002 | `/rerank`, `/v1/rerank`, `/score` |

Checked against **vLLM 0.31.0** (released 2026-10-05) and the vLLM `latest` docs on 2026-10-06.
The sources are listed at the bottom.

## 1. Install

```bash
pip install -U "vllm==0.31.0"
vllm --version
```

## 2. Get the reranker chat template

The reranker needs a chat template that wraps query and document in Qwen's yes/no prompt.
A copy is in this directory: [`qwen3_reranker.jinja`](qwen3_reranker.jinja).
It is the vLLM repo file `examples/pooling/score/template/qwen3_reranker.jinja`. To download it fresh:

```bash
curl -L -o qwen3_reranker.jinja \
  https://raw.githubusercontent.com/vllm-project/vllm/main/examples/pooling/score/template/qwen3_reranker.jinja
```

## 3. Start the embedding server (port 8001)

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

## 4. Start the reranker server (port 8002)

```bash
vllm serve Qwen/Qwen3-Reranker-0.6B \
  --port 8002 \
  --runner pooling \
  --hf-overrides '{"architectures":["Qwen3ForSequenceClassification"],"classifier_from_token":["no","yes"],"is_original_qwen3_reranker":true}' \
  --chat-template ./qwen3_reranker.jinja \
  --gpu-memory-utilization 0.15 \
  --max-model-len 8192
```

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8002/health   # 200 = ready
```

**Option without `--hf-overrides`:** use the pre-converted checkpoint `tomaarsen/Qwen3-Reranker-0.6B-seq-cls`.
The vLLM example says it is more efficient than the original:

```bash
vllm serve tomaarsen/Qwen3-Reranker-0.6B-seq-cls \
  --port 8002 \
  --runner pooling \
  --chat-template ./qwen3_reranker.jinja \
  --gpu-memory-utilization 0.15 \
  --max-model-len 8192
```

## 5. Test

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

## 6. Test with Bruno

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

## Sources (search these titles)

| What | Where |
|---|---|
| vLLM 0.31.0 is the latest release (2026-10-05) | PyPI "vllm" → Release history — <https://pypi.org/project/vllm/#history> |
| `--gpu-memory-utilization` per-instance, `--runner`, `--convert`, `--hf-overrides`, `--max-model-len` | vLLM docs "Engine Arguments" — <https://docs.vllm.ai/en/latest/configuration/engine_args/> |
| `--task` removed; endpoint list (`/v1/embeddings`, `/rerank`, `/score`, …) | vLLM docs "Pooling Models" — <https://docs.vllm.ai/en/latest/models/pooling_models/> |
| `--runner pooling --convert embed`; Qwen3-Embedding listed as supported | vLLM docs "Pooling Models → Embed" — <https://docs.vllm.ai/en/latest/models/pooling_models/embed/> |
| Qwen3-Reranker `--hf-overrides` command | vLLM docs "Pooling Models → Scoring" — <https://docs.vllm.ai/en/latest/models/pooling_models/scoring/> |
| Reranker serve command with `--chat-template`, seq-cls checkpoint, `/score` request body | vLLM repo `examples/pooling/score/qwen3_reranker_online.py` — <https://github.com/vllm-project/vllm/blob/main/examples/pooling/score/qwen3_reranker_online.py> |
| Reranker chat template | vLLM repo `examples/pooling/score/template/qwen3_reranker.jinja` |
| Query instruction format, 1–5 % note, 32k context, 1024 dim | Hugging Face model card "Qwen/Qwen3-Embedding-0.6B" — <https://huggingface.co/Qwen/Qwen3-Embedding-0.6B> |
| Why the original reranker needs a conversion | Hugging Face "Qwen/Qwen3-Reranker-0.6B" discussion #3 — <https://huggingface.co/Qwen/Qwen3-Reranker-0.6B/discussions/3> |
| `.bru` file syntax (`meta`, `post`, `auth:bearer`, `body:json`, `tests`, `vars:secret`) | Bruno docs "Bru Lang" — <https://docs.usebruno.com/bru-lang/overview>; parser fixtures in GitHub `usebruno/bruno` → `packages/bruno-lang/v2/tests` |
| Community reports on two instances on one GPU | vLLM Forums "2 vllm containers on a single GPU" — <https://discuss.vllm.ai/t/2-vllm-containers-on-a-single-gpu/608> |

**Not tested on hardware.** The commands come from the docs above and were not run on a GPU.
The `/rerank` request body follows the documented Jina/Cohere-style API and is not copied from a Qwen-specific example.
