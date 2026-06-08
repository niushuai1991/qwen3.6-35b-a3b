#!/usr/bin/env bash
# download-model.sh - 下载 all-MiniLM-L6-v2 F32 GGUF 文件
#
# 使用 hf-mirror.com 下载，已存在的文件自动跳过。
#
# 可覆盖的环境变量（默认值与 .env 保持一致）：
#   TARGET_DIR    /home/ns/models/all-MiniLM-L6-v2-f32
#   MODEL_FILE    all-MiniLM-L6-v2-f32.gguf
#   HF_REPO       niushuai1991/all-MiniLM-L6-v2-f32-GGUF
#   HF_ENDPOINT   https://hf-mirror.com
#
# 用法：
#   ./download-model.sh                     # 下载
#   TARGET_DIR=/data/minilm ./download-model.sh   # 改路径

set -euo pipefail

TARGET_DIR="${TARGET_DIR:-/home/ns/models/all-MiniLM-L6-v2-f32}"
MODEL_FILE="${MODEL_FILE:-all-MiniLM-L6-v2-f32.gguf}"
HF_REPO="${HF_REPO:-niushuai1991/all-MiniLM-L6-v2-f32-GGUF}"
HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"

log()  { printf '[download] %s\n' "$*"; }
warn() { printf '[download] WARN: %s\n' "$*" >&2; }
die()  { printf '[download] ERROR: %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

ensure_hf() {
    if ! have hf; then
        warn "hf 未安装"
        warn "  pip install -U 'huggingface_hub[cli]'"
        return 1
    fi
}

mkdir -p "$TARGET_DIR"

if [ -f "$TARGET_DIR/$MODEL_FILE" ]; then
    log "skip (exists): $MODEL_FILE"
else
    log "downloading: $MODEL_FILE"
    ensure_hf || die "请先安装 huggingface_hub CLI"
    log "  → HF: ${HF_REPO} / ${MODEL_FILE}"
    HF_ENDPOINT="$HF_ENDPOINT" hf download \
        "$HF_REPO" "$MODEL_FILE" \
        --local-dir "$TARGET_DIR" \
        || die "download failed"
    log "  ok"
fi

log "done. contents of $TARGET_DIR:"
ls -lh "$TARGET_DIR"
