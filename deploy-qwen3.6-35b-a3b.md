# 16G 显存部署 Qwen3.6 35B A3B

> 5060 Ti 16G + llama.cpp，速度 50+ tokens/s

## 硬件

- 显卡：RTX 5060 Ti 16G
- 框架：llama.cpp

## 模型文件

- `Qwen3.6-35B-A3B-APEX-I-Compact.gguf`
- `Qwen3.6-35B-A3B-APEX-I-Compact-mmproj.gguf`

## 启动参数

```bash
./llamacpp/llama-server.exe \
  --model ./model/Qwen3.6-35B-A3B-APEX-I-C/Qwen3.6-35B-A3B-APEX-I-Compact.gguf \
  --mmproj ./model/Qwen3.6-35B-A3B-APEX-I-C/Qwen3.6-35B-A3B-APEX-I-Compact-mmproj.gguf \
  --port ${PORT} \
  --reasoning-budget 0 \
  --no-kv-offload \
  -ctk q8_0 -ctv q8_0 \
  -c 256000 \
  --fa on
```

## 参数说明

| 参数 | 说明 |
|------|------|
| `--no-kv-offload` | KV cache 不 offload 到 GPU，省显存 |
| `-ctk q8_0 -ctv q8_0` | KV cache 量化至 8-bit，减少显存占用 |
| `-c 256000` | 上下文长度 256K |
| `--fa on` | 启用 Flash Attention |
| `--reasoning-budget 0` | 禁用推理预算（thinking），只输出最终回答 |

## KV Cache 内存估算 (q8_0, 256K 上下文)

模型架构参数（来自 [config.json](https://hf-mirror.com/Qwen/Qwen3.6-35B-A3B/raw/main/config.json)）：

| 参数 | 值 |
|------|-----|
| num_hidden_layers | 40 |
| full_attention 层数 | 10（每 4 层 1 个） |
| linear_attention 层数 | 30 |
| num_key_value_heads (full attn) | 2 |
| head_dim (full attn) | 256 |

**公式：** `KV = 2 × num_kv_heads × head_dim × context_length × 1 字节`

```
每层 full attention: 2 × 2 × 256 × 256000 × 1 = 262,144,000 字节 ≈ 250 MB
10 层 full attention: ~2.5 GB
```

Linear attention 层使用固定大小的递归状态（类似 Mamba），不随上下文长度增长，占用可忽略。

**KV cache 总计：约 2.5 GB**，配合 Q4_K_M 模型约 ~20 GB，16G 显存 + 32G 内存可跑。
