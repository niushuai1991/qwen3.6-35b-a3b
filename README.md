# llm-docker

> 各种 LLM 的 Docker 部署合集

每个模型独立目录，自带 Dockerfile / docker-compose / 下载与基准脚本。多阶段构建（CUDA 编译），运行期镜像精简。

---

## 模型索引

| 模型 | 推理引擎 | 量化 | 显存需求 | 状态 | 目录 |
|---|---|---|---|---|---|
| Qwen3.6-35B-A3B | llama.cpp `b9542` | IQ3_S (~13.7 GB) | ~15.4 GB | ✅ 已验证（RTX 4080 16G，32–49 t/s） | [models/qwen3.6-35b-a3b](./models/qwen3.6-35b-a3b) |
| Gemma-4-12B-it | llama.cpp `b9542` | Q4_K_M (~7.5 GB) | ~9 GB | ✅ 已验证（RTX 4080 16G，35–43 t/s） | [models/gemma-4-12b-it](./models/gemma-4-12b-it) |

> 新增模型时在此追加一行。

---

## 快速使用

```bash
# 1) 克隆仓库
git clone https://github.com/niushuai1991/llm-docker.git
cd llm-docker

# 2) 选一个模型进入对应目录
cd models/qwen3.6-35b-a3b

# 3) 后续步骤（配置 .env → 下载模型 → 构建启动）见该模型自己的 README.md
```

每个模型的部署步骤、配置项、性能数据见各自目录下的 `README.md`。

---

## 通用文档

- [前置条件（Docker / NVIDIA Container Toolkit / CDI）](./docs/prerequisites.md)
- [GPU 架构与 CUDA 编译参数](./docs/gpu-architectures.md)
- [WSL2 注意事项](./docs/wsl2-notes.md)

---

## 仓库结构

```
llm-docker/
├── README.md                       # 本文件（模型索引）
├── docs/                           # 跨模型通用文档
│   ├── prerequisites.md
│   ├── gpu-architectures.md
│   └── wsl2-notes.md
└── models/
    └── qwen3.6-35b-a3b/            # 每个模型一个独立目录
        ├── README.md               # 该模型的详细说明
        ├── Dockerfile
        ├── docker-compose.yml
        ├── .env.example
        ├── entrypoint.sh
        ├── download-model.sh
        └── bench.sh
```

新增模型：在 `models/` 下新建一个目录，参考现有目录的结构即可。
