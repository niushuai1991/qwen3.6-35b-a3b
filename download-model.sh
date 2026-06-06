#!/usr/bin/env bash
# download-model.sh - 下载 Qwen3.6-35B-A3B 的两个 gguf 文件
#
# 优先级：modelscope（国内 CDN 快） → HF 镜像兜底
# 已存在的文件自动跳过，天然支持断点续传
#
# 可覆盖的环境变量（默认值与 .env 保持一致）：
#   TARGET_DIR   /home/ns/models/Qwen3.6-35B-A3B
#   MODEL_FILE   Qwen3.6-35B-A3B-UD-IQ3_S.gguf
#   MMPROJ_FILE  mmproj-F16.gguf
#   HF_REPO      unsloth/Qwen3.6-35B-A3B-GGUF
#   HF_ENDPOINT  https://hf-mirror.com
#   MS_REPO      unsloth/Qwen3.6-35B-A3B-GGUF（空：跳过 modelscope）
#
# 用法：
#   ./download-model.sh                         # 下载全部
#   TARGET_DIR=/data/qwen ./download-model.sh   # 改路径
#   MODEL_FILE=Qwen3.6-35B-A3B-UD-Q3_K_M.gguf ./download-model.sh  # 换量化

set -euo pipefail

TARGET_DIR="${TARGET_DIR:-/home/ns/models/Qwen3.6-35B-A3B}"
MODEL_FILE="${MODEL_FILE:-Qwen3.6-35B-A3B-UD-IQ3_S.gguf}"
MMPROJ_FILE="${MMPROJ_FILE:-mmproj-F16.gguf}"
HF_REPO="${HF_REPO:-unsloth/Qwen3.6-35B-A3B-GGUF}"
HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
MS_REPO="${MS_REPO:-unsloth/Qwen3.6-35B-A3B-GGUF}"

FILES=("$MODEL_FILE" "$MMPROJ_FILE")

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

ensure_ms() {
    if ! have modelscope; then
        warn "modelscope 未安装"
        warn "  pip install -U modelscope"
        return 1
    fi
}

try_hf() {
    local file="$1"
    ensure_hf || return 1
    log "  → HF: ${HF_REPO} / ${file}"
    HF_ENDPOINT="$HF_ENDPOINT" hf download \
        "$HF_REPO" "$file" \
        --local-dir "$TARGET_DIR"
}

try_ms() {
    local file="$1"
    [ -n "$MS_REPO" ] || { warn "MS_REPO 为空，跳过 modelscope"; return 1; }
    ensure_ms || return 1
    log "  → MS: ${MS_REPO} / ${file}"
    modelscope download \
        --model "$MS_REPO" \
        "$file" \
        --local_dir "$TARGET_DIR"
}

mkdir -p "$TARGET_DIR"

failed=()
for f in "${FILES[@]}"; do
    if [ -f "$TARGET_DIR/$f" ]; then
        log "skip (exists): $f"
        continue
    fi

    log "downloading: $f"
    if try_ms "$f"; then
        log "  ok via MS"
    elif try_hf "$f"; then
        log "  ok via HF"
    else
        warn "all sources failed for: $f"
        failed+=("$f")
    fi
done

if [ "${#failed[@]}" -gt 0 ]; then
    die "failed files: ${failed[*]}"
fi

log "done. contents of $TARGET_DIR:"
ls -lh "$TARGET_DIR"
