---
name: llm-docker-add-model
description: 在 llm-docker 仓库（多阶段 CUDA llama.cpp Docker 部署合集）中新增模型部署目录。Use when: (1) 用户说"添加新模型 / 创建 X 部署 / 加个 gemma/qwen/llama 部署"; (2) 用户分享 HuggingFace 模型链接要求编写 Dockerfile / docker-compose / entrypoint; (3) 在 models/ 下创建新子目录的任何任务。覆盖研究 → 决策 → 模板填充 → 索引更新 → 验证 全流程。仓库 AGENTS.md 是单一真实源，本 skill 仅补充流程指引。
---

# Add LLM Model to llm-docker

## 触发条件

当用户在本仓库（或结构相同的 llama.cpp Docker 部署仓库）中需要新增一个模型部署目录时触发。典型信号：

- "加一个 Gemma-4-12B 部署"
- "帮我写 llama-3 的 docker 脚本"（前面已经讨论过模型链接）
- 分享 HuggingFace URL 并要求"创建部署脚本"

**不要在用户只是查询模型信息、问 llama.cpp 用法、或调试已有模型时触发**——这些用通用工具即可。

---

## 工作流（5 阶段）

### Phase 1: 研究（5 分钟）

先读完仓库 `AGENTS.md`，再用研究脚本拉取目标模型的客观信息：

```bash
.claude/skills/llm-docker-add-model/scripts/research-model.sh <hf-repo-id> [llama.cpp-tag]
```

例：

```bash
.claude/skills/llm-docker-add-model/scripts/research-model.sh google/gemma-4-12B b9847
```

脚本输出三块：

1. **Model Info** — arch、参数量、dtype、上下文长度、模态（text/image/audio）
2. **GGUF Sources** — HF 上已有 GGUF 转换仓库列表，标注 `[official]`(ggml-org) / `[full]`(unsloth/bartowski 等全档位) / `[partial]`
3. **llama.cpp Support** — 指定 tag 是否已合入目标 arch，列出注册的 converter class

研究阶段必须确认：

- 模型存在且是对话模型（非 embedding / encoder-only）
- GGUF 已有人转换（否则要先 `convert_hf_to_gguf.py` 自己转，超出本 skill 范围）
- llama.cpp 的某个 release tag 已支持目标 arch（**研究脚本是辅助，最终要肉眼复核 conversion/<arch>.py 的注册类**）

### Phase 2: 决策提问（向用户）

使用 `question` 工具一次问 4 个标准问题，每个都给推荐项 + 简短说明：

| 问题 | 选项维度 |
|---|---|
| 1. Base vs IT | instruction-tuned 通常推荐 |
| 2. GGUF 来源 | ggml-org（官方但档位少）/ unsloth（档位全）/ bartowski |
| 3. 默认量化档位 | 基于目标 GPU 显存（16G/24G/48G）推荐 |
| 4. LLAMA_CPP_REF | 研究脚本报告的最小支持 release tag |

提问示例见 `references/question-template.md`（如存在），否则参考仓库现有对话。

### Phase 3: 模板填充

从 `assets/` 复制 8 个模板到 `models/{{MODEL_DIR}}/`，按下面的变量替换表填充。

#### 变量替换表（12 个占位符）

| 占位符 | 含义 | Qwen 示例 | Gemma-4 示例 |
|---|---|---|---|
| `{{MODEL_HUMAN_NAME}}` | README 标题用的人类可读名 | Qwen3.6-35B-A3B | Gemma-4-12B-it |
| `{{MODEL_DIR}}` | `models/` 下的目录名 | qwen3.6-35b-a3b | gemma-4-12b-it |
| `{{CONTAINER_NAME}}` | docker container_name | qwen3.6-35b-a3b | gemma-4-12b-it |
| `{{LLAMA_CPP_REF}}` | 默认 llama.cpp git tag | b9542 | b9847 |
| `{{CUDA_ARCHITECTURES}}` | 默认 CUDA arch（单数字或分号串） | 89 | 89 |
| `{{MODEL_FILE}}` | 默认 GGUF 主文件名 | Qwen3.6-35B-A3B-UD-IQ3_S.gguf | gemma-4-12b-it-Q4_K_M.gguf |
| `{{MMPROJ_FILE}}` | 默认 mmproj 文件名 | mmproj-F16.gguf | mmproj-F16.gguf |
| `{{HF_REPO}}` | 默认 GGUF 仓库 ID | unsloth/Qwen3.6-35B-A3B-GGUF | unsloth/gemma-4-12b-it-GGUF |
| `{{MS_REPO}}` | modelscope 镜像（通常同 HF） | 同上 | 同上 |
| `{{CONTEXT_SIZE}}` | 默认上下文 | 256000 | 256000 |
| `{{ARCH_NAME}}` | 架构短名（验证用，不写入文件） | qwen3 | gemma4 |
| `{{QUANT_SIZE}}` | README 性能节标注的量化大小 | ~13.7 GB | ~7.5 GB |

