> [← 返回 llm-docker 主目录](../..)

# Qwen3.6-35B-A3B Docker 部署

> **RTX 4080 16G** + llama.cpp `b9542`，纯 GPU 跑 35B MoE 多模态，predict **32–49 t/s**

基于 [unsloth/Qwen3.6-35B-A3B-GGUF](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF) 量化包，IQ3_S 量化（13.7 GB）+ F16 mmproj（858 MB）。多阶段 Docker 镜像构建，CUDA 编译，运行期仅 ~700 MB。

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
9. [更换量化等级](#9-更换量化等级)
10. [bench.sh 测速脚本](#10-benchsh-测速脚本)
11. [常见问题](#11-常见问题)

---

## 1. 项目简介

| 项 | 值 |
|---|---|
| 模型 | Qwen3.6-35B-A3B（MoE，激活 3B） |
| 量化 | `Qwen3.6-35B-A3B-UD-IQ3_S.gguf`（13.7 GB） |
| 多模态 | `mmproj-F16.gguf`（858 MB） |
| 推理引擎 | llama.cpp `b9542`（含 libmtmd 多模态支持） |
| 上下文 | 256K（KV cache 量化 q8_0，存 CPU 内存） |

---

## 2. 硬件要求

**已验证配置**：i5-13600KF（20 线程）+ RTX 4080 16G + 32 GB DDR5 + CUDA 12.8.1（builder/runtime）。

**换 GPU**：修改 `.env` 里的 `CUDA_ARCHITECTURES`，对照表见 [`../../docs/gpu-architectures.md`](../../docs/gpu-architectures.md)。

> 改架构后需重新 `docker compose build --no-cache`。

---

## 3. 前置条件

Docker、NVIDIA Container Toolkit、CDI 配置等通用要求见 [`../../docs/prerequisites.md`](../../docs/prerequisites.md)。

---

## 4. 快速开始

```bash
# 1) 拿到本项目（git clone 或直接拷贝目录）
git clone https://github.com/niushuai1991/llm-docker.git
cd llm-docker/models/qwen3.6-35b-a3b

# 2) 配置环境变量（至少改 MODEL_HOST_DIR 为你的实际路径）
cp .env.example .env   # 如果没有 .env.example，直接编辑 .env
$EDITOR .env

# 3) 下载模型（默认到 /home/ns/models/Qwen3.6-35B-A3B/）
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

`download-model.sh` 自动用 modelscope（国内 CDN 快）→ hf-mirror 兜底。已存在的文件自动跳过，支持断点续传。

```bash
./download-model.sh                                 # 默认全部
MODEL_HOST_DIR=/data/qwen ./download-model.sh      # 改下载目录
MODEL_FILE=Qwen3.6-35B-A3B-UD-Q4_K_M.gguf \
  ./download-model.sh                               # 换量化
```

**前置依赖**：

```bash
pip install -U modelscope 'huggingface_hub[cli]'
```

**预期产物**：

```
/home/ns/models/Qwen3.6-35B-A3B/
├── Qwen3.6-35B-A3B-UD-IQ3_S.gguf   (~13 GB)
└── mmproj-F16.gguf                  (~858 MB)
```

---

## 6. 配置项一览

所有可调参数集中在 `.env`，compose 自动读取：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `LLAMA_CPP_REF` | `b9542` | llama.cpp git tag/commit。改后必须 `--no-cache` 重建 |
| `CUDA_ARCHITECTURES` | `89` | 目标 GPU 架构，见 §2 |
| `PORT` | `8080` | 宿主机暴露端口 |
| `MODEL_HOST_DIR` | `/home/ns/models/Qwen3.6-35B-A3B` | 宿主机模型目录（**记得改成你的路径**） |
| `MODEL_FILE` | `Qwen3.6-35B-A3B-UD-IQ3_S.gguf` | 主模型文件名 |
| `MMPROJ_FILE` | `mmproj-F16.gguf` | 多模态投影文件名 |
| `LOAD_MMPROJ` | `true` | `false` 可省 ~0.9 G 显存，纯文本场景用 |
| `CONTEXT_SIZE` | `256000` | 上下文长度。OOM 处理见 §11.5 |
| `EXTRA_ARGS` | （空） | 透传给 llama-server 的额外参数（如 `--temp 0.7 --top-p 0.8`） |

---

## 7. API 使用示例

本服务暴露的 `POST /v1/chat/completions` 端点**完全兼容 OpenAI Chat Completions 规范**，可直接对接：

- **OpenAI 官方 SDK**：Python `openai` 包、Node.js `openai` 包，把 `base_url` 指到 `http://localhost:8080/v1`、`api_key` 任意非空值即可
- **第三方客户端**：Cherry Studio / Lobe Chat / NextChat / Cline / Open WebUI 等所有支持 custom OpenAI endpoint 的工具
- **多模态图片输入**：走标准 OpenAI Vision API 格式（`content` 数组中 `image_url` + `text`），无需任何特殊适配

> 仅 `chat_template_kwargs.enable_thinking`（见 §7.2）是 llama.cpp 的扩展字段。

### 7.1 健康检查

```bash
curl http://localhost:8080/health
# {"status":"ok"}
```

### 7.2 enable_thinking 参数说明

Qwen3.6 支持推理模式（思考过程），通过 request body 里的 `chat_template_kwargs.enable_thinking` 字段控制，**关闭时**直接回答，**开启时**先输出思考再产出最终答案。

**字段说明**：

| 位置 | 字段 | 说明 |
|---|---|---|
| request | `chat_template_kwargs.enable_thinking` | `true` 开启思考；`false` 关闭（默认行为视调用方而定） |
| response | `message.reasoning_content` | 思考过程文本（仅 `enable_thinking=true` 时返回） |
| response | `message.content` | 最终答案 |

**示例（开启 thinking）**：

```bash
curl -X POST http://localhost:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "qwen",
    "messages": [
      {"role": "user", "content": "证明根号2是无理数"}
    ],
    "max_tokens": 2048,
    "chat_template_kwargs": {"enable_thinking": true}
  }'
# 返回里 message.reasoning_content 是思考过程，message.content 是最终答案
```

> `entrypoint.sh` 启动时使用 `--reasoning-budget 0`（即不强制思考 token 上限），由调用方按场景决定开/关。

---

## 8. 性能数据

**实测环境**：RTX 4080 16G + i5-13600KF + 32GB DDR5，IQ3_S 量化，256K 上下文。

由 `./bench.sh` 测得（3 次取平均，warm-up 后）：

| 场景 (in_tok / max_out) | prompt t/s | predict t/s | 实际 tok/run |
|---|---:|---:|---:|
| 短 (10 / 64)            |       60.6 |       **49.2** |          2 |
| 中 (20 / 256)           |       81.2 |       **33.1** |         77 |
| 长 (~200 / 512)         |      186.1 |       **32.8** |         58 |

**资源预算**：

| 项 | 位置 | 大小 |
|---|---|---|
| 模型权重 IQ3_S | GPU | ~13.7 GB |
| mmproj-F16 | GPU | ~0.9 GB |
| 激活值 / CUDA overhead | GPU | ~0.8 GB |
| **GPU 显存合计** |  | **~15.4 GB** ✅ |
| KV cache (q8_0, 256K) | **CPU 内存** | ~2.5 GB |

---

## 9. 更换量化等级

改 `.env` 里的 `MODEL_FILE` 一行即可，重启容器生效（**无需重建镜像**）：

```bash
# .env
MODEL_FILE=Qwen3.6-35B-A3B-UD-Q4_K_M.gguf
```

```bash
docker compose down && docker compose up -d
```

常见量化对照（来自 unsloth 仓库）：

| 量化 | 文件 | 大小 | 估算显存（含 mmproj + overhead） | 备注 |
|---|---|---|---|---|
| IQ3_S | `...-UD-IQ3_S.gguf` | ~13.7 GB | **~15.4 GB** | **当前 / 推荐 16G 卡** |
| Q4_K_M | `...-UD-Q4_K_M.gguf` | ~17 GB | ~19 GB | 24G 卡可用 |
| Q5_K_S | `...-UD-Q5_K_S.gguf` | ~20 GB | ~22 GB | 24G 卡勉强 |
| Q8_0 | `...-UD-Q8_0.gguf` | ~33 GB | ~35 GB | 48G+ 卡 |

---

## 10. bench.sh 测速脚本

项目自带 `bench.sh`，跑 3 个场景（短/中/长 prompt）× 3 次取平均，输出 markdown 表格 + VRAM。

```bash
./bench.sh                                # 默认 localhost:8080, RUNS=3
ENDPOINT=http://192.168.1.10:8080 ./bench.sh
RUNS=5 ./bench.sh                         # 每场景跑 5 次
```

依赖：`curl` + `python3`（用于 JSON 解析）。输出示例见 §8。

---

## 11. 常见问题

### 11.1 主机连不上 GitHub（git clone llama.cpp 失败）

国内通常需要走代理：

```bash
# 假设 clash 在 127.0.0.1:7890
HTTP_PROXY=http://127.0.0.1:7890 \
HTTPS_PROXY=http://127.0.0.1:7890 \
git clone --depth 1 --branch b9542 \
    https://github.com/ggml-org/llama.cpp.git llama.cpp-src
```

### 11.2 WSL2 下 GPU 找不到

见 [`../../docs/wsl2-notes.md`](../../docs/wsl2-notes.md)。

### 11.3 llama-server 报 `error: invalid argument: --fa`

b4400 用 `--fa on`，**b9542 改了**：

- 短形式：`-fa on`
- 长形式：`--flash-attn on`
- `--fa`（双 dash）**不再支持**

`entrypoint.sh` 已使用 `-fa on`。若你升级到更新版本又出问题，用以下命令查可用 flag：

```bash
docker run --rm --gpus all --entrypoint llama-server \
    qwen3.6-35b-a3b:latest --help | less
```

### 11.4 容器启动失败：`model file not found`

检查 `.env` 的 `MODEL_HOST_DIR` 是否指向实际存在模型的目录，且目录里有 `MODEL_FILE` 和 `MMPROJ_FILE`：

```bash
ls -lh "${MODEL_HOST_DIR}/${MODEL_FILE}"
ls -lh "${MODEL_HOST_DIR}/${MMPROJ_FILE}"
```

### 11.5 OOM（显存不足）

按以下顺序尝试：

1. `LOAD_MMPROJ=false`（纯文本场景，省 ~0.9 G）
2. `CONTEXT_SIZE=131072`（128K，KV cache 减半）
3. 换更小量化（见 §9）

### 11.6 升级 llama.cpp 版本

```bash
# 改 .env 的 LLAMA_CPP_REF（例如 b5331）
rm -rf llama.cpp-src
git clone --depth 1 --branch "$(grep ^LLAMA_CPP_REF .env | cut -d= -f2)" \
    https://github.com/ggml-org/llama.cpp.git llama.cpp-src
docker compose build --no-cache && docker compose up -d
```

> 必须用 `--no-cache`，否则 builder 层不会刷新。
