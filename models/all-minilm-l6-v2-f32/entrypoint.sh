#!/usr/bin/env bash
# entrypoint.sh - 启动 llama-server 加载 all-MiniLM-L6-v2 F32 embedding 模型
#
# 环境变量（带默认值）：
#   MODEL_DIR       /models
#   MODEL_FILE      all-MiniLM-L6-v2-f32.gguf
#   HOST            0.0.0.0
#   PORT            8080
#   CONTEXT_SIZE    256
#   EXTRA_ARGS      透传给 llama-server 的额外参数

set -euo pipefail

log() { printf '[entrypoint] %s\n' "$*"; }
die() { printf '[entrypoint] ERROR: %s\n' "$*" >&2; exit 1; }

MODEL_DIR="${MODEL_DIR:-/models}"
MODEL_FILE="${MODEL_FILE:-all-MiniLM-L6-v2-f32.gguf}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8080}"
CONTEXT_SIZE="${CONTEXT_SIZE:-256}"
EXTRA_ARGS="${EXTRA_ARGS:-}"

MODEL_PATH="${MODEL_DIR}/${MODEL_FILE}"

# 文件检查
[ -f "$MODEL_PATH" ] || die "model file not found: $MODEL_PATH"
log "model: $MODEL_PATH"

log "host=${HOST} port=${PORT} context=${CONTEXT_SIZE} embeddings=true"
[ -n "$EXTRA_ARGS" ] && log "extra args: ${EXTRA_ARGS}"

# 启动 llama-server（exec 让信号直传）
# shellcheck disable=SC2086
exec llama-server \
    --model "$MODEL_PATH" \
    --host "$HOST" \
    --port "$PORT" \
    -c "$CONTEXT_SIZE" \
    -fa on \
    --embeddings \
    $EXTRA_ARGS
