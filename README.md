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
12. [目录结构](#12-目录结构)
13. [致谢](#13-致谢)

---

## 1. 项目简介

| 项 | 值 |
|---|---|
| 模型 | Qwen3.6-35B-A3B（MoE，激活 3B） |
| 量化 | `Qwen3.6-35B-A3B-UD-IQ3_S.gguf`（13.7 GB） |
| 多模态 | `mmproj-F16.gguf`（858 MB），支持图片输入 |
| 推理引擎 | llama.cpp `b9542`（含 libmtmd 多模态支持） |
| 上下文 | 256K（KV cache 量化 q8_0，存 CPU 内存） |
| 端口 | `8080`（OpenAI 兼容 API） |
| GPU 显存 | **15.4 G / 16 G**（RTX 4080 实测） |
| 推理速度 | predict **32–49 t/s**（视 prompt 长度） |

---

## 2. 硬件要求

**已验证配置**：

- GPU：NVIDIA RTX 4080 16G（Ada Lovelace, sm_89）
- CPU：i5-13600KF（20 线程，server 用 10 线程）
- 内存：32 GB（KV cache 占 ~2.5 GB）
- CUDA：12.8.1（builder） + 12.8.1（runtime）

**换 GPU**：修改 `.env` 里的 `CUDA_ARCHITECTURES`：

| 显卡系列 | 架构代码 |
|---|---|
| RTX 40 系列（4080/4090/4070 ...） | `89` |
| RTX 30 系列（3090/3080/3060 ...） | `86` |
| RTX 50 系列（Blackwell） | `120`（**需 CUDA 12.10+ builder**） |
| A100 / H100 | `80` / `90` |
| 多卡混合 | `86;89`（分号分隔） |

> 改架构后需重新 `docker compose build --no-cache`。

---

## 3. 前置条件

### 3.1 Docker + Compose

```bash
docker --version          # >= 24.0
docker compose version    # v2
```

### 3.2 NVIDIA Container Toolkit

```bash
# Ubuntu/Debian（详细见 https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html）
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

### 3.3 CDI 配置（关键！WSL2 尤其需要）

```bash
# 生成 CDI spec
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

# 验证 GPU 可见
docker run --rm --gpus all nvidia/cuda:12.8.1-base-ubuntu22.04 nvidia-smi
```

> WSL2 用户：系统自带 spec 可能引用错误驱动路径，**必须**重新生成。详见 §11.2。

---

## 4. 快速开始

```bash
# 1) 拿到本项目（git clone 或直接拷贝目录）
git clone https://github.com/niushuai1991/qwen3.6-35b-a3b.git
cd qwen3.6-35b-a3b

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

冒烟测试：

```bash
curl http://localhost:8080/health
# {"status":"ok"}

curl -X POST http://localhost:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model":"qwen",
    "messages":[{"role":"user","content":"一个汉字回答：天空是什么颜色"}],
    "max_tokens":64,
    "chat_template_kwargs":{"enable_thinking":false}
  }'
```

---

## 5. 模型下载

`download-model.sh` 自动用 modelscope（国内 CDN 快）→ hf-mirror 兜底。已存在的文件自动跳过，支持断点续传。

```bash
./download-model.sh                                 # 默认全部
TARGET_DIR=/data/qwen ./download-model.sh           # 改下载目录
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
| `CONTEXT_SIZE` | `256000` | 上下文长度。OOM 时降到 `131072` 或 `65536` |
| `EXTRA_ARGS` | （空） | 透传给 llama-server 的额外参数（如 `--temp 0.7 --top-p 0.8`） |

---

## 7. API 使用示例

### 7.1 健康检查

```bash
curl http://localhost:8080/health
# {"status":"ok"}
```

### 7.2 文本对话（关闭 thinking，纯文本回答）

```bash
curl -X POST http://localhost:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "qwen",
    "messages": [
      {"role": "user", "content": "用三句话解释光合作用"}
    ],
    "max_tokens": 256,
    "chat_template_kwargs": {"enable_thinking": false}
  }'
```

### 7.3 文本对话（开启 thinking，复杂推理）

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

> `entrypoint.sh` 默认 `--reasoning-budget 0`（即不强制思考 token 上限），由调用方按场景决定开/关。

### 7.4 多模态（图片输入）

```bash
# 准备一张图片，base64 编码
IMG=$(base64 -w0 photo.jpg)

curl -X POST http://localhost:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d "{
    \"model\": \"qwen\",
    \"messages\": [{
      \"role\": \"user\",
      \"content\": [
        {\"type\": \"image_url\", \"image_url\": {\"url\": \"data:image/jpeg;base64,${IMG}\"}},
        {\"type\": \"text\", \"text\": \"描述这张图片\"}
      ]
    }],
    \"max_tokens\": 512,
    \"chat_template_kwargs\": {\"enable_thinking\": false}
  }"
