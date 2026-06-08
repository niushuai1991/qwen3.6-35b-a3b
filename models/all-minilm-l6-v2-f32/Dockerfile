# syntax=docker/dockerfile:1.6
#
# all-MiniLM-L6-v2 F32 Embedding 部署镜像
# - 多阶段构建：builder 编译 llama.cpp (CUDA)，runtime 仅保留二进制
# - 模型通过 volume 挂载，不打入镜像
#
# Build args（可在 docker-compose.yml / .env 中覆盖）:
#   LLAMA_CPP_REF     llama.cpp git tag/commit    (默认 b9542)
#   CUDA_VERSION      CUDA 主版本号               (默认 12.8.1)
#   UBUNTU_VERSION    Ubuntu 基础版本             (默认 22.04)
#   CUDA_ARCHITECTURES 目标 GPU 架构              (默认 89，对应 RTX 4080)
#                     - 5060 Ti Blackwell 用 120（需 CUDA 12.10+ builder）
#                     - 多卡混合用分号分隔，如 "89;90"
#                     - 注意：builder 内 cmake 3.22，不带 "-realtime" 后缀

ARG LLAMA_CPP_REF=b9542
ARG CUDA_VERSION=12.8.1
ARG UBUNTU_VERSION=22.04
ARG CUDA_ARCHITECTURES=89

############################
# Builder: 编译 llama.cpp (CUDA)
############################
FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu${UBUNTU_VERSION} AS builder

ARG LLAMA_CPP_REF
ARG CUDA_ARCHITECTURES

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        git build-essential cmake ca-certificates \
        libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*

# CUDA devel 镜像里 libcuda.so 是 stub，链接器在编译期需要它在标准路径
# 用 symlink 暴露给 ld（运行期由 nvidia container runtime 注入真实驱动库）
RUN ln -sf /usr/local/cuda/lib64/stubs/libcuda.so \
           /usr/local/cuda/lib64/libcuda.so.1 \
 && ldconfig

# 源码在宿主机已 clone 到 llama.cpp-src/（避免在 builder 里访问外网）
# 如需更新源码：cd llama.cpp-src && git fetch --depth 1 origin ${LLAMA_CPP_REF} && git checkout FETCH_HEAD
COPY llama.cpp-src/ /src/

WORKDIR /src

# CUDA 编译，启用 FA / CURL
RUN cmake -S . -B build \
        -DGGML_CUDA=ON \
        -DLLAMA_CURL=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCHITECTURES}" \
        -DCMAKE_INSTALL_PREFIX=/opt/llama.cpp \
    && cmake --build build --config Release -j"$(nproc)" \
    && cmake --install build --prefix /opt/llama.cpp --config Release

############################
# Runtime: 精简运行时
############################
FROM nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu${UBUNTU_VERSION}

ARG CUDA_ARCHITECTURES

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai

RUN apt-get update && apt-get install -y --no-install-recommends \
        libcurl4 libgomp1 ca-certificates curl tzdata \
    && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && rm -rf /var/lib/apt/lists/*

# 拷贝编译产物
COPY --from=builder /opt/llama.cpp/ /usr/local/

ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib/llama.cpp \
    PATH=/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin

RUN mkdir -p /models

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
