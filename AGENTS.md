# AGENTS.md

Docker 部署合集：每个 LLM 一个独立目录，多阶段 CUDA 构建。当前仅 `models/qwen3.6-35b-a3b`。

## 仓库性质

- 纯 shell + Docker 仓库。**无构建系统、无 CI、无 lint、无测试**——别去找。
- 文档、注释、log 输出全部用中文。新增/修改时保持语言风格一致。
- `llama.cpp-src/`（gitignored）：宿主机 clone 的 llama.cpp 源码，构建期 `COPY` 进 builder。仓库不 vendor 这份代码。

## 新增模型

在 `models/<name>/` 下复制以下结构，参考 `models/qwen3.6-35b-a3b/`：

- `Dockerfile`（多阶段：builder 编译 CUDA，runtime 仅二进制）
- `docker-compose.yml`（参数全部 `${VAR:-default}`，不硬编码）
- `.env.example`（参数模板；`.env` 由 gitignore 排除）
- `entrypoint.sh` / `download-model.sh` / `bench.sh`（带 `set -euo pipefail`）
- `README.md`（中文，章节结构对齐现有模型）

最后在根 `README.md` 的「模型索引」表追加一行。

## 构建关键点

**必须先 clone llama.cpp 源码**（构建上下文里没有就 `docker build` 直接失败）：

```bash
git clone --depth 1 --branch "$LLAMA_CPP_REF" \
    https://github.com/ggml-org/llama.cpp.git llama.cpp-src
```

**必须 `docker compose build --no-cache` 的场景：**
- 改 `LLAMA_CPP_REF`
- 改 `CUDA_ARCHITECTURES`
- 升级 llama.cpp

只换 `MODEL_FILE` / `CONTEXT_SIZE` 等运行期参数 → `down && up -d` 即可。

## llama.cpp 版本陷阱

- `entrypoint.sh` 用 `-fa on`。**不要改回 `--fa`**——b9542 起双 dash 形式已废弃。若升级后报参数错，用以下命令核对：
  ```bash
  docker run --rm --gpus all --entrypoint llama-server <image> --help
  ```
- 默认版本号在仓库内不一致：
  - `Dockerfile` / `docker-compose.yml` 的 fallback 是 `b4400`
  - `.env.example` / README 实测用的是 `b9542`

  `.env` 覆盖 compose 默认值；当前推荐版本是 `b9542`。改 Dockerfile 默认时三处文件一起更新。

## 显存 / KV cache 策略

`entrypoint.sh` 的 `--no-kv-offload -ctk q8_0 -ctv q8_0` 把 KV cache 量化后放 CPU 内存，让 256K 上下文跑进 16G 卡。改动前先评估显存预算（模型 README §8）。

## `.env` 是单一真实源

所有运行期参数（端口、模型文件、CUDA 架构、上下文长度、mmproj 开关）都在 `.env`，compose 自动读。**不要在 `docker-compose.yml` 里硬编码值**，只放 `${VAR:-default}` 形式。

## CUDA 架构

- 单卡：`89`（RTX 4080）/ `86`（RTX 30 系）/ `120`（Blackwell，需 CUDA 12.10+ builder）/ `80`/`90`（A100/H100）
- 多卡混合：分号分隔，如 `86;89`
- builder 内 cmake 3.22，**不要加 `-realtime` 后缀**

完整对照表见 `docs/gpu-architectures.md`。

## 常用命令

```bash
cd models/qwen3.6-35b-a3b

# 首次构建（前置：llama.cpp-src 已 clone，.env 已配 MODEL_HOST_DIR）
docker compose up -d --build

# 仅换运行期参数
docker compose down && docker compose up -d

# 升级 llama.cpp（必须 --no-cache）
docker compose build --no-cache && docker compose up -d

# 基准（容器需运行中，依赖 curl + python3）
./bench.sh
```
