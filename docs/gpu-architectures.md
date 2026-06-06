# GPU 架构与 CUDA 编译参数

llama.cpp 等需要本地编译 CUDA 内核的镜像，构建时通过 build arg `CUDA_ARCHITECTURES` 指定目标 GPU 架构。

> 改架构后必须 `docker compose build --no-cache` 重建，否则 builder 层会命中缓存。

---

## 架构对照表

| 显卡系列 | 架构代码 |
|---|---|
| RTX 40 系列（4080/4090/4070 ...） | `89` |
| RTX 30 系列（3090/3080/3060 ...） | `86` |
| RTX 50 系列（Blackwell） | `120`（**需 CUDA 12.10+ builder**） |
| A100 / H100 | `80` / `90` |
| 多卡混合 | `86;89`（分号分隔） |

> 注意：builder 内 cmake 3.22 不带 `-realtime` 后缀。
