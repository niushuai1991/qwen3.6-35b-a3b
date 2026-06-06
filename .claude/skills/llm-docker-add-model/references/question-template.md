# Phase 2 决策提问模板

向用户提问时用 `question` 工具，一次发 4 个问题，每个都给推荐项 + 简短说明。下表是各问题的标准选项维度，**实际选项内容必须基于 Phase 1 的研究结果填充**（如具体的 GGUF 仓库名、可用的量化档位、最小支持 llama.cpp tag）。

## 4 个标准问题

### Q1: Base vs IT（基础 vs 指令微调）

| 推荐标签 | 描述要点 |
|---|---|
| IT 版本（推荐） | 已对齐聊天场景，绝大多数用户需要 |
| Base 版本 | 仅做续写，做 fine-tune 或自研 prompt 模板的人需要 |

**前提**：研究脚本输出里 `pipeline_tag` 不是 `text-generation`（如 `image-text-to-text`），且 HF 上同时存在 base 和 -it 仓库。

### Q2: GGUF 来源仓库

候选来自研究脚本的 "GGUF Sources" 节，按这个优先级给推荐：

1. `ggml-org/<model>-GGUF`（官方，但档位少）
2. `unsloth/<model>-GGUF`（社区最常用，档位最全，modelscope 通常有镜像）
3. `bartowski/<model>-GGUF`（社区口碑好）
4. 其他（每个选项要有理由）

### Q3: 默认量化档位

按目标显存推荐，研究脚本的 "params / dtype" 输出 + 目标 GPU 给参考：

| GPU | 推荐档 | 估算模型大小 |
|---|---|---|
| 8-12G | IQ2_XS / Q2_K | ~30-40% of FP16 |
| 16G | Q4_K_M / IQ4_XS | ~50% |
| 24G | Q5_K_M / Q6_K | ~65-75% |
| 48G+ | Q8_0 / BF16 | 100% / 无损 |

### Q4: LLAMA_CPP_REF

研究脚本的 "llama.cpp Support" 节会报告：

- ✅ 已支持 → 给当前 master 的最新 release tag
- ⚠️ 需升级 → 给包含目标 arch commit 的最小 release tag
- ❌ 不支持 → 不该走到这里（Phase 1 就该终止）

## 提问示例（参考真实 case）

```json
{
  "questions": [
    {
      "header": "Base vs IT",
      "question": "用 base 模型（google/gemma-4-12B）还是 instruction-tuned（google/gemma-4-12B-it）？",
      "options": [
        {"label": "IT 版本（推荐）", "description": "gemma-4-12B-it，已对齐聊天/助手场景"},
        {"label": "Base 版本", "description": "gemma-4-12B，仅做续写"}
      ]
    },
    {
      "header": "GGUF 来源",
      "question": "GGUF 默认从哪个仓库下载？",
      "options": [
        {"label": "unsloth（推荐）", "description": "档位最全，modelscope 通常有镜像"},
        {"label": "ggml-org 官方", "description": "只有 Q4_K_M / Q8_0 / bf16 三档"},
        {"label": "bartowski", "description": "档位齐全"}
      ]
    },
    {
      "header": "默认量化",
      "question": "默认量化档位（写入 .env.example）选哪个？",
      "options": [
        {"label": "Q4_K_M（推荐）", "description": "约 7.5 GB，16G 卡留足 KV cache"},
        {"label": "IQ4_XS", "description": "约 6.5 GB，速度优先"},
        {"label": "Q5_K_M", "description": "约 8.7 GB，质量更好"}
      ]
    },
    {
      "header": "llama.cpp 版本",
      "question": "LLAMA_CPP_REF 用什么版本？",
      "options": [
        {"label": "b9847（推荐）", "description": "确认包含 Gemma-4 支持的最小 release"},
        {"label": "保持 b9542", "description": "和现有 Qwen 一致，但需先验证"}
      ]
    }
  ]
}
```

## 注意

- 推荐项放第一个，加 "(推荐)" 后缀
- 每个选项描述控制在 1 行（30 字以内），用户秒懂
- 不要给 4 个以上的选项，会决策疲劳
- 如果研究脚本只发现 1 个 GGUF 仓库，Q2 直接跳过