```

> mmproj 在容器启动时已加载（日志可见 `loaded multimodal model`）。如不需图片功能，设 `LOAD_MMPROJ=false` 省 ~0.9 G 显存。

---

## 8. 性能数据

**实测环境**：RTX 4080 16G + i5-13600KF + 32GB DDR5，IQ3_S 量化，256K 上下文。

由 `./bench.sh` 测得（3 次取平均，warm-up 后）：

| 场景 (in_tok / max_out) | prompt t/s | predict t/s | 实际 tok/run |
|---|---:|---:|---:|
| 短 (10 / 64)            |       60.6 |       **49.2** |          2 |
| 中 (20 / 256)           |       81.2 |       **33.1** |         77 |
| 长 (~200 / 512)         |      186.1 |       **32.8** |         58 |

显存占用：

```
NVIDIA GeForce RTX 4080, 15515 MiB / 16376 MiB used, util 40%
```

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

下载新量化：

```bash
MODEL_FILE=Qwen3.6-35B-A3B-UD-Q4_K_M.gguf ./download-model.sh
```

---

## 10. bench.sh 测速脚本

项目自带 `bench.sh`，跑 3 个场景（短/中/长 prompt）× 3 次取平均，输出 markdown 表格 + VRAM。

```bash
./bench.sh                                # 默认 localhost:8080, RUNS=3
ENDPOINT=http://192.168.1.10:8080 ./bench.sh
RUNS=5 ./bench.sh                         # 每场景跑 5 次
```

输出（直接可粘贴到 issue / 报告）：

```markdown
## Bench Results

| 场景 (in_tok / max_out) | prompt t/s | predict t/s | 实际 tok/run |
|---|---:|---:|---:|
| 短 (10 / 64)            |       60.6 |       49.2 |          2 |
| 中 (20 / 256)           |       81.2 |       33.1 |         77 |
| 长 (~200 / 512)         |      186.1 |       32.8 |         58 |

## VRAM

NVIDIA GeForce RTX 4080, 15515 MiB, 16376 MiB, 40 %
```

依赖：`curl` + `python3`（用于 JSON 解析）。

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

或者把已下载的源码拷过来（不带 `.git`）：

```bash
cp -r /tmp/llama.cpp llama.cpp-src
rm -rf llama.cpp-src/.git
```

### 11.2 WSL2 下 `docker run --gpus all` 报 GPU 找不到

WSL2 的 nvidia-ctk 生成的 CDI spec 可能引用错误驱动路径。重新生成：

```bash
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
# 验证
docker run --rm --gpus all nvidia/cuda:12.8.1-base-ubuntu22.04 nvidia-smi
```

正常会列出你的 GPU。

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

### 11.6 llama.cpp 源码如何准备

Dockerfile 第 44 行 `COPY llama.cpp-src/ /src/` 把宿主机的 `llama.cpp-src/` 整个拷进 builder。**不会在容器内联网**，所以必须先在宿主机 clone 好。

升级版本：

```bash
# 改 .env 的 LLAMA_CPP_REF
$EDITOR .env                # 例如 LLAMA_CPP_REF=b5331

# 更新源码
rm -rf llama.cpp-src
git clone --depth 1 --branch "$(grep ^LLAMA_CPP_REF .env | cut -d= -f2)" \
    https://github.com/ggml-org/llama.cpp.git llama.cpp-src

# 重建（必须 --no-cache，否则 builder 层不刷新）
docker compose build --no-cache
docker compose up -d
```

---

## 12. 目录结构

```
qwen3.6-35b-a3b/
├── .dockerignore              # build context 排除（.git/.env/*.md 等）
├── .env                       # 配置（团队复现时改这里）
├── Dockerfile                 # 多阶段：builder (CUDA devel) + runtime
├── docker-compose.yml         # 编排，CDI GPU 声明
├── entrypoint.sh              # llama-server 启动脚本
├── download-model.sh          # 模型下载（modelscope/hf-mirror）
├── bench.sh                   # 推理速度基准
├── deploy-qwen3.6-35b-a3b.md  # 原始部署笔记
├── PLAN.md                    # 执行计划与决策记录
├── README.md                  # 本文件
└── llama.cpp-src/             # llama.cpp 源码（builder COPY 进去）

# 模型在宿主机另一个目录（默认）：
/home/ns/models/Qwen3.6-35B-A3B/
├── Qwen3.6-35B-A3B-UD-IQ3_S.gguf   (~13 GB)
└── mmproj-F16.gguf                  (~858 MB)
```

---

## 13. 致谢

- [Qwen Team](https://qwenlm.github.io/) —— Qwen3.6-35B-A3B 原始模型
- [unsloth](https://huggingface.co/unsloth) —— GGUF 量化包（IQ3_S / Q4_K_M 等）
- [llama.cpp](https://github.com/ggml-org/llama.cpp) —— 推理引擎，特别感谢 `b9542` 重新引入 `--mmproj` 多模态支持
- [modelscope](https://modelscope.cn) —— 国内 CDN 下载加速
