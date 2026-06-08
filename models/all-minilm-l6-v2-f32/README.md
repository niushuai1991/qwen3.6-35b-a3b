> [← 返回 llm-docker 主目录](../..)

# all-MiniLM-L6-v2 F32 Docker 部署

> **任意 GPU** + llama.cpp `b9542`，F32 精度 embedding 模型，模型仅 ~90 MB，<0.5 GB 显存即可运行

基于 [niushuai1991/all-MiniLM-L6-v2-f32-GGUF](https://huggingface.co/niushuai1991/all-MiniLM-L6-v2-f32-GGUF)，由 [sentence-transformers/all-MiniLM-L6-v2](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2) 通过 llama.cpp `convert_hf_to_gguf.py` 转换的 F32 GGUF。

---

## 目录

1. [项目简介](#1-项目简介)
2. [硬件要求](#2-硬件要求)
3. [前置条件](#3-前置条件)
4. [快速开始](#4-快速开始)
5. [模型下载](#5-模型下载)
6. [配置项一览](#6-配置项一览)
7. [API 使用示例](#7-api-使用示例)
8. [性能数据](#8-性能数据)
9. [bench.sh 测速脚本](#9-benchsh-测速脚本)
10. [常见问题](#10-常见问题)

---

## 1. 项目简介

| 项 | 值 |
|---|---|
| 模型 | all-MiniLM-L6-v2（sentence-transformers embedding） |
| 精度 | F32（完整精度 ~90 MB） |
| 推理引擎 | llama.cpp `b9542` |
| 上下文 | 256 tokens |
| API | `POST /v1/embeddings`（OpenAI 兼容） |

---

## 2. 硬件要求

模型极轻量（~90 MB F32），**任意有 GPU 的机器均可运行**，显存需求 <0.5 GB。

`CUDA_ARCHITECTURES` 按你的 GPU 设置，对照表见 [`../../docs/gpu-architectures.md`](../../docs/gpu-architectures.md)。

---

## 3. 前置条件

Docker、NVIDIA Container Toolkit、CDI 配置等通用要求见 [`../../docs/prerequisites.md`](../../docs/prerequisites.md)。

---

## 4. 快速开始

```bash
# 1) 拿到本项目（git clone 或直接拷贝目录）
git clone https://github.com/niushuai1991/llm-docker.git
cd llm-docker/models/all-minilm-l6-v2-f32

# 2) 配置环境变量（至少改 MODEL_HOST_DIR 为你的实际路径）
cp .env.example .env
$EDITOR .env

# 3) 下载模型（默认到 /home/ns/models/all-MiniLM-L6-v2-f32/）
./download-model.sh

# 4) 准备 llama.cpp 源码（builder 阶段 COPY 进去，不在容器内联网）
rm -rf llama.cpp-src
git clone --depth 1 --branch b9542 \
    https://github.com/ggml-org/llama.cpp.git llama.cpp-src

# 5) 构建并启动（首次约 5 min 编译）
docker compose up -d --build

# 6) 看启动日志
docker compose logs -f
# 看到 "server is listening on http://0.0.0.0:8080" 即成功
```

启动后参考 §7 验证服务（health 检查，或用任意 OpenAI 客户端连 `http://localhost:8080/v1`）。

---

## 5. 模型下载

`download-model.sh` 自动用 hf-mirror.com 下载。已存在的文件自动跳过。

```bash
./download-model.sh                                 # 默认全部
TARGET_DIR=/data/minilm ./download-model.sh         # 改下载目录
```

**前置依赖**：

```bash
pip install -U 'huggingface_hub[cli]'
```

**预期产物**：

```
/home/ns/models/all-MiniLM-L6-v2-f32/
└── all-MiniLM-L6-v2-f32.gguf   (~90 MB)
```

---

## 6. 配置项一览

所有可调参数集中在 `.env`，compose 自动读取：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `LLAMA_CPP_REF` | `b9542` | llama.cpp git tag/commit。改后必须 `--no-cache` 重建 |
| `CUDA_ARCHITECTURES` | `89` | 目标 GPU 架构，见 §2 |
| `PORT` | `8080` | 宿主机暴露端口 |
| `MODEL_HOST_DIR` | `/home/ns/models/all-MiniLM-L6-v2-f32` | 宿主机模型目录（**记得改成你的路径**） |
| `MODEL_FILE` | `all-MiniLM-L6-v2-f32.gguf` | 模型文件名 |
| `CONTEXT_SIZE` | `256` | 上下文长度（MiniLM 最大 512） |
| `EXTRA_ARGS` | （空） | 透传给 llama-server 的额外参数 |

---

## 7. API 使用示例

本服务暴露的 `POST /v1/embeddings` 端点**兼容 OpenAI Embeddings 规范**，可直接对接：

- **OpenAI 官方 SDK**：Python `openai` / Node.js `openai`，把 `base_url` 指到 `http://localhost:8080/v1`
- **langchain / llama_index** 等 embedding 框架

### 7.1 健康检查

```bash
curl http://localhost:8080/health
# {"status":"ok"}
```

### 7.2 获取 embedding

```bash
# 单条文本
curl -X POST http://localhost:8080/v1/embeddings \
  -H 'Content-Type: application/json' \
  -d '{"input": "hello world"}'

# 批量文本
curl -X POST http://localhost:8080/v1/embeddings \
  -H 'Content-Type: application/json' \
  -d '{"input": ["第一条文本", "第二条文本", "第三条文本"]}'
```

返回格式（384 维向量）：

```json
{
  "object": "list",
  "data": [
    {"object": "embedding", "embedding": [...], "index": 0}
  ],
  "model": "all-MiniLM-L6-v2-f32.gguf",
  "usage": {"prompt_tokens": 8, "total_tokens": 8}
}
```

### 7.3 Python SDK 示例

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8080/v1",
    api_key="not-needed"
)

# 单条
resp = client.embeddings.create(
    model="all-MiniLM-L6-v2-f32.gguf",
    input="hello world"
)
print(len(resp.data[0].embedding))  # 384

# 批量
resp = client.embeddings.create(
    model="all-MiniLM-L6-v2-f32.gguf",
    input=["text1", "text2", "text3"]
)
for d in resp.data:
    print(d.index, len(d.embedding))
```

---

## 8. 性能数据

> 待实测。预期吞吐数百 text/s，延迟 <10ms/条（GPU）。

---

## 9. bench.sh 测速脚本

项目自带 `bench.sh`，跑 4 个场景（单条 + 批量 10/50/100）× 3 次取平均，输出 markdown 表格。

```bash
./bench.sh                                # 默认 localhost:8080, RUNS=3
ENDPOINT=http://192.168.1.10:8080 ./bench.sh
RUNS=5 ./bench.sh                         # 每场景跑 5 次
```

依赖：`curl` + `python3`（用于 JSON 构造）。

---

## 10. 常见问题

### 10.1 容器启动失败：`model file not found`

检查 `.env` 的 `MODEL_HOST_DIR` 是否指向实际存在模型的目录，且 `MODEL_FILE` 存在：

```bash
ls -lh "${MODEL_HOST_DIR}/${MODEL_FILE}"
```

### 10.2 主机连不上 GitHub（git clone llama.cpp 失败）

国内通常需要走代理：

```bash
# 假设 clash 在 127.0.0.1:7890
HTTP_PROXY=http://127.0.0.1:7890 \
HTTPS_PROXY=http://127.0.0.1:7890 \
git clone --depth 1 --branch b9542 \
    https://github.com/ggml-org/llama.cpp.git llama.cpp-src
```

### 10.3 WSL2 下 GPU 找不到

见 [`../../docs/wsl2-notes.md`](../../docs/wsl2-notes.md)。

### 10.4 升级 llama.cpp 版本

```bash
# 改 .env 的 LLAMA_CPP_REF
rm -rf llama.cpp-src
git clone --depth 1 --branch "$(grep ^LLAMA_CPP_REF .env | cut -d= -f2)" \
    https://github.com/ggml-org/llama.cpp.git llama.cpp-src
docker compose build --no-cache && docker compose up -d
```

> 必须用 `--no-cache`，否则 builder 层不会刷新。