填充策略：用 `edit` 工具按 `replaceAll=true` 一次替换一个占位符。注意 `.dockerignore` 无占位符，直接复制。

**必须三处同步**（来自 AGENTS.md）：`Dockerfile` ARG / `docker-compose.yml` args / `.env.example` 的 `LLAMA_CPP_REF` 默认值要完全一致。改默认时三处一起更新。

### Phase 4: 更新根 README 索引

打开仓库根 `README.md`，在"模型索引"表追加一行：

```markdown
| {{MODEL_HUMAN_NAME}} | llama.cpp `{{LLAMA_CPP_REF}}` | {{QUANT_LABEL}} ({{QUANT_SIZE}}) | ~{{VRAM_BUDGET}} GB | ⏳ 待验证 | [models/{{MODEL_DIR}}](./models/{{MODEL_DIR}}) |
```

字段说明：

- `{{QUANT_LABEL}}`：量化标识如 `Q4_K_M` / `IQ3_S`
- `{{VRAM_BUDGET}}`：模型权重 + mmproj + overhead 的总估算显存

状态字段首次创建时用 `⏳ 待验证`；用户实测过性能后再改成 `✅ 已验证（GPU + tok/s 范围）`。

### Phase 5: 验证

```bash
# 1. shell 语法检查
bash -n models/{{MODEL_DIR}}/entrypoint.sh
bash -n models/{{MODEL_DIR}}/download-model.sh
bash -n models/{{MODEL_DIR}}/bench.sh

# 2. 三处 LLAMA_CPP_REF 一致性
grep -H "LLAMA_CPP_REF" models/{{MODEL_DIR}}/Dockerfile \
                       models/{{MODEL_DIR}}/docker-compose.yml \
                       models/{{MODEL_DIR}}/.env.example

# 3. mmproj 文件名与 GGUF 仓库实际命名核对
# （去 HF 仓库页面肉眼看，research 脚本不能可靠捕获 mmproj 命名变体）

# 4. 占位符残留检查（应为空）
grep -rE '\{\{[A-Z_]+\}\}' models/{{MODEL_DIR}}/
```

若任一检查失败，立即修正。

---

## 关键陷阱（继承自 AGENTS.md）

1. **`-fa on`（不要写 `--fa`）**——b9542 起双 dash 形式已废弃。升级后报参数错用 `docker run --rm --gpus all --entrypoint llama-server <image> --help` 核对。
2. **KV cache 策略**：`--no-kv-offload -ctk q8_0 -ctv q8_0` 把 KV 量化后存 CPU 内存，让 256K 上下文进 16G 卡。改动前评估显存预算。
3. **`CUDA_ARCHITECTURES` 不带 `-realtime` 后缀**——builder 内 cmake 3.22 不识别。
4. **所有 shell 脚本必须 `set -euo pipefail`**。
5. **文档、注释、log 输出全部用中文**——保持仓库风格一致。
6. **`.env` 是单一真实源**——所有运行期参数走 `${VAR:-default}`，不要在 `docker-compose.yml` 硬编码。

---

## 模型族特殊适配

不同模型族在 `entrypoint.sh` 和 `bench.sh` 里有差异，下面列出常见的。

### 多模态（图像 / 音频）

- 模板里默认 `LOAD_MMPROJ=true` + `MMPROJ_FILE=mmproj-F16.gguf`
- 纯文本模型：把 `LOAD_MMPROJ` 默认值改 `false`，README §6 标注"无多模态"
- mmproj 文件名变体（来自不同 GGUF 仓库）：
  - `mmproj-F16.gguf`（unsloth 多见）
  - `mmproj-Q8_0.gguf`（ggml-org 默认）
  - `mmproj-<model>-F16.gguf`（bartowski 多见）
- 写 `.env.example` 前必须去 HF 仓库页面**核对实际文件名**

### 思考模式（reasoning）

- llama-server 用 `--reasoning-budget N`（N=0 关闭，N>0 启用且限制 token 数）
- 模板里 `entrypoint.sh` 默认 `--reasoning-budget 0`，让调用方按场景开/关
- 调用方 API 层面：
  - **Qwen3.x**：`chat_template_kwargs.enable_thinking` 字段
  - **Gemma-4**：request 顶层 `reasoning` 字段或通过 `enable_thinking` 在 chat template 里支持
  - **DeepSeek-R1**：模型自带思考，无需开关
- `bench.sh` 里要按模型族的字段调整 `chat_template_kwargs`，否则可能触发思考模式拿到非预期结果

### chat_template_kwargs 速查

| 模型族 | 关 thinking 字段 | 例 |
|---|---|---|
| Qwen3.x | `chat_template_kwargs.enable_thinking = false` | Qwen 模板默认 |
| Gemma-4 | 默认不思考；启用通过 `reasoning` 字段或 chat template 选项 | bench 可省略该字段 |
| Llama 3.x | 无思考模式 | 不写 |
| DeepSeek-R1 | 始终思考 | 不能关 |

---

## 失败场景与回退

### llama.cpp tag 不支持目标 arch

研究脚本报告 `❌ Not supported` 时：

1. 查 llama.cpp master 是否已合入（改 tag 参数为 `master` 再跑）
2. 若 master 有，找包含该 commit 的最小 release tag（看 GitHub `releases` 页）
3. 若 master 也没有，说明社区尚未适配——告知用户该模型暂不能用 llama.cpp 部署

### GGUF 仓库不可用

HF 上没有现成 GGUF 时：

1. 提示用户用 `convert_hf_to_gguf.py` 本地转换（不在本 skill 范围）
2. 给出参考命令：`python convert_hf_to_gguf.py <hf-model-dir> --outtype f16`

### 国内访问 HuggingFace 超时

研究脚本默认走 `localhost:7890` 代理（`PROXY` 环境变量可覆盖）。若用户无代理，把 `HF_ENDPOINT=https://hf-mirror.com` 传给 `hf` 命令，但 HF API 走 `huggingface.co` 域名，hf-mirror 不代理 API——只能让用户开代理。

---

## 模板清单

`assets/` 下 8 个模板文件，详细填充规则见各文件内注释：

| 文件 | 关键占位符 | 备注 |
|---|---|---|
| `Dockerfile.tmpl` | `{{LLAMA_CPP_REF}}` / `{{CUDA_ARCHITECTURES}}` | 三处同步之一 |
| `docker-compose.yml.tmpl` | `{{CONTAINER_NAME}}` / `{{LLAMA_CPP_REF}}` / `{{MODEL_FILE}}` 等 | 三处同步之二 |
| `.env.example.tmpl` | 全部 12 个占位符（除 `{{ARCH_NAME}}`） | 三处同步之三 |
| `entrypoint.sh.tmpl` | `{{MODEL_FILE}}` / `{{MMPROJ_FILE}}` / `{{CONTEXT_SIZE}}` | set -euo pipefail |
| `download-model.sh.tmpl` | `{{HF_REPO}}` / `{{MS_REPO}}` / `{{MODEL_FILE}}` 等 | modelscope 优先 |
| `bench.sh.tmpl` | `{{CONTAINER_NAME}}` / `{{MODEL_FILE}}` | chat_template_kwargs 按族调整 |
| `.dockerignore` | 无 | 直接复用，无需修改 |
| `README.md.tmpl` | `{{MODEL_HUMAN_NAME}}` / 性能数据章节 | 性能数据运行后填 |

---

## 触发后的第一步

进入 Phase 1 之前，**先读 `AGENTS.md`**（仓库根），它是单一真实源。本 skill 仅补充流程指引，任何与 AGENTS.md 冲突的地方以 AGENTS.md 为准。
